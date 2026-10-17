from datetime import timedelta

import jwt
from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from .db import get_db
from .models import AccountStatus, AuditLog, Role, User, utcnow
from .security import decode_access_token

bearer = HTTPBearer(auto_error=False)
PASSWORD_CHANGE_ALLOWED = ("/auth/change-password", "/auth/logout", "/me", "/auth/refresh")


def err(status: int, code: str, message: str, **extra):
    return HTTPException(status, detail={"code": code, "message": message, **extra})


def _load_user(request: Request, creds: HTTPAuthorizationCredentials | None, db: Session) -> User:
    if creds is None:
        raise err(401, "not_authenticated", "Please sign in to continue.")
    try:
        data = decode_access_token(creds.credentials)
    except jwt.ExpiredSignatureError:
        raise err(401, "token_expired", "Your session has expired. Please sign in again.")
    except jwt.PyJWTError:
        raise err(401, "invalid_token", "Invalid sign-in token.")
    user = db.get(User, int(data["sub"]))
    # Role and status always come from the database, never from the token or the client.
    if user is None or user.status != AccountStatus.active:
        raise err(401, "account_unavailable", "This account is not available.")
    now = utcnow()
    if user.last_active_at is None or now - user.last_active_at > timedelta(minutes=5):
        user.last_active_at = now
        db.commit()
    return user


def current_user(request: Request, creds: HTTPAuthorizationCredentials | None = Depends(bearer), db: Session = Depends(get_db)) -> User:
    user = _load_user(request, creds, db)
    if user.must_change_password and not request.url.path.endswith(PASSWORD_CHANGE_ALLOWED):
        raise err(403, "password_change_required", "You must change your temporary password before continuing.")
    return user


def student_user(user: User = Depends(current_user)) -> User:
    if user.role != Role.student:
        raise err(403, "student_only", "This endpoint is for student accounts.")
    return user


def admin_user(request: Request, creds: HTTPAuthorizationCredentials | None = Depends(bearer), db: Session = Depends(get_db)) -> User:
    user = _load_user(request, creds, db)
    if user.role != Role.admin:
        raise err(403, "admin_only", "Administrator access is required.")
    return user


def audit(db: Session, admin: User | None, action: str, entity: str | None = None, entity_id=None, details: dict | None = None,
          request: Request | None = None) -> None:
    db.add(AuditLog(admin_id=admin.id if admin else None, admin_name=admin.full_name if admin else None, action=action, entity=entity,
                    entity_id=str(entity_id) if entity_id is not None else None, details=details,
                    ip=(request.client.host if request and request.client else None)))
