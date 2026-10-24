"""Administrator view of every account: details, role changes (with the promotion-chain rules), suspend / activate, delete.

Rules (see accounts.py): the owner is untouchable, nobody acts on themselves, any admin manages students, and an admin
manages another admin only when they promoted them directly or indirectly. The owner manages every admin.
"""
from datetime import datetime, timedelta, timezone
from typing import Literal

from fastapi import APIRouter, Depends, Query, Request, Response
from pydantic import BaseModel, Field
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from ..accounts import (can_manage, clear_suspension, demote_admin, promotion_ancestors, require_manage, revoke_sessions)
from ..db import get_db
from ..deps import admin_user, audit, err
from ..models import AccountStatus, AppState, Role, User, utcnow
from ..schemas import Page
from ..security import generate_temp_password, hash_password
from ..stats import user_progress

router = APIRouter(prefix="/admin/users", tags=["admin users"], dependencies=[Depends(admin_user)])


class RoleIn(BaseModel):
    role: Literal["student", "admin"]


class SuspendIn(BaseModel):
    reason: str | None = Field(default=None, max_length=200)
    until: datetime | None = None           # None = until re-activated by an administrator
    days: int | None = Field(default=None, ge=1, le=3650)   # convenience: suspend for N days


def _out(db: Session, u: User, actor: User, names: dict[int, str] | None = None) -> dict:
    ok, why = can_manage(db, actor, u)
    parent = (names or {}).get(u.promoted_by_id) if u.promoted_by_id else None
    if u.promoted_by_id and parent is None:
        parent = db.scalar(select(User.full_name).where(User.id == u.promoted_by_id))
    suspended = u.status == AccountStatus.inactive
    return {"id": u.id, "full_name": u.full_name, "username": u.username, "phone": u.phone, "role": u.role.value, "is_owner": u.is_owner,
            "status": "suspended" if suspended else "active", "suspended_reason": u.suspended_reason, "suspended_at": u.suspended_at,
            "suspended_until": u.suspended_until, "selected_grade": u.selected_grade, "selected_track": u.selected_track,
            "promoted_by": {"id": u.promoted_by_id, "name": parent} if u.promoted_by_id else None,
            "must_change_password": u.must_change_password, "created_at": u.created_at, "last_active_at": u.last_active_at,
            "can_manage": ok, "cannot_manage_reason": why}


@router.get("")
def list_users(q: str | None = None, role: Literal["student", "admin"] | None = None, status: Literal["active", "suspended"] | None = None,
               grade: int | None = None, track: Literal["natural", "social"] | None = None,
               sort: Literal["created", "name", "active"] = "created", order: Literal["asc", "desc"] = "desc",
               page: int = Query(1, ge=1), size: int = Query(20, ge=1, le=100), db: Session = Depends(get_db), admin: User = Depends(admin_user)):
    st = select(User)
    if q:
        like = f"%{q.strip().replace('%', '').replace('_', '')}%"
        st = st.where(or_(User.full_name.ilike(like), User.username.ilike(like), User.phone.like(like)))
    if role:
        st = st.where(User.role == Role(role))
    if status:
        st = st.where(User.status == (AccountStatus.inactive if status == "suspended" else AccountStatus.active))
    if grade:
        st = st.where(User.selected_grade == grade)
    if track:
        st = st.where(User.selected_track == track)
    col = {"created": User.created_at, "name": User.full_name, "active": User.last_active_at}[sort]
    st = st.order_by((col.asc() if order == "asc" else col.desc()).nulls_last(), User.id.desc())
    total = db.scalar(select(func.count()).select_from(st.subquery()))
    rows = db.scalars(st.offset((page - 1) * size).limit(size)).all()
    names = {u.id: u.full_name for u in db.scalars(select(User).where(User.role == Role.admin))}
    return Page(items=[_out(db, u, admin, names) for u in rows], total=total, page=page, size=size)


def _get(db: Session, uid: int) -> User:
    u = db.get(User, uid)
    if not u:
        raise err(404, "not_found", "User not found.")
    return u


@router.get("/{user_id:int}")
def user_detail(user_id: int, db: Session = Depends(get_db), admin: User = Depends(admin_user)):
    u = _get(db, user_id)
    st = db.scalar(select(AppState.data).where(AppState.user_id == u.id))
    return {**_out(db, u, admin), "progress": user_progress(db, st or {}),
            "promotion_chain": [{"id": a, "name": db.scalar(select(User.full_name).where(User.id == a))} for a in promotion_ancestors(db, u)]}


@router.post("/{user_id:int}/role")
def set_role(user_id: int, body: RoleIn, request: Request, db: Session = Depends(get_db), admin: User = Depends(admin_user)):
    target = _get(db, user_id)
    if target.id == admin.id:
        raise err(403, "not_allowed", "You cannot change your own role.")
    if target.is_owner:
        raise err(403, "not_allowed", "The owner account is protected.")
    new = Role(body.role)
    if new == target.role:
        return _out(db, target, admin)
    if new == Role.admin:                      # promote: any administrator may promote a student; it is recorded who did it
        if target.status != AccountStatus.active:
            raise err(409, "suspended", "Activate this account before making it an administrator.")
        target.role, target.promoted_by_id = Role.admin, admin.id
        revoke_sessions(db, target.id)         # fresh sign-in picks up the admin role cleanly
        audit(db, admin, "user.promote", "user", target.id, {"to": "admin"}, request)
    else:
        require_manage(db, admin, target)
        children = db.scalars(select(User.id).where(User.promoted_by_id == target.id)).all()
        demote_admin(db, target)
        audit(db, admin, "user.demote", "user", target.id, {"to": "student", "admins_moved_up": list(children)}, request)
    db.commit()
    return _out(db, target, admin)


@router.post("/{user_id:int}/suspend")
def suspend(user_id: int, body: SuspendIn, request: Request, db: Session = Depends(get_db), admin: User = Depends(admin_user)):
    target = _get(db, user_id)
    require_manage(db, admin, target)
    until = body.until
    if body.days:
        until = utcnow() + timedelta(days=body.days)
    if until is not None:
        until = until if until.tzinfo else until.replace(tzinfo=timezone.utc)
        if until <= utcnow():
            raise err(422, "bad_date", "The end date must be in the future.")
    target.status, target.suspended_at, target.suspended_by_id = AccountStatus.inactive, utcnow(), admin.id
    target.suspended_reason, target.suspended_until = (body.reason or "").strip() or None, until
    revoke_sessions(db, target.id)              # signed out everywhere at once; their next request is refused
    audit(db, admin, "user.suspend", "user", target.id, {"reason": target.suspended_reason, "until": until.isoformat() if until else None}, request)
    db.commit()
    return _out(db, target, admin)


@router.post("/{user_id:int}/activate")
def activate(user_id: int, request: Request, db: Session = Depends(get_db), admin: User = Depends(admin_user)):
    target = _get(db, user_id)
    require_manage(db, admin, target)
    clear_suspension(target)
    audit(db, admin, "user.activate", "user", target.id, None, request)
    db.commit()
    return _out(db, target, admin)


@router.post("/{user_id:int}/reset-password")
def reset_password(user_id: int, request: Request, db: Session = Depends(get_db), admin: User = Depends(admin_user)):
    """One-time temporary password, shown once and never stored in plain text. The user must choose a new one at next sign-in."""
    target = _get(db, user_id)
    require_manage(db, admin, target)
    temp = generate_temp_password()
    target.password_hash, target.must_change_password = hash_password(temp), True
    revoke_sessions(db, target.id)
    audit(db, admin, "user.password_reset", "user", target.id, None, request)
    db.commit()
    return {"temporary_password": temp, "note": "Give this to the user privately. They must set a new password when they sign in."}


@router.post("/{user_id:int}/force-password-change")
def force_password_change(user_id: int, request: Request, db: Session = Depends(get_db), admin: User = Depends(admin_user)):
    target = _get(db, user_id)
    require_manage(db, admin, target)
    target.must_change_password = True
    audit(db, admin, "user.force_password_change", "user", target.id, None, request)
    db.commit()
    return _out(db, target, admin)


@router.post("/{user_id:int}/logout-everywhere")
def logout_everywhere(user_id: int, request: Request, db: Session = Depends(get_db), admin: User = Depends(admin_user)):
    target = _get(db, user_id)
    require_manage(db, admin, target)
    n = revoke_sessions(db, target.id)
    audit(db, admin, "user.logout_everywhere", "user", target.id, {"sessions": n}, request)
    db.commit()
    return {"revoked_sessions": n}


@router.delete("/{user_id:int}", status_code=204)
def delete_user(user_id: int, request: Request, confirm: bool = Query(False), db: Session = Depends(get_db), admin: User = Depends(admin_user)):
    target = _get(db, user_id)
    require_manage(db, admin, target)
    if not confirm:
        raise err(400, "confirmation_required", "Add confirm=true to delete this account permanently.")
    if target.role == Role.admin:           # admins it promoted move up, exactly like a demotion
        demote_admin(db, target)
    audit(db, admin, "user.delete", "user", target.id, {"username": target.username, "role": target.role.value}, request)
    db.delete(target)
    db.commit()
    return Response(status_code=204)
