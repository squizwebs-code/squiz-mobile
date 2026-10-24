from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session, selectinload

from ..db import get_db
from ..deps import current_user, err
from ..models import AppSetting, Grade, GradeSubject, Question, Subject, Unit, User
from ..schemas import GradeOut, OptionOut, Page, QuestionOut, SubjectOut, UnitOut
from ..visibility import question_counts_by_unit, visible_questions, visible_units

router = APIRouter(tags=["content"])


def question_out(q: Question) -> QuestionOut:
    return QuestionOut(id=q.id, unit_id=q.unit_id, text=q.text, image_url=q.image_url, difficulty=q.difficulty.value if q.difficulty else None,
                       options=[OptionOut(id=o.id, text=o.text) for o in q.options])


def _grade_or_404(db: Session, number: int) -> Grade:
    g = db.scalar(select(Grade).where(Grade.number == number, Grade.published.is_(True)))
    if not g:
        raise err(404, "grade_not_found", "That grade is not available.")
    return g


@router.get("/config")
def public_config(db: Session = Depends(get_db)):
    """Public: branding and default grade, used by the splash/onboarding screens."""
    row = db.get(AppSetting, "app")
    v = row.value if row else {}
    return {"app_name": v.get("app_name", "SQUIZ"), "tagline": v.get("tagline", "Smart Quiz and Learning"), "default_grade": v.get("default_grade"),
            "exam_name": v.get("exam_name"), "exam_date": v.get("exam_date")}


@router.get("/grades", response_model=list[GradeOut])
def list_grades(db: Session = Depends(get_db)):
    return db.scalars(select(Grade).where(Grade.published.is_(True)).order_by(Grade.number)).all()


@router.get("/grades/{number}/subjects", response_model=list[SubjectOut])
def list_subjects(number: int, db: Session = Depends(get_db), _: User = Depends(current_user)):
    _grade_or_404(db, number)
    units = db.scalars(visible_units(number)).all()
    counts = question_counts_by_unit(db, number)
    by_subject: dict[int, list[Unit]] = {}
    for u in units:
        by_subject.setdefault(u.subject_id, []).append(u)
    subjects = db.scalars(select(Subject).where(Subject.id.in_(by_subject.keys() or [0])).order_by(Subject.name)).all() if by_subject else []
    out = []
    for s in subjects:
        us = by_subject[s.id]
        qn = sum(counts.get(u.id, 0) for u in us)
        if qn:
            out.append(SubjectOut(id=s.id, key=s.key, name=s.name, icon=s.icon, unit_count=len([u for u in us if counts.get(u.id)]), question_count=qn))
    return out


@router.get("/grades/{number}/subjects/{subject_id}/units", response_model=list[UnitOut])
def list_units(number: int, subject_id: int, db: Session = Depends(get_db), _: User = Depends(current_user)):
    _grade_or_404(db, number)
    counts = question_counts_by_unit(db, number, subject_id)
    return [UnitOut(id=u.id, title=u.title, kind=u.kind, position=u.position, subject_id=u.subject_id, grade_number=number, question_count=counts[u.id])
            for u in db.scalars(visible_units(number, subject_id)).all() if counts.get(u.id)]


@router.get("/questions", response_model=Page[QuestionOut])
def list_questions(unit_id: int | None = None, subject_id: int | None = None, grade: int | None = None,
                   page: int = Query(1, ge=1), size: int = Query(20, ge=1, le=100),
                   db: Session = Depends(get_db), _: User = Depends(current_user)):
    base = visible_questions(grade, subject_id, unit_id)
    total = db.scalar(select(func.count()).select_from(base.subquery()))
    rows = db.scalars(base.options(selectinload(Question.options)).order_by(Question.unit_id, Question.id).offset((page - 1) * size).limit(size)).all()
    return Page(items=[question_out(q) for q in rows], total=total, page=page, size=size)


@router.get("/search")
def search(q: str = Query(min_length=2, max_length=80), grade: int | None = None, db: Session = Depends(get_db), _: User = Depends(current_user)):
    like = f"%{q.strip().replace('%', '').replace('_', '')}%"
    units = [u for u in db.scalars(visible_units(grade).where(or_(Unit.title.ilike(like), Subject.name.ilike(like))).limit(20)).all()]
    qs = db.scalars(visible_questions(grade).where(Question.text.ilike(like)).options(selectinload(Question.options)).order_by(Question.id).limit(30)).all()
    subs = {s.id: s for s in db.scalars(select(Subject).where(Subject.id.in_([u.subject_id for u in units] or [0])))}
    return {"units": [{"id": u.id, "title": u.title, "subject": subs[u.subject_id].name, "subject_id": u.subject_id, "grade_id": u.grade_id} for u in units],
            "questions": [question_out(x) for x in qs]}


@router.get("/content/offline-pack")
def offline_pack(grade: int, db: Session = Depends(get_db), _: User = Depends(current_user)):
    """Everything needed for offline PRACTICE for one grade, including answers.

    Exams are always graded by the server from a server-held snapshot, so this pack cannot be used to
    change exam results; it does let a student look up answers, which is acceptable for practice content.
    """
    _grade_or_404(db, grade)
    units = db.scalars(visible_units(grade)).all()
    subs = {s.id: s for s in db.scalars(select(Subject))}
    rows = db.scalars(visible_questions(grade).options(selectinload(Question.options)).order_by(Question.unit_id, Question.id)).all()
    by_unit: dict[int, list] = {}
    for q in rows:
        by_unit.setdefault(q.unit_id, []).append({
            "id": q.id, "text": q.text, "explanation": q.explanation, "image_url": q.image_url, "version": q.version,
            "options": [{"id": o.id, "text": o.text, "is_correct": o.is_correct} for o in q.options]})
    from datetime import datetime, timezone
    return {"grade": grade, "generated_at": datetime.now(timezone.utc).isoformat(),
            "units": [{"id": u.id, "title": u.title, "kind": u.kind, "position": u.position, "subject_id": u.subject_id, "subject": subs[u.subject_id].name,
                       "questions": by_unit[u.id]} for u in units if u.id in by_unit]}
