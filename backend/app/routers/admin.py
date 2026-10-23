"""Administrator API. Every route depends on `admin_user`, which re-checks the role in the database on each request."""
import os
import secrets
from datetime import timedelta
import io
import pandas as pd
import hashlib

from fastapi import APIRouter, Depends, File, Query, Request, Response, UploadFile
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from ..config import get_settings
from ..db import get_db
from ..deps import admin_user, audit, err
from ..models import (
    AccountStatus, AppSetting, AuditLog, Grade, GradeSubject, PublishStatus, Question, AnswerOption, QuizAttempt, RefreshToken, Role,
    SessionQuestion, StudentProgress, Subject, Unit, User, ImportBatch, utcnow
)
from ..routers.student import compute_stats
from ..schemas import (
    AssignIn, GradeIn, GradePatch, Page, ReorderIn, SettingsIn, StudentStatusIn, SubjectIn, SubjectPatch, UnitIn,
    UnitPatch
)
from ..security import generate_temp_password, hash_password

router = APIRouter(prefix="/admin", tags=["admin"], dependencies=[Depends(admin_user)])


def _me(admin: User = Depends(admin_user)) -> User:    # cached per request by FastAPI
    return admin


# ---------------- dashboard ----------------
@router.get("/dashboard")
def dashboard(db: Session = Depends(get_db)):
    now = utcnow()
    students = select(func.count()).select_from(User).where(User.role == Role.student)
    recent_attempts = db.execute(select(QuizAttempt, User.full_name).join(User, User.id == QuizAttempt.user_id)
                                 .order_by(QuizAttempt.submitted_at.desc()).limit(8)).all()
    return {
        "students": db.scalar(students),
        "active_students_7d": db.scalar(select(func.count()).select_from(User).where(User.role == Role.student, User.last_active_at >= now - timedelta(days=7))),
        "questions": db.scalar(select(func.count()).select_from(Question).where(Question.deleted_at.is_(None))),
        "published_questions": db.scalar(select(func.count()).select_from(Question).where(Question.deleted_at.is_(None), Question.status == PublishStatus.published)),
        "subjects": db.scalar(select(func.count()).select_from(Subject)),
        "units": db.scalar(select(func.count()).select_from(Unit)),
        "completed_quizzes": db.scalar(select(func.count()).select_from(QuizAttempt)),
        "recent_activity": [{"attempt_id": a.id, "student": n, "title": a.title, "mode": a.mode, "percentage": a.percentage, "at": a.submitted_at} for a, n in recent_attempts],
        "recent_admin_actions": [_audit_out(x) for x in db.scalars(select(AuditLog).order_by(AuditLog.id.desc()).limit(8))],
    }


# ---------------- admin governance & promotion chain ----------------
def _is_descendant(db: Session, actor_id: int, target_id: int) -> bool:
    """Check if target is in actor's promotion sub-tree."""
    current = target_id
    while current:
        u = db.get(User, current)
        if not u or not u.promoted_by_id:
            return False
        if u.promoted_by_id == actor_id:
            return True
        current = u.promoted_by_id
    return False


@router.get("/admins")
def list_admins(db: Session = Depends(get_db)):
    admins = db.scalars(select(User).where(User.role == Role.admin)).all()
    return [{
        "id": a.id,
        "full_name": a.full_name,
        "phone": a.phone,
        "is_owner": a.is_owner,
        "promoted_by_id": a.promoted_by_id,
        "status": a.status.value,
        "created_at": a.created_at
    } for a in admins]


@router.post("/admins/promote", status_code=201)
def promote_user(user_id: int, request: Request, db: Session = Depends(get_db), admin: User = Depends(_me)):
    u = db.get(User, user_id) or _nf("User")
    if u.role == Role.admin:
        raise err(400, "already_admin", "User is already an administrator.")
    u.role = Role.admin
    u.promoted_by_id = admin.id
    u.token_version += 1
    audit(db, admin, "admin.promote", "user", u.id, {"promoted_by": admin.id}, request)
    db.commit()
    return {"message": f"User {u.full_name} promoted to admin successfully."}


@router.post("/admins/{admin_id}/demote")
def demote_admin(admin_id: int, request: Request, db: Session = Depends(get_db), admin: User = Depends(_me)):
    target = db.get(User, admin_id) or _nf("Admin")
    if target.is_owner:
        raise err(403, "owner_protected", "Cannot demote the system owner.")
    if target.id == admin.id:
        raise err(403, "self_action_forbidden", "Cannot demote yourself.")
    if not admin.is_owner and not _is_descendant(db, admin.id, target.id):
        raise err(403, "forbidden_chain", "You can only demote administrators within your own promotion chain.")
    
    # Handle promoted admins pass-up: reassign their promoted_by_id to target's promoter
    sub_admins = db.scalars(select(User).where(User.promoted_by_id == target.id)).all()
    for sub in sub_admins:
        sub.promoted_by_id = target.promoted_by_id

    target.role = Role.student
    target.promoted_by_id = None
    target.token_version += 1
    
    # Revoke sessions
    for t in db.scalars(select(RefreshToken).where(RefreshToken.user_id == target.id, RefreshToken.revoked_at.is_(None))):
        t.revoked_at = utcnow()

    audit(db, admin, "admin.demote", "user", target.id, None, request)
    db.commit()
    return {"message": f"Admin {target.full_name} demoted to student successfully."}


# ---------------- grades ----------------
def _grade_out(g: Grade) -> dict:
    return {"id": g.id, "number": g.number, "name": g.name, "published": g.published}


@router.get("/grades")
def list_grades(db: Session = Depends(get_db)):
    return [_grade_out(g) for g in db.scalars(select(Grade).order_by(Grade.number))]


@router.post("/grades", status_code=201)
def create_grade(body: GradeIn, request: Request, db: Session = Depends(get_db), admin: User = Depends(_me)):
    if db.scalar(select(Grade.id).where(Grade.number == body.number)):
        raise err(409, "grade_exists", f"Grade {body.number} already exists.")
    g = Grade(**body.model_dump())
    db.add(g)
    db.flush()
    audit(db, admin, "grade.create", "grade", g.id, body.model_dump(), request)
    db.commit()
    return _grade_out(g)


@router.patch("/grades/{grade_id}")
def update_grade(grade_id: int, body: GradePatch, request: Request, db: Session = Depends(get_db), admin: User = Depends(_me)):
    g = db.get(Grade, grade_id) or _nf("Grade")
    for k, v in body.model_dump(exclude_unset=True).items():
        setattr(g, k, v)
    audit(db, admin, "grade.update", "grade", g.id, body.model_dump(exclude_unset=True), request)
    db.commit()
    return _grade_out(g)


def _nf(what: str):
    raise err(404, "not_found", f"{what} not found.")


# ---------------- subjects ----------------
def _subject_out(db: Session, s: Subject) -> dict:
    links = db.scalars(select(GradeSubject).where(GradeSubject.subject_id == s.id)).all()
    nums = {g.id: g.number for g in db.scalars(select(Grade))}
    return {"id": s.id, "key": s.key, "name": s.name, "icon": s.icon, "published": s.published,
            "grades": sorted([{"grade_id": l.grade_id, "number": nums[l.grade_id], "published": l.published} for l in links], key=lambda x: x["number"])}


@router.get("/subjects")
def list_subjects(db: Session = Depends(get_db)):
    return [_subject_out(db, s) for s in db.scalars(select(Subject).order_by(Subject.name))]


@router.post("/subjects", status_code=201)
def create_subject(body: SubjectIn, request: Request, db: Session = Depends(get_db), admin: User = Depends(_me)):
    if db.scalar(select(Subject.id).where(Subject.key == body.key)):
        raise err(409, "subject_exists", "A subject with this key already exists.")
    s = Subject(**body.model_dump())
    db.add(s)
    db.flush()
    audit(db, admin, "subject.create", "subject", s.id, body.model_dump(), request)
    db.commit()
    return _subject_out(db, s)


@router.patch("/subjects/{subject_id}")
def update_subject(subject_id: int, body: SubjectPatch, request: Request, db: Session = Depends(get_db), admin: User = Depends(_me)):
    s = db.get(Subject, subject_id) or _nf("Subject")
    for k, v in body.model_dump(exclude_unset=True).items():
        setattr(s, k, v)
    audit(db, admin, "subject.update", "subject", s.id, body.model_dump(exclude_unset=True), request)
    db.commit()
    return _subject_out(db, s)


@router.put("/grades/{grade_id}/subjects/{subject_id}")
def assign_subject(grade_id: int, subject_id: int, body: AssignIn, request: Request, db: Session = Depends(get_db), admin: User = Depends(_me)):
    g = db.get(Grade, grade_id) or _nf("Grade")
    s = db.get(Subject, subject_id) or _nf("Subject")
    link = db.get(GradeSubject, (g.id, s.id))
    if link is None:
        db.add(GradeSubject(grade_id=g.id, subject_id=s.id, published=body.published))
    else:
        link.published = body.published
    audit(db, admin, "subject.assign", "grade_subject", f"{g.id}:{s.id}", {"grade": g.number, "subject": s.key, "published": body.published}, request)
    db.commit()