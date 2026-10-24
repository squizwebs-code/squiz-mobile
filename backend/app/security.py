import hashlib
import re
import secrets
import uuid
from datetime import datetime, timedelta, timezone

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError

from .config import get_settings

_ph = PasswordHasher()                      # Argon2id with library defaults
_DUMMY_HASH = _ph.hash("dummy-password-for-timing")


def hash_password(pw: str) -> str:
    return _ph.hash(pw)


def verify_password(pw: str, hashed: str | None) -> bool:
    """Constant-ish time: verifies against a dummy hash when the user does not exist."""
    try:
        return _ph.verify(hashed or _DUMMY_HASH, pw) and hashed is not None
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False


def needs_rehash(hashed: str) -> bool:
    return _ph.check_needs_rehash(hashed)


def password_problem(pw: str) -> str | None:
    """Any characters are fine; only the length is checked."""
    if len(pw) < 6:
        return "Password must be at least 6 characters"
    if len(pw) > 128:
        return "Password must be at most 128 characters"
    return None


def create_access_token(user_id: int, role: str) -> tuple[str, int]:
    s = get_settings()
    exp = datetime.now(timezone.utc) + timedelta(minutes=s.access_token_minutes)
    tok = jwt.encode({"sub": str(user_id), "role": role, "typ": "access", "jti": uuid.uuid4().hex, "exp": exp},
                     s.jwt_secret, algorithm=s.jwt_algorithm)
    return tok, s.access_token_minutes * 60


def decode_access_token(token: str) -> dict:
    s = get_settings()
    data = jwt.decode(token, s.jwt_secret, algorithms=[s.jwt_algorithm], options={"require": ["exp", "sub"]})
    if data.get("typ") != "access":
        raise jwt.InvalidTokenError("wrong token type")
    return data


def new_refresh_token() -> tuple[str, str]:
    raw = secrets.token_urlsafe(48)
    return raw, hash_refresh(raw)


def hash_refresh(raw: str) -> str:
    return hashlib.sha256(raw.encode()).hexdigest()


def generate_temp_password() -> str:
    alphabet = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    while True:
        pw = "".join(secrets.choice(alphabet) for _ in range(12))
        if password_problem(pw) is None:
            return pw
