"""Administrator API. Every route depends on `admin_user`, which re-checks the role in the database on each request."""
import os
import secrets
from datetime import timedelta

from fastapi import APIRouter, Depends, File, Query, Request, Response, UploadFile
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from ..config import get_settings
from ..db import get_db
from ..deps import admin_user, audit, err
from ..models import (AccountStatus, AppSetting, AuditLog, Grade, GradeSubject, PublishStatus, Question, QuizAttempt, RefreshToken, Role,
                      SessionQuestion, StudentProgress, Subject, Unit, User, utcnow)
from ..routers.student import compute_stats
from ..schemas import (AssignIn, GradeIn, GradePatch, Page, ReorderIn, SettingsIn, StudentStatusIn, SubjectIn, SubjectPatch, UnitIn,
                       UnitPatch)
from ..security import generate_temp_password, hash_password

router = APIRouter(prefix="/admin", tags=["admin"], dependencies=[Depends(admin_user)])


def _me(admin: User = Depends(admin_user)) -> User:   # cached per request by FastAPI
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
    return _subject_out(db, s)


@router.delete("/grades/{grade_id}/subjects/{subject_id}", status_code=204)
def unassign_subject(grade_id: int, subject_id: int, request: Request, db: Session = Depends(get_db), admin: User = Depends(_me)):
    if db.scalar(select(func.count()).select_from(Unit).where(Unit.grade_id == grade_id, Unit.subject_id == subject_id)):
        raise err(409, "has_units", "This subject still has units in this grade. Unpublish it instead, or remove the units first.")
    link = db.get(GradeSubject, (grade_id, subject_id))
    if link:
        db.delete(link)
        audit(db, admin, "subject.unassign", "grade_subject", f"{grade_id}:{subject_id}", None, request)
        db.commit()
    return Response(status_code=204)


@router.delete("/subjects/{subject_id}", status_code=204)
def delete_subject(subject_id: int, request: Request, confirm: bool = Query(False), db: Session = Depends(get_db), admin: User = Depends(_me)):
    s = db.get(Subject, subject_id) or _nf("Subject")
    if not confirm:
        raise err(400, "confirmation_required", "Add confirm=true to delete.")
    if db.scalar(select(func.count()).select_from(Unit).where(Unit.subject_id == s.id)):
        raise err(409, "has_units", "This subject has units. Unpublish it instead of deleting.")
    audit(db, admin, "subject.delete", "subject", s.id, {"key": s.key}, request)
    db.delete(s)
    db.commit()
    return Response(status_code=204)


# ---------------- units ----------------
def _unit_out(db: Session, u: Unit) -> dict:
    counts = dict(db.execute(select(Question.status, func.count()).where(Question.unit_id == u.id, Question.deleted_at.is_(None)).group_by(Question.status)).all())
    return {"id": u.id, "grade_id": u.grade_id, "subject_id": u.subject_id, "title": u.title, "kind": u.kind, "position": u.position, "published": u.published,
            "questions": {k.value: counts.get(k, 0) for k in PublishStatus}}


@router.get("/units")
def list_units(grade_id: int | None = None, subject_id: int | None = None, db: Session = Depends(get_db)):
    q = select(Unit).order_by(Unit.grade_id, Unit.subject_id, Unit.position, Unit.id)
    if grade_id:
        q = q.where(Unit.grade_id == grade_id)
    if subject_id:
        q = q.where(Unit.subject_id == subject_id)
    return [_unit_out(db, u) for u in db.scalars(q)]


@router.post("/units", status_code=201)
def create_unit(body: UnitIn, request: Request, db: Session = Depends(get_db), admin: User = Depends(_me)):
    g = db.get(Grade, body.grade_id) or _nf("Grade")
    s = db.get(Subject, body.subject_id) or _nf("Subject")
    if db.scalar(select(Unit.id).where(Unit.grade_id == g.id, Unit.subject_id == s.id, func.lower(Unit.title) == body.title.lower())):
        raise err(409, "unit_exists", "A unit with this title already exists for this grade and subject.")
    if db.get(GradeSubject, (g.id, s.id)) is None:
        db.add(GradeSubject(grade_id=g.id, subject_id=s.id, published=True))     # creating a unit implies the subject is taught in that grade
    pos = (db.scalar(select(func.max(Unit.position)).where(Unit.grade_id == g.id, Unit.subject_id == s.id)) or 0) + 1
    u = Unit(grade_id=g.id, subject_id=s.id, title=body.title, kind=body.kind, position=pos, published=body.published)
    db.add(u)
    db.flush()
    audit(db, admin, "unit.create", "unit", u.id, body.model_dump(), request)
    db.commit()
    return _unit_out(db, u)


@router.patch("/units/{unit_id}")
def update_unit(unit_id: int, body: UnitPatch, request: Request, db: Session = Depends(get_db), admin: User = Depends(_me)):
    u = db.get(Unit, unit_id) or _nf("Unit")
    data = body.model_dump(exclude_unset=True)
    if "title" in data and db.scalar(select(Unit.id).where(Unit.grade_id == u.grade_id, Unit.subject_id == u.subject_id, func.lower(Unit.title) == data["title"].lower(), Unit.id != u.id)):
        raise err(409, "unit_exists", "A unit with this title already exists for this grade and subject.")
    for k, v in data.items():
        setattr(u, k, v)
    audit(db, admin, "unit.update", "unit", u.id, data, request)
    db.commit()
    return _unit_out(db, u)


@router.post("/units/reorder")
def reorder_units(body: ReorderIn, request: Request, db: Session = Depends(get_db), admin: User = Depends(_me)):
    units = {u.id: u for u in db.scalars(select(Unit).where(Unit.grade_id == body.grade_id, Unit.subject_id == body.subject_id))}
    if set(body.unit_ids) != set(units) or len(body.unit_ids) != len(set(body.unit_ids)):
        raise err(422, "bad_order", "unit_ids must list every unit of this grade and subject exactly once.")
    for i, uid in enumerate(body.unit_ids, start=1):
        units[uid].position = i
    audit(db, admin, "unit.reorder", "unit", None, {"grade_id": body.grade_id, "subject_id": body.subject_id, "order": body.unit_ids}, request)
    db.commit()
    return [_unit_out(db, units[i]) for i in body.unit_ids]


@router.delete("/units/{unit_id}", status_code=204)
def delete_unit(unit_id: int, request: Request, confirm: bool = Query(False), db: Session = Depends(get_db), admin: User = Depends(_me)):
    u = db.get(Unit, unit_id) or _nf("Unit")
    if not confirm:
        raise err(400, "confirmation_required", "Add confirm=true to delete.")
    if db.scalar(select(func.count()).select_from(Question).where(Question.unit_id == u.id)):
        raise err(409, "has_questions", "This unit still has questions (including archived/deleted ones that keep student history). Unpublish it instead.")
    audit(db, admin, "unit.delete", "unit", u.id, {"title": u.title}, request)
    db.delete(u)
    db.commit()
    return Response(status_code=204)


# ---------------- students ----------------
def _student_out(u: User) -> dict:
    return {"id": u.id, "full_name": u.full_name, "phone": u.phone, "status": u.status.value, "selected_grade": u.selected_grade,
            "created_at": u.created_at, "last_active_at": u.last_active_at, "must_change_password": u.must_change_password}


@router.get("/students")
def list_students(q: str | None = None, status: str | None = None, page: int = Query(1, ge=1), size: int = Query(20, ge=1, le=100), db: Session = Depends(get_db)):
    st = select(User).where(User.role == Role.student)
    if q:
        like = f"%{q.strip().replace('%', '').replace('_', '')}%"
        st = st.where(or_(User.full_name.ilike(like), User.phone.like(like)))
    if status:
        st = st.where(User.status == AccountStatus(status))
    total = db.scalar(select(func.count()).select_from(st.subquery()))
    rows = db.scalars(st.order_by(User.created_at.desc(), User.id.desc()).offset((page - 1) * size).limit(size)).all()
    return Page(items=[_student_out(u) for u in rows], total=total, page=page, size=size)


def _student(db: Session, sid: int) -> User:
    u = db.get(User, sid)
    if not u or u.role != Role.student:
        _nf("Student")
    return u


@router.get("/students/{student_id}")
def student_detail(student_id: int, db: Session = Depends(get_db)):
    u = _student(db, student_id)
    attempts = db.scalars(select(QuizAttempt).where(QuizAttempt.user_id == u.id).order_by(QuizAttempt.submitted_at.desc()).limit(25)).all()
    return {**_student_out(u), "stats": compute_stats(db, u.id),
            "attempts": [{"id": a.id, "title": a.title, "mode": a.mode, "correct": a.correct, "total": a.total, "percentage": a.percentage, "submitted_at": a.submitted_at} for a in attempts]}


@router.patch("/students/{student_id}/status")
def set_student_status(student_id: int, body: StudentStatusIn, request: Request, db: Session = Depends(get_db), admin: User = Depends(_me)):
    u = _student(db, student_id)
    u.status = AccountStatus(body.status)
    if u.status == AccountStatus.inactive:          # deactivation signs the student out everywhere
        for t in db.scalars(select(RefreshToken).where(RefreshToken.user_id == u.id, RefreshToken.revoked_at.is_(None))):
            t.revoked_at = utcnow()
    audit(db, admin, "student.status", "user", u.id, {"status": body.status}, request)
    db.commit()
    return _student_out(u)


@router.post("/students/{student_id}/reset-password")
def reset_password(student_id: int, request: Request, db: Session = Depends(get_db), admin: User = Depends(_me)):
    """Generates a one-time temporary password (shown once, never stored in plaintext).
    The student is forced to choose a new password at next sign-in and all their sessions are revoked."""
    u = _student(db, student_id)
    temp = generate_temp_password()
    u.password_hash = hash_password(temp)
    u.must_change_password = True
    for t in db.scalars(select(RefreshToken).where(RefreshToken.user_id == u.id, RefreshToken.revoked_at.is_(None))):
        t.revoked_at = utcnow()
    audit(db, admin, "student.password_reset", "user", u.id, None, request)      # the password itself is never logged
    db.commit()
    return {"temporary_password": temp, "note": "Give this to the student privately. It works once; they must set a new password when they sign in."}


# ---------------- activity & analytics ----------------
@router.get("/activity")
def activity(page: int = Query(1, ge=1), size: int = Query(20, ge=1, le=100), mode: str | None = None, db: Session = Depends(get_db)):
    q = select(QuizAttempt, User.full_name, User.phone).join(User, User.id == QuizAttempt.user_id)
    if mode:
        q = q.where(QuizAttempt.mode == mode)
    total = db.scalar(select(func.count()).select_from(q.subquery()))
    rows = db.execute(q.order_by(QuizAttempt.submitted_at.desc()).offset((page - 1) * size).limit(size)).all()
    return Page(items=[{"id": a.id, "student": n, "phone": p, "title": a.title, "mode": a.mode, "correct": a.correct, "total": a.total,
                        "percentage": a.percentage, "timed_out": a.timed_out, "submitted_at": a.submitted_at} for a, n, p in rows], total=total, page=page, size=size)


@router.get("/analytics")
def analytics(db: Session = Depends(get_db)):
    by_subject = db.execute(select(Subject.name, func.count(QuizAttempt.id), func.avg(QuizAttempt.percentage)).join(Subject, Subject.id == QuizAttempt.subject_id)
                            .group_by(Subject.name).order_by(Subject.name)).all()
    tz = get_settings().app_timezone
    day = func.date(func.timezone(tz, QuizAttempt.submitted_at))
    per_day = db.execute(select(day, func.count()).where(QuizAttempt.submitted_at >= utcnow() - timedelta(days=30)).group_by(day).order_by(day)).all()
    modes = dict(db.execute(select(QuizAttempt.mode, func.count()).group_by(QuizAttempt.mode)).all())
    return {"by_subject": [{"subject": n, "attempts": c, "average_percentage": round(float(a), 1)} for n, c, a in by_subject],
            "attempts_per_day_30d": [{"date": d.isoformat(), "attempts": c} for d, c in per_day], "attempts_by_mode": modes}


@router.get("/questions-analytics")
def question_analytics(min_answers: int = Query(10, ge=1), limit: int = Query(25, ge=1, le=100), db: Session = Depends(get_db)):
    """Usage per question, plus questions answered correctly unusually rarely (possible wrong answer key or unclear wording)."""
    answers = func.count(SessionQuestion.id)
    correct = func.sum(func.cast(SessionQuestion.is_correct, Integer_()))
    rows = db.execute(select(SessionQuestion.question_id, answers, correct).where(SessionQuestion.selected_option_id.is_not(None), SessionQuestion.question_id.is_not(None))
                      .group_by(SessionQuestion.question_id).having(answers >= min_answers)).all()
    qs = {q.id: q for q in db.scalars(select(Question).where(Question.id.in_([r[0] for r in rows] or [0])))}
    items = [{"question_id": qid, "text": qs[qid].text, "status": qs[qid].status.value, "answers": n, "correct_rate": round((c or 0) * 100 / n)}
             for qid, n, c in rows if qid in qs]
    usage = sorted(items, key=lambda x: -x["answers"])[:limit]
    suspect = sorted([i for i in items if i["correct_rate"] < 25], key=lambda x: x["correct_rate"])[:limit]
    return {"min_answers": min_answers, "most_used": usage, "may_need_correction": suspect}


def Integer_():
    from sqlalchemy import Integer
    return Integer


# ---------------- audit log, settings, uploads ----------------
def _audit_out(a: AuditLog) -> dict:
    return {"id": a.id, "admin": a.admin_name, "action": a.action, "entity": a.entity, "entity_id": a.entity_id, "details": a.details, "ip": a.ip, "at": a.created_at}


@router.get("/audit")
def audit_log(action: str | None = None, page: int = Query(1, ge=1), size: int = Query(30, ge=1, le=100), db: Session = Depends(get_db)):
    q = select(AuditLog)
    if action:
        q = q.where(AuditLog.action.like(f"{action}%"))
    total = db.scalar(select(func.count()).select_from(q.subquery()))
    rows = db.scalars(q.order_by(AuditLog.id.desc()).offset((page - 1) * size).limit(size)).all()
    return Page(items=[_audit_out(a) for a in rows], total=total, page=page, size=size)


def _settings(db: Session) -> dict:
    row = db.get(AppSetting, "app")
    base = {"app_name": "SQUIZ", "tagline": "Smart Quiz and Learning", "default_grade": None, "allow_name_change": True}
    return {**base, **(row.value if row else {})}


@router.get("/settings")
def get_settings_(db: Session = Depends(get_db)):
    return _settings(db)


@router.put("/settings")
def put_settings(body: SettingsIn, request: Request, db: Session = Depends(get_db), admin: User = Depends(_me)):
    data = body.model_dump(exclude_unset=True)
    if data.get("default_grade") and not db.scalar(select(Grade.id).where(Grade.number == data["default_grade"])):
        raise err(422, "unknown_grade", "That grade does not exist.")
    new = {**_settings(db), **data}
    row = db.get(AppSetting, "app")
    if row is None:
        db.add(AppSetting(key="app", value=new))
    else:
        row.value = new
    audit(db, admin, "settings.update", "settings", "app", data, request)
    db.commit()
    return new


_MAGIC = {b"\x89PNG\r\n\x1a\n": ("png", "image/png"), b"\xff\xd8\xff": ("jpg", "image/jpeg"), b"RIFF": ("webp", "image/webp")}


@router.post("/uploads", status_code=201)
async def upload_image(request: Request, file: UploadFile = File(...), db: Session = Depends(get_db), admin: User = Depends(_me)):
    cfg = get_settings()
    data = await file.read(cfg.max_upload_mb * 1024 * 1024 + 1)
    if len(data) > cfg.max_upload_mb * 1024 * 1024:
        raise err(413, "file_too_large", f"Images must be at most {cfg.max_upload_mb} MB.")
    ext = next((e for magic, (e, _) in _MAGIC.items() if data.startswith(magic) and (magic != b"RIFF" or data[8:12] == b"WEBP")), None)
    if ext is None:
        raise err(415, "unsupported_image", "Only PNG, JPEG or WebP images are allowed.")
    os.makedirs(cfg.upload_dir, exist_ok=True)
    name = f"{secrets.token_hex(12)}.{ext}"          # server-chosen name: the client filename is never used
    with open(os.path.join(cfg.upload_dir, name), "wb") as f:
        f.write(data)
    audit(db, admin, "upload.image", "file", name, {"bytes": len(data)}, request)
    db.commit()
    return {"url": f"/media/{name}"}
