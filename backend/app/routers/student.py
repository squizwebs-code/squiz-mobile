from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, Query, Response
from pydantic import BaseModel
from sqlalchemy import and_, func, select
from sqlalchemy.orm import Session, selectinload

from ..config import get_settings
from ..db import get_db
from ..deps import current_user, err, student_user
from ..models import (AppSetting, Bookmark, Grade, Question, QuizAttempt, QuizSession, SessionMode, SessionQuestion, SessionStatus,
                      StudentProgress, Subject, Unit, User, utcnow)
from ..schemas import DeleteAccountIn, Page, ProfileUpdate, UserOut
from ..phone import name_key
from ..security import verify_password
from ..visibility import visible_questions

router = APIRouter(tags=["student"])


# ---------------- profile ----------------
@router.get("/me", response_model=UserOut)
def me(user: User = Depends(current_user)):
    return user


@router.patch("/me", response_model=UserOut)
def update_me(body: ProfileUpdate, db: Session = Depends(get_db), user: User = Depends(current_user)):
    if body.full_name is not None and " ".join(body.full_name.split()) != user.full_name:
        row = db.get(AppSetting, "app")
        if row and row.value.get("allow_name_change") is False:
            raise err(403, "name_change_disabled", "Changing your name is not allowed. Please contact an administrator.")
        user.full_name = " ".join(body.full_name.split())
        user.name_key = name_key(user.full_name)
    if body.selected_grade is not None:
        if not db.scalar(select(Grade.id).where(Grade.number == body.selected_grade, Grade.published.is_(True))):
            raise err(404, "grade_not_found", "That grade is not available.")
        user.selected_grade = body.selected_grade
    if body.selected_track is not None:
        user.selected_track = None if body.selected_track == "all" else body.selected_track
    if body.username is not None and body.username != user.username:
        if db.scalar(select(User.id).where(User.username == body.username, User.id != user.id)):
            raise err(409, "username_taken", "That username is already taken.")
        user.username = body.username
    db.commit()
    return user


@router.delete("/me", status_code=204)
def delete_account(body: DeleteAccountIn, db: Session = Depends(get_db), user: User = Depends(student_user)):
    """Safe deletion: requires the current password. All of the student's data is removed (cascade)."""
    if not verify_password(body.password, user.password_hash):
        raise err(400, "wrong_password", "Your password is incorrect.")
    db.delete(user)
    db.commit()
    return Response(status_code=204)


# ---------------- review lists ----------------
class ReviewOption(BaseModel):
    id: int
    text: str
    is_correct: bool


class ReviewQuestion(BaseModel):
    id: int
    text: str
    unit_id: int
    unit_title: str
    subject: str
    explanation: str | None
    image_url: str | None
    options: list[ReviewOption]
    bookmarked: bool = False
    flagged: bool = False


def _review_items(db: Session, user: User, ids: list[int]) -> list[ReviewQuestion]:
    if not ids:
        return []
    rows = db.scalars(visible_questions().where(Question.id.in_(ids)).options(selectinload(Question.options), selectinload(Question.unit))).all()
    by_id = {q.id: q for q in rows}
    subs = {s.id: s.name for s in db.scalars(select(Subject))}
    bms = set(db.scalars(select(Bookmark.question_id).where(Bookmark.user_id == user.id, Bookmark.question_id.in_(ids))))
    fl = set(db.scalars(select(StudentProgress.question_id).where(StudentProgress.user_id == user.id, StudentProgress.flagged.is_(True), StudentProgress.question_id.in_(ids))))
    out = []
    for i in ids:                       # keep the requested order
        q = by_id.get(i)
        if q:
            out.append(ReviewQuestion(id=q.id, text=q.text, unit_id=q.unit_id, unit_title=q.unit.title, subject=subs.get(q.unit.subject_id, ""),
                                      explanation=q.explanation, image_url=q.image_url, bookmarked=q.id in bms, flagged=q.id in fl,
                                      options=[ReviewOption(id=o.id, text=o.text, is_correct=o.is_correct) for o in q.options]))
    return out


def _paged_ids(db, stmt, page, size):
    total = db.scalar(select(func.count()).select_from(stmt.subquery()))
    ids = list(db.scalars(stmt.offset((page - 1) * size).limit(size)))
    return total, ids


@router.get("/bookmarks", response_model=Page[ReviewQuestion])
def list_bookmarks(page: int = Query(1, ge=1), size: int = Query(20, ge=1, le=100), db: Session = Depends(get_db), user: User = Depends(student_user)):
    stmt = (select(Bookmark.question_id).join(Question, Question.id == Bookmark.question_id)
            .where(Bookmark.user_id == user.id, Question.deleted_at.is_(None)).order_by(Bookmark.created_at.desc()))
    total, ids = _paged_ids(db, stmt, page, size)
    return Page(items=_review_items(db, user, ids), total=total, page=page, size=size)


@router.put("/bookmarks/{question_id}", status_code=204)
def add_bookmark(question_id: int, db: Session = Depends(get_db), user: User = Depends(student_user)):
    if not db.scalar(visible_questions().where(Question.id == question_id).with_only_columns(Question.id)):
        raise err(404, "question_not_found", "Question not found.")
    if db.get(Bookmark, (user.id, question_id)) is None:
        db.add(Bookmark(user_id=user.id, question_id=question_id))
        db.commit()
    return Response(status_code=204)


@router.delete("/bookmarks/{question_id}", status_code=204)
def remove_bookmark(question_id: int, db: Session = Depends(get_db), user: User = Depends(student_user)):
    b = db.get(Bookmark, (user.id, question_id))
    if b:
        db.delete(b)
        db.commit()
    return Response(status_code=204)


@router.get("/flags", response_model=Page[ReviewQuestion])
def list_flags(page: int = Query(1, ge=1), size: int = Query(20, ge=1, le=100), db: Session = Depends(get_db), user: User = Depends(student_user)):
    stmt = select(StudentProgress.question_id).where(StudentProgress.user_id == user.id, StudentProgress.flagged.is_(True)).order_by(StudentProgress.question_id)
    total, ids = _paged_ids(db, stmt, page, size)
    return Page(items=_review_items(db, user, ids), total=total, page=page, size=size)


def _set_flag(db: Session, user: User, question_id: int, value: bool):
    if not db.scalar(visible_questions().where(Question.id == question_id).with_only_columns(Question.id)):
        raise err(404, "question_not_found", "Question not found.")
    p = db.get(StudentProgress, (user.id, question_id))
    if p is None:
        p = StudentProgress(user_id=user.id, question_id=question_id, attempts=0, correct_count=0)
        db.add(p)
    p.flagged = value
    db.commit()
    return Response(status_code=204)


@router.put("/flags/{question_id}", status_code=204)
def add_flag(question_id: int, db: Session = Depends(get_db), user: User = Depends(student_user)):
    return _set_flag(db, user, question_id, True)


@router.delete("/flags/{question_id}", status_code=204)
def remove_flag(question_id: int, db: Session = Depends(get_db), user: User = Depends(student_user)):
    return _set_flag(db, user, question_id, False)


@router.get("/me/incorrect", response_model=Page[ReviewQuestion])
def incorrect(page: int = Query(1, ge=1), size: int = Query(20, ge=1, le=100), db: Session = Depends(get_db), user: User = Depends(student_user)):
    """Questions whose most recent answer was wrong (cleared once answered correctly)."""
    stmt = (select(StudentProgress.question_id).where(StudentProgress.user_id == user.id, StudentProgress.last_correct.is_(False))
            .order_by(StudentProgress.last_at.desc()))
    total, ids = _paged_ids(db, stmt, page, size)
    return Page(items=_review_items(db, user, ids), total=total, page=page, size=size)


# ---------------- statistics ----------------
def compute_stats(db: Session, user_id: int) -> dict:
    tz = ZoneInfo(get_settings().app_timezone)
    a, c, distinct = db.execute(select(func.coalesce(func.sum(StudentProgress.attempts), 0), func.coalesce(func.sum(StudentProgress.correct_count), 0),
                                       func.count()).where(StudentProgress.user_id == user_id, StudentProgress.attempts > 0)).one()
    completed = db.scalar(select(func.count()).select_from(QuizAttempt).where(QuizAttempt.user_id == user_id))
    day = func.date(func.timezone(get_settings().app_timezone, SessionQuestion.answered_at))
    rows = db.execute(select(day, func.count()).join(QuizSession, QuizSession.id == SessionQuestion.session_id)
                      .where(QuizSession.user_id == user_id, SessionQuestion.answered_at.is_not(None),
                             SessionQuestion.answered_at >= utcnow() - timedelta(days=400)).group_by(day)).all()
    per_day: dict[date, int] = {d: n for d, n in rows}
    today = datetime.now(tz).date()
    d = today if per_day.get(today) else today - timedelta(days=1)
    streak = 0
    while per_day.get(d):
        streak += 1
        d -= timedelta(days=1)
    last7 = [{"date": (today - timedelta(days=i)).isoformat(), "answered": per_day.get(today - timedelta(days=i), 0)} for i in range(6, -1, -1)]
    subj = db.execute(select(Subject.id, Subject.name, func.sum(StudentProgress.attempts), func.sum(StudentProgress.correct_count), func.count())
                      .join(Question, Question.id == StudentProgress.question_id).join(Unit, Unit.id == Question.unit_id)
                      .join(Subject, Subject.id == Unit.subject_id)
                      .where(StudentProgress.user_id == user_id, StudentProgress.attempts > 0).group_by(Subject.id, Subject.name).order_by(Subject.name)).all()
    return {"questions_answered": int(a), "correct_answers": int(c), "accuracy": round(c * 100 / a) if a else None,
            "distinct_questions": distinct, "completed_quizzes": completed, "streak_days": streak, "last_7_days": last7,
            "by_subject": [{"subject_id": i, "subject": n, "answered": int(x), "correct": int(y), "accuracy": round(y * 100 / x) if x else None,
                            "distinct_questions": z} for i, n, x, y, z in subj]}


@router.get("/me/stats")
def stats(db: Session = Depends(get_db), user: User = Depends(student_user)):
    return compute_stats(db, user.id)


@router.get("/me/dashboard")
def dashboard(db: Session = Depends(get_db), user: User = Depends(student_user)):
    st = compute_stats(db, user.id)
    cont = db.scalar(select(QuizSession).where(QuizSession.user_id == user.id, QuizSession.status == SessionStatus.in_progress,
                                               QuizSession.mode == SessionMode.practice).order_by(QuizSession.id.desc()).limit(1))
    answered = None
    if cont:
        answered = db.scalar(select(func.count()).select_from(SessionQuestion).where(SessionQuestion.session_id == cont.id, SessionQuestion.selected_option_id.is_not(None)))
        total = db.scalar(select(func.count()).select_from(SessionQuestion).where(SessionQuestion.session_id == cont.id))
    recent_rows = db.execute(select(QuizSession.unit_id, func.max(QuizSession.id)).where(QuizSession.user_id == user.id, QuizSession.unit_id.is_not(None))
                             .group_by(QuizSession.unit_id).order_by(func.max(QuizSession.id).desc()).limit(5)).all()
    recents = []
    for uid, _ in recent_rows:
        u = db.get(Unit, uid)
        if u and u.published:
            recents.append({"unit_id": u.id, "title": u.title, "subject_id": u.subject_id, "subject": db.get(Subject, u.subject_id).name})
    return {"user": UserOut.model_validate(user).model_dump(mode="json"), "stats": st,
            "continue_session": {"id": cont.id, "title": cont.title, "answered": answered, "total": total} if cont else None,
            "recent_units": recents,
            "bookmark_count": db.scalar(select(func.count()).select_from(Bookmark).where(Bookmark.user_id == user.id)),
            "incorrect_count": db.scalar(select(func.count()).select_from(StudentProgress).where(StudentProgress.user_id == user.id, StudentProgress.last_correct.is_(False)))}
