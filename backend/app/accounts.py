"""Rules about who may change whom. Kept in one place so every admin route applies the same checks.

* The owner (first administrator) cannot be demoted, suspended, reset or deleted by anyone, and nobody can do those to themselves.
* Any administrator can manage students.
* An administrator can manage another administrator only if they promoted them, directly or through a chain of promotions
  ("the admin I set, or the admin they set before"). The owner can manage every administrator.
"""
from sqlalchemy import select
from sqlalchemy.orm import Session

from .deps import err
from .models import AccountStatus, RefreshToken, Role, User, utcnow


def promotion_ancestors(db: Session, user: User) -> list[int]:
    """Ids of everyone above `user` in the promotion chain, nearest first. Cycle-safe."""
    out, seen, cur = [], {user.id}, user.promoted_by_id
    while cur is not None and cur not in seen:
        out.append(cur)
        seen.add(cur)
        cur = db.scalar(select(User.promoted_by_id).where(User.id == cur))
    return out


def can_manage(db: Session, actor: User, target: User) -> tuple[bool, str | None]:
    if target.id == actor.id:
        return False, "You cannot do this to your own account."
    if target.is_owner:
        return False, "The owner account is protected."
    if target.role == Role.student:
        return True, None
    if actor.is_owner or actor.id in promotion_ancestors(db, target):
        return True, None
    return False, "You can only manage administrators that you promoted, or that an administrator you promoted set."


def require_manage(db: Session, actor: User, target: User) -> None:
    ok, why = can_manage(db, actor, target)
    if not ok:
        raise err(403, "not_allowed", why or "Not allowed.")


def revoke_sessions(db: Session, user_id: int) -> int:
    n = 0
    for t in db.scalars(select(RefreshToken).where(RefreshToken.user_id == user_id, RefreshToken.revoked_at.is_(None))):
        t.revoked_at = utcnow()
        n += 1
    return n


def lift_expired_suspension(user: User) -> bool:
    """A suspension with an end date ends by itself. Returns True when the account was re-activated."""
    if user.status == AccountStatus.inactive and user.suspended_until is not None and user.suspended_until <= utcnow():
        clear_suspension(user)
        return True
    return False


def clear_suspension(user: User) -> None:
    user.status = AccountStatus.active
    user.suspended_reason = user.suspended_at = user.suspended_until = user.suspended_by_id = None


def suspension_message(user: User) -> str:
    msg = "This account has been suspended."
    if user.suspended_reason:
        msg += f" Reason: {user.suspended_reason}."
    if user.suspended_until:
        msg += f" It ends on {user.suspended_until.date().isoformat()}."
    return msg + " Please contact your administrator."


def demote_admin(db: Session, target: User) -> None:
    """Admin -> student. Admins promoted by `target` move up to the demoted admin's own promoter (or the owner)."""
    new_parent = target.promoted_by_id
    if new_parent is None:
        new_parent = db.scalar(select(User.id).where(User.is_owner.is_(True)))
    for child in db.scalars(select(User).where(User.promoted_by_id == target.id)):
        child.promoted_by_id = new_parent
    target.role = Role.student
    target.promoted_by_id = None
    revoke_sessions(db, target.id)      # the admin session must not outlive the role
