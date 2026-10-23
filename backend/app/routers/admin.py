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


def _audit_out(a: AuditLog) -> dict:
    return {"id": a.id, "admin": a.admin_name, "action": a.action, "entity": a.entity, "entity_id": a.entity_id, "details": a.details, "ip": a.ip, "at": a.created_at}


def _nf(what: str):
    raise err(404, "not_found", f"{what} not found.")


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
        db.add(GradeSubject(grade_id=g.id, subject_id=s.id, published=True))    # creating a unit implies the subject is taught in that grade
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


# ---------------- students & suspensions ----------------
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
    u.token_version += 1
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
    u.token_version += 1
    for t in db.scalars(select(RefreshToken).where(RefreshToken.user_id == u.id, RefreshToken.revoked_at.is_(None))):
        t.revoked_at = utcnow()
    audit(db, admin, "student.password_reset", "user", u.id, None, request)      # the password itself is never logged
    db.commit()
    return {"temporary_password": temp, "note": "Give this to the student privately. It works once; they must set a new password when they sign in."}


# ---------------- excel import & export ----------------
@router.post("/import/preview")
async def preview_excel_import(file: UploadFile = File(...), db: Session = Depends(get_db)):
    content = await file.read()
    try:
        df = pd.read_excel(io.BytesIO(content))
    except Exception as e:
        raise err(400, "invalid_excel", f"Could not parse Excel file: {str(e)}")

    required_cols = {"grade", "subject", "unit", "question", "option_a", "option_b", "option_c", "option_d", "correct_answer"}
    missing = required_cols - set(df.columns)
    if missing:
        raise err(422, "missing_columns", f"Excel file is missing required columns: {list(missing)}")

    rows_preview = []
    errors = []
    duplicates = []

    for idx, row in df.iterrows():
        r_num = idx + 2  # Excel row numbering (1-based + header)
        text = str(row.get("question", "")).strip()
        correct = str(row.get("correct_answer", "")).strip().upper()

        row_errors = []
        if not text:
            row_errors.append("Question text is empty")
        if correct not in ["A", "B", "C", "D"]:
            row_errors.append(f"Invalid correct_answer '{correct}', must be A, B, C, or D")

        # Check duplicate by text hash
        text_key = hashlib.sha256(text.encode("utf-8")).hexdigest()
        existing_q = db.scalar(select(Question.id).where(Question.text_key == text_key, Question.deleted_at.is_(None)))
        is_dup = existing_q is not None

        if row_errors:
            errors.append({"row": r_num, "errors": row_errors})
        if is_dup:
            duplicates.append({"row": r_num, "question": text[:50]})

        rows_preview.append({
            "row": r_num,
            "grade": row.get("grade"),
            "subject": row.get("subject"),
            "unit": row.get("unit"),
            "question": text,
            "correct_answer": correct,
            "is_duplicate": is_dup,
            "errors": row_errors
        })

    return {
        "file_name": file.filename,
        "total_rows": len(df),
        "error_count": len(errors),
        "duplicate_count": len(duplicates),
        "errors": errors,
        "duplicates": duplicates,
        "preview": rows_preview[:50]  # first 50 rows preview
    }


@router.post("/import/commit", status_code=201)
async def commit_excel_import(
    file: UploadFile = File(...),
    duplicate_strategy: str = Query("skip", regex="^(skip|update|add)$"),
    request: Request = Depends(Request),
    db: Session = Depends(get_db),
    admin: User = Depends(_me)
):
    content = await file.read()
    try:
        df = pd.read_excel(io.BytesIO(content))
    except Exception as e:
        raise err(400, "invalid_excel", f"Could not parse Excel file: {str(e)}")

    batch = ImportBatch(file_name=file.filename, admin_id=admin.id, total_rows=len(df), status="draft")
    db.add(batch)
    db.flush()

    imported_count = 0
    for _, row in df.iterrows():
        text = str(row.get("question", "")).strip()
        if not text:
            continue
        correct = str(row.get("correct_answer", "")).strip().upper()
        if correct not in ["A", "B", "C", "D"]:
            continue

        grade_num = int(row.get("grade", 9))
        subject_key = str(row.get("subject", "math")).strip().lower()
        unit_title = str(row.get("unit", "Unit 1")).strip()

        # Find or create Grade, Subject, Unit
        grade = db.scalar(select(Grade).where(Grade.number == grade_num))
        if not grade:
            grade = Grade(number=grade_num, name=f"Grade {grade_num}")
            db.add(grade)
            db.flush()

        subject = db.scalar(select(Subject).where(Subject.key == subject_key))
        if not subject:
            subject = Subject(key=subject_key, name=subject_key.capitalize())
            db.add(subject)
            db.flush()

        # Ensure grade_subject link
        if not db.get(GradeSubject, (grade.id, subject.id)):
            db.add(GradeSubject(grade_id=grade.id, subject_id=subject.id, published=True))

        unit = db.scalar(select(Unit).where(Unit.grade_id == grade.id, Unit.subject_id == subject.id, func.lower(Unit.title) == unit_title.lower()))
        if not unit:
            unit = Unit(grade_id=grade.id, subject_id=subject.id, title=unit_title, published=False)
            db.add(unit)
            db.flush()

        text_key = hashlib.sha256(text.encode("utf-8")).hexdigest()
        existing = db.scalar(select(Question).where(Question.text_key == text_key, Question.deleted_at.is_(None)))

        if existing:
            if duplicate_strategy == "skip":
                continue
            elif duplicate_strategy == "update":
                existing.text = text
                existing.explanation = str(row.get("explanation", "")) or None
                imported_count += 1
                continue

        q = Question(
            unit_id=unit.id,
            text=text,
            text_key=text_key,
            explanation=str(row.get("explanation", "")) or None,
            status=PublishStatus.draft  # imported as drafts for safety
        )
        db.add(q)
        db.flush()

        # Add options
        for opt_label, pos in [("A", 1), ("B", 2), ("C", 3), ("D", 4)]:
            opt_text = str(row.get(f"option_{opt_label.lower()}", "")).strip()
            db.add(AnswerOption(
                question_id=q.id,
                text=opt_text,
                is_correct=(opt_label == correct),
                position=pos
            ))
        imported_count += 1

    batch.imported_rows = imported_count
    batch.status = "committed"
    audit(db, admin, "import.excel", "import_batch", batch.id, {"file_name": file.filename, "imported": imported_count}, request)
    db.commit()
    return {"batch_id": batch.id, "file_name": batch.file_name, "imported_rows": imported_count, "status": "committed"}


@router.post("/import/{batch_id}/undo", status_code=204)
def undo_import_batch(batch_id: int, request: Request, db: Session = Depends(get_db), admin: User = Depends(_me)):
    batch = db.get(ImportBatch, batch_id) or _nf("Import batch")
    if batch.status != "committed":
        raise err(400, "invalid_batch_status", "Batch is not in committed status or already rolled back.")
    
    batch.status = "rolled_back"
    audit(db, admin, "import.undo", "import_batch", batch.id, {"file_name": batch.file_name}, request)
    db.commit()
    return Response(status_code=204)


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