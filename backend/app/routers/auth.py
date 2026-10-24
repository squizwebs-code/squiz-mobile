import uuid
from datetime import timedelta

from fastapi import APIRouter, Depends, Request, Response
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .. import ratelimit
from ..config import get_settings
from ..db import get_db
from ..accounts import lift_expired_suspension, revoke_sessions, suspension_message
from ..deps import audit, current_user, err
from ..models import AccountStatus, RefreshToken, Role, User, utcnow
from ..phone import PhoneError, looks_like_phone, name_key, normalize_phone, normalize_username
from ..schemas import ChangePasswordIn, LoginIn, RefreshIn, RegisterIn, TokenOut, UserOut
from ..security import (create_access_token, hash_password, hash_refresh, needs_rehash, new_refresh_token, verify_password)

router = APIRouter(tags=["auth"])


def issue_tokens(db: Session, user: User, scope: str, family: str | None = None) -> TokenOut:
    s = get_settings()
    access, ttl = create_access_token(user.id, user.role.value)
    raw, hashed = new_refresh_token()
    db.add(RefreshToken(user_id=user.id, token_hash=hashed, family_id=family or str(uuid.uuid4()),
                        expires_at=utcnow() + timedelta(days=s.refresh_token_days), scope=scope))
    db.commit()
    return TokenOut(access_token=access, refresh_token=raw, expires_in=ttl, user=UserOut.model_validate(user))


def authenticate(db: Session, request: Request, identifier: str, password: str, role: Role | None = None) -> User:
    """`identifier` is a phone number or a username. Pass `role` to accept only that kind of account."""
    ip = ratelimit.client_ip(request)
    ratelimit.check(f"login-ip:{ip}", 30, 300)
    ratelimit.check(f"login-id:{identifier.strip().casefold()}", 8, 300)
    user = None
    ident = identifier.strip()
    if looks_like_phone(ident):
        try:
            user = db.scalar(select(User).where(User.phone == normalize_phone(ident)))
        except PhoneError:
            user = None
    else:
        user = db.scalar(select(User).where(User.username == ident.lower()))
    if user is not None and role is not None and user.role != role:
        user = None
    ok = verify_password(password, user.password_hash if user else None)
    if not user or not ok:
        raise err(401, "invalid_credentials", "Incorrect username/phone number or password.")
    if lift_expired_suspension(user):
        db.commit()
    if user.status != AccountStatus.active:
        raise err(403, "account_inactive", suspension_message(user), reason=user.suspended_reason,
                  until=user.suspended_until.isoformat() if user.suspended_until else None)
    if needs_rehash(user.password_hash):
        user.password_hash = hash_password(password)
    return user


def scope_for(user: User) -> str:
    return "admin" if user.role == Role.admin else "student"


@router.post("/auth/register", response_model=TokenOut, status_code=201)
def register(body: RegisterIn, request: Request, db: Session = Depends(get_db)):
    ratelimit.check(f"register-ip:{ratelimit.client_ip(request)}", 10, 600)
    if db.scalar(select(User.id).where(User.phone == body.phone)):
        raise err(409, "phone_taken", "This phone number is already registered. Try signing in instead.")
    if db.scalar(select(User.id).where(User.username == body.username)):
        raise err(409, "username_taken", "That username is already taken. Please choose another.")
    # The role is always "student": it is not part of the request schema.
    user = User(full_name=body.full_name, username=body.username, name_key=name_key(body.full_name), phone=body.phone,
                password_hash=hash_password(body.password), role=Role.student)
    db.add(user)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        if db.scalar(select(User.id).where(User.username == body.username)):
            raise err(409, "username_taken", "That username is already taken. Please choose another.")
        raise err(409, "phone_taken", "This phone number is already registered. Try signing in instead.")
    return issue_tokens(db, user, "student")


@router.post("/auth/login", response_model=TokenOut)
def login(body: LoginIn, request: Request, db: Session = Depends(get_db)):
    """One sign-in for everyone. The response tells the app the account's role; the server checks the role again on every request."""
    user = authenticate(db, request, body.identifier, body.password)
    if user.role == Role.admin:
        audit(db, user, "admin.login", "user", user.id, request=request)
    return issue_tokens(db, user, scope_for(user))


@router.post("/auth/refresh", response_model=TokenOut)
def refresh(body: RefreshIn, request: Request, db: Session = Depends(get_db)):
    ratelimit.check(f"refresh-ip:{ratelimit.client_ip(request)}", 60, 300)
    row = db.scalar(select(RefreshToken).where(RefreshToken.token_hash == hash_refresh(body.refresh_token)))
    if row is None:
        raise err(401, "invalid_refresh", "Please sign in again.")
    if row.revoked_at is not None:
        # A rotated-out token was presented again: assume theft and kill the whole family.
        for t in db.scalars(select(RefreshToken).where(RefreshToken.family_id == row.family_id, RefreshToken.revoked_at.is_(None))):
            t.revoked_at = utcnow()
        db.commit()
        raise err(401, "invalid_refresh", "Please sign in again.")
    if row.expires_at <= utcnow():
        raise err(401, "invalid_refresh", "Your session has expired. Please sign in again.")
    user = db.get(User, row.user_id)
    if user is not None and lift_expired_suspension(user):
        db.commit()
    if user is None or user.status != AccountStatus.active or (row.scope == "admin" and user.role != Role.admin):
        raise err(401, "invalid_refresh", "Please sign in again.")
    row.revoked_at = utcnow()
    return issue_tokens(db, user, scope_for(user), family=row.family_id)


@router.post("/auth/logout", status_code=204)
def logout(body: RefreshIn, db: Session = Depends(get_db)):
    row = db.scalar(select(RefreshToken).where(RefreshToken.token_hash == hash_refresh(body.refresh_token)))
    if row and row.revoked_at is None:
        row.revoked_at = utcnow()
        db.commit()
    return Response(status_code=204)


@router.post("/auth/change-password", response_model=TokenOut)
def change_password(body: ChangePasswordIn, db: Session = Depends(get_db), user: User = Depends(current_user)):
    if not verify_password(body.current_password, user.password_hash):
        raise err(400, "wrong_password", "Your current password is incorrect.")
    if body.current_password == body.new_password:
        raise err(400, "same_password", "Choose a new password that is different from the current one.")
    user.password_hash = hash_password(body.new_password)
    user.must_change_password = False
    for t in db.scalars(select(RefreshToken).where(RefreshToken.user_id == user.id, RefreshToken.revoked_at.is_(None))):
        t.revoked_at = utcnow()          # sign out every other device
    db.commit()
    return issue_tokens(db, user, scope_for(user))


@router.post("/auth/logout-all", status_code=204)
def logout_all(db: Session = Depends(get_db), user: User = Depends(current_user)):
    """Signs the account out on every device (all refresh tokens are revoked)."""
    revoke_sessions(db, user.id)
    db.commit()
    return Response(status_code=204)


@router.get("/auth/username-available")
def username_available(username: str, request: Request, db: Session = Depends(get_db)):
    ratelimit.check(f"username-ip:{ratelimit.client_ip(request)}", 40, 300)
    try:
        u = normalize_username(username)
    except ValueError as e:
        return {"available": False, "reason": str(e)}
    return {"available": db.scalar(select(User.id).where(User.username == u)) is None, "reason": None}


@router.post("/admin/auth/login", response_model=TokenOut, tags=["admin"])
def admin_login(body: LoginIn, request: Request, db: Session = Depends(get_db)):
    user = authenticate(db, request, body.identifier, body.password, Role.admin)
    audit(db, user, "admin.login", "user", user.id, request=request)
    return issue_tokens(db, user, "admin")
