import random
from datetime import timedelta

from fastapi import APIRouter, Depends, Query, Response
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from .. import grading
from ..config import get_settings
from ..db import get_db
from ..deps import err, student_user
from ..models import (Grade, Question, QuizAttempt, QuizSession, SessionMode, SessionQuestion, SessionStatus, StudentProgress, Subject,
                      Unit, User, utcnow)
from ..schemas import (AnswerIn, AnswerOut, AttemptOut, OptionOut, Page, ResultOut, SessionOut, SessionQuestionOut, StartSessionIn,
                       SubmitIn, SyncPracticeIn)
from ..visibility import visible_questions, visible_units

router = APIRouter(tags=["quiz"])


# ---------- helpers ----------
def record_progress(db: Session, user_id: int, question_id: int | None, correct: bool, when=None) -> None:
    if question_id is None:
        return
    when = when or utcnow()
    p = db.get(StudentProgress, (user_id, question_id))
    if p is None:
        if db.get(Question, question_id) is None:
            return
        p = StudentProgress(user_id=user_id, question_id=question_id, attempts=0, correct_count=0)
        db.add(p)
    p.attempts = (p.attempts or 0) + 1
    p.correct_count = (p.correct_count or 0) + (1 if correct else 0)
    if p.last_at is None or when >= p.last_at:          # last write wins by timestamp (offline sync can arrive late)
        p.last_correct, p.last_at = correct, when


def _owned(db: Session, user: User, session_id: int) -> QuizSession:
    s = db.scalar(select(QuizSession).where(QuizSession.id == session_id, QuizSession.user_id == user.id).options(selectinload(QuizSession.questions)))
    if not s:
        raise err(404, "session_not_found", "Quiz session not found.")
    return s


def _question_out(sq: SessionQuestion, reveal: bool) -> SessionQuestionOut:
    snap = sq.snapshot
    by_id = {o["id"]: o for o in snap["options"]}
    show = reveal or False
    return SessionQuestionOut(position=sq.position, question_id=sq.question_id, text=snap["text"], image_url=snap.get("image_url"),
                              options=[OptionOut(id=i, text=by_id[i]["text"]) for i in sq.option_order if i in by_id],
                              selected_option_id=sq.selected_option_id,
                              is_correct=sq.is_correct if show else None,
                              correct_option_id=grading.correct_option_id(snap) if show else None,
                              explanation=snap.get("explanation") if show else None)


def build_session_out(s: QuizSession) -> SessionOut:
    submitted = s.status == SessionStatus.submitted
    qs = []
    for sq in s.questions:
        reveal = submitted or (s.mode == SessionMode.practice and sq.selected_option_id is not None)
        qs.append(_question_out(sq, reveal))
    return SessionOut(id=s.id, mode=s.mode.value, status=s.status.value, title=s.title, started_at=s.started_at, expires_at=s.expires_at,
                      limit_seconds=s.limit_seconds, server_time=utcnow(), answered=sum(1 for q in s.questions if q.selected_option_id is not None),
                      total=len(s.questions), questions=qs)


def _apply_answer(s: QuizSession, sq: SessionQuestion, option_id: int | None, when=None) -> None:
    if option_id is not None and not grading.valid_option(sq.snapshot, option_id):
        raise err(422, "invalid_option", "That answer option does not belong to this question.")
    sq.selected_option_id = option_id
    sq.is_correct = grading.is_correct(sq.snapshot, option_id)
    sq.answered_at = when or utcnow() if option_id is not None else None


def finalize(db: Session, s: QuizSession, timed_out: bool = False) -> QuizAttempt:
    """Server-side grading. Idempotent: returns the existing attempt if the session was already submitted."""
    existing = db.scalar(select(QuizAttempt).where(QuizAttempt.session_id == s.id))
    if existing:
        return existing
    now = utcnow()
    ended = min(now, s.expires_at) if timed_out and s.expires_at else now
    t = grading.tally([sq.is_correct for sq in s.questions])
    if s.mode == SessionMode.exam:
        for sq in s.questions:              # practice answers were recorded as they happened
            if sq.is_correct is not None:
                record_progress(db, s.user_id, sq.question_id, sq.is_correct, sq.answered_at)
    s.status, s.submitted_at = SessionStatus.submitted, ended
    a = QuizAttempt(session_id=s.id, user_id=s.user_id, mode=s.mode.value, title=s.title, subject_id=s.subject_id, unit_id=s.unit_id,
                    grade_number=s.grade_number, duration_seconds=max(0, int((ended - s.started_at).total_seconds())) if s.mode == SessionMode.exam else None,
                    timed_out=timed_out, submitted_at=ended, **t)
    db.add(a)
    db.commit()
    return a


def _expire_if_needed(db: Session, s: QuizSession) -> bool:
    if s.status == SessionStatus.in_progress and s.mode == SessionMode.exam and s.expires_at and utcnow() >= s.expires_at:
        finalize(db, s, timed_out=True)
        return True
    return False


# ---------- start / read ----------
@router.post("/sessions", response_model=SessionOut, status_code=201)
def start_session(body: StartSessionIn, db: Session = Depends(get_db), user: User = Depends(student_user)):
    if body.unit_id is not None:
        unit = db.scalar(visible_units().where(Unit.id == body.unit_id))
        if not unit:
            raise err(404, "unit_not_found", "That unit is not available.")
        pool_q = visible_questions(unit_id=unit.id)
        subject = db.get(Subject, unit.subject_id)
        grade = db.get(Grade, unit.grade_id)
        title, grade_number, subject_id, unit_id = f"{subject.name} · {unit.title}", grade.number, subject.id, unit.id
        default_shuffle, default_count = body.mode == "exam", None
    else:
        pool_q = visible_questions(body.grade_number, body.subject_id)
        subject = db.get(Subject, body.subject_id) if body.subject_id else None
        title = f"{subject.name} · Mixed" if subject else f"Mixed · Grade {body.grade_number}"
        grade_number, subject_id, unit_id = body.grade_number, body.subject_id, None
        default_shuffle, default_count = True, 20
    pool = db.scalars(pool_q.options(selectinload(Question.options)).order_by(Question.id)).all()
    if not pool:
        raise err(404, "no_questions", "There are no published questions for this selection yet.")
    shuffle = default_shuffle if body.shuffle is None else body.shuffle
    count = body.count or default_count or len(pool)
    chosen = random.sample(pool, min(count, len(pool))) if shuffle or count < len(pool) else list(pool)
    if not shuffle:
        chosen.sort(key=lambda q: q.id)
    now = utcnow()
    limit = body.limit_minutes * 60 if (body.mode == "exam" and body.limit_minutes) else None
    s = QuizSession(user_id=user.id, mode=SessionMode(body.mode), title=title, grade_number=grade_number, subject_id=subject_id, unit_id=unit_id,
                    limit_seconds=limit, started_at=now, expires_at=now + timedelta(seconds=limit) if limit else None)
    for i, q in enumerate(chosen):
        snap = grading.snapshot_question(q)
        s.questions.append(SessionQuestion(position=i, question_id=q.id, snapshot=snap, option_order=grading.option_order(snap, shuffle=True)))
    db.add(s)
    db.commit()
    return build_session_out(s)


@router.get("/sessions", response_model=list[SessionOut])
def list_sessions(status: str = "in_progress", db: Session = Depends(get_db), user: User = Depends(student_user)):
    rows = db.scalars(select(QuizSession).where(QuizSession.user_id == user.id, QuizSession.status == SessionStatus(status))
                      .options(selectinload(QuizSession.questions)).order_by(QuizSession.id.desc()).limit(10)).all()
    out = []
    for s in rows:
        if _expire_if_needed(db, s):
            continue
        out.append(build_session_out(s))
    return out


@router.get("/sessions/{session_id}", response_model=SessionOut)
def get_session(session_id: int, db: Session = Depends(get_db), user: User = Depends(student_user)):
    s = _owned(db, user, session_id)
    _expire_if_needed(db, s)
    db.refresh(s)
    return build_session_out(s)


# ---------- answering ----------
@router.put("/sessions/{session_id}/answers", response_model=AnswerOut)
def save_answer(session_id: int, body: AnswerIn, db: Session = Depends(get_db), user: User = Depends(student_user)):
    s = _owned(db, user, session_id)
    if _expire_if_needed(db, s):
        raise err(409, "exam_expired", "Time is up. Your exam has been submitted with the answers saved so far.")
    if s.status == SessionStatus.submitted:
        raise err(409, "session_submitted", "This quiz has already been submitted. Answers can no longer be changed.")
    sq = next((x for x in s.questions if x.question_id == body.question_id), None)
    if sq is None:
        raise err(404, "question_not_in_session", "That question is not part of this quiz.")
    snap = sq.snapshot
    if s.mode == SessionMode.practice:
        if body.selected_option_id is None:
            raise err(422, "answer_required", "Choose an answer.")
        if sq.selected_option_id is not None:
            if sq.selected_option_id != body.selected_option_id:
                raise err(409, "already_answered", "This question was already answered in practice mode.")
        else:
            _apply_answer(s, sq, body.selected_option_id)
            record_progress(db, user.id, sq.question_id, bool(sq.is_correct), sq.answered_at)
            db.commit()
        return AnswerOut(saved=True, is_correct=sq.is_correct, correct_option_id=grading.correct_option_id(snap), explanation=snap.get("explanation"))
    _apply_answer(s, sq, body.selected_option_id)       # exam: changeable until submit, never reveals anything
    db.commit()
    return AnswerOut(saved=True)


@router.post("/sessions/{session_id}/submit", response_model=ResultOut)
def submit(session_id: int, body: SubmitIn | None = None, db: Session = Depends(get_db), user: User = Depends(student_user)):
    s = _owned(db, user, session_id)
    if s.status == SessionStatus.submitted:
        return _result(db, s)
    cfg = get_settings()
    now = utcnow()
    late = bool(s.expires_at and now > s.expires_at + timedelta(seconds=cfg.exam_submit_grace_seconds))
    timed_out = bool(s.expires_at and now >= s.expires_at)
    if body and body.answers and not late:
        by_q = {x.question_id: x for x in s.questions}
        for a in body.answers:
            sq = by_q.get(a.question_id)
            if sq is None:
                raise err(404, "question_not_in_session", f"Question {a.question_id} is not part of this quiz.")
            if s.mode == SessionMode.practice and sq.selected_option_id is not None:
                continue
            _apply_answer(s, sq, a.selected_option_id)
            if s.mode == SessionMode.practice and a.selected_option_id is not None:
                record_progress(db, user.id, sq.question_id, bool(sq.is_correct), sq.answered_at)
    finalize(db, s, timed_out=timed_out)
    db.refresh(s)
    return _result(db, s)


def _result(db: Session, s: QuizSession) -> ResultOut:
    a = db.scalar(select(QuizAttempt).where(QuizAttempt.session_id == s.id))
    return ResultOut(attempt=AttemptOut.model_validate(a), questions=[_question_out(sq, True) for sq in s.questions])


@router.get("/sessions/{session_id}/result", response_model=ResultOut)
def result(session_id: int, db: Session = Depends(get_db), user: User = Depends(student_user)):
    s = _owned(db, user, session_id)
    _expire_if_needed(db, s)
    db.refresh(s)
    if s.status != SessionStatus.submitted:
        raise err(409, "not_submitted", "Results are available after you submit the quiz.")
    return _result(db, s)


@router.get("/attempts", response_model=Page[AttemptOut])
def history(page: int = Query(1, ge=1), size: int = Query(20, ge=1, le=100), mode: str | None = None,
            db: Session = Depends(get_db), user: User = Depends(student_user)):
    q = select(QuizAttempt).where(QuizAttempt.user_id == user.id)
    if mode:
        q = q.where(QuizAttempt.mode == mode)
    total = db.scalar(select(func.count()).select_from(q.subquery()))
    rows = db.scalars(q.order_by(QuizAttempt.submitted_at.desc(), QuizAttempt.id.desc()).offset((page - 1) * size).limit(size)).all()
    return Page(items=[AttemptOut.model_validate(r) for r in rows], total=total, page=page, size=size)


# ---------- offline practice sync ----------
@router.post("/sync/practice")
def sync_practice(body: SyncPracticeIn, response: Response, db: Session = Depends(get_db), user: User = Depends(student_user)):
    """Idempotent upload of a practice session completed offline (keyed by the device-generated client_id)."""
    existing = db.scalar(select(QuizSession).where(QuizSession.user_id == user.id, QuizSession.client_id == body.client_id)
                         .options(selectinload(QuizSession.questions)))
    if existing:
        response.status_code = 200
        return {"duplicate": True, "ignored": 0, **_result(db, existing).model_dump(mode="json")}
    ids = [a.question_id for a in body.answers]
    qs = {q.id: q for q in db.scalars(visible_questions().where(Question.id.in_(ids or [0])).options(selectinload(Question.options)))}
    now = utcnow()
    s = QuizSession(user_id=user.id, mode=SessionMode.practice, title=body.title, unit_id=body.unit_id, started_at=body.started_at or now,
                    client_id=body.client_id, status=SessionStatus.in_progress)
    seen, ignored, pos = set(), 0, 0
    for a in body.answers:
        q = qs.get(a.question_id)
        if q is None or a.question_id in seen:
            ignored += 1
            continue
        seen.add(a.question_id)
        snap = grading.snapshot_question(q)
        sq = SessionQuestion(position=pos, question_id=q.id, snapshot=snap, option_order=grading.option_order(snap, shuffle=False))
        if a.selected_option_id is not None and grading.valid_option(snap, a.selected_option_id):
            sq.selected_option_id = a.selected_option_id
            sq.is_correct = grading.is_correct(snap, a.selected_option_id)
            sq.answered_at = min(a.answered_at or now, now)
            record_progress(db, user.id, q.id, bool(sq.is_correct), sq.answered_at)
        else:
            ignored += 1 if a.selected_option_id is not None else 0
        s.questions.append(sq)
        pos += 1
    if not s.questions:
        raise err(422, "nothing_to_sync", "None of the submitted questions are available any more.")
    db.add(s)
    try:
        db.flush()
        finalize(db, s)
    except IntegrityError:                  # two syncs raced: the other one won
        db.rollback()
        existing = db.scalar(select(QuizSession).where(QuizSession.user_id == user.id, QuizSession.client_id == body.client_id)
                             .options(selectinload(QuizSession.questions)))
        return {"duplicate": True, "ignored": 0, **_result(db, existing).model_dump(mode="json")}
    db.refresh(s)
    response.status_code = 201
    return {"duplicate": False, "ignored": ignored, **_result(db, s).model_dump(mode="json")}
