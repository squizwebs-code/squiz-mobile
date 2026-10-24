"""One place that defines what a student is allowed to see (published, not deleted, whole chain published)."""
from sqlalchemy import and_, func, select

from .models import Grade, GradeSubject, PublishStatus, Question, Subject, Unit


def visible_questions(grade_number: int | None = None, subject_id: int | None = None, unit_id: int | None = None):
    q = (select(Question).join(Unit, Unit.id == Question.unit_id).join(Grade, Grade.id == Unit.grade_id)
         .join(Subject, Subject.id == Unit.subject_id)
         .join(GradeSubject, and_(GradeSubject.grade_id == Unit.grade_id, GradeSubject.subject_id == Unit.subject_id))
         .where(Question.status == PublishStatus.published, Question.deleted_at.is_(None), Unit.published.is_(True),
                Grade.published.is_(True), Subject.published.is_(True), GradeSubject.published.is_(True),
                Unit.archived_at.is_(None), Grade.archived_at.is_(None), Subject.archived_at.is_(None)))
    if grade_number is not None:
        q = q.where(Grade.number == grade_number)
    if subject_id is not None:
        q = q.where(Unit.subject_id == subject_id)
    if unit_id is not None:
        q = q.where(Question.unit_id == unit_id)
    return q


def visible_question_ids_subquery(**kw):
    return visible_questions(**kw).with_only_columns(Question.id).subquery()


def visible_units(grade_number: int | None = None, subject_id: int | None = None):
    q = (select(Unit).join(Grade, Grade.id == Unit.grade_id).join(Subject, Subject.id == Unit.subject_id)
         .join(GradeSubject, and_(GradeSubject.grade_id == Unit.grade_id, GradeSubject.subject_id == Unit.subject_id))
         .where(Unit.published.is_(True), Grade.published.is_(True), Subject.published.is_(True), GradeSubject.published.is_(True),
                Unit.archived_at.is_(None), Grade.archived_at.is_(None), Subject.archived_at.is_(None)))
    if grade_number is not None:
        q = q.where(Grade.number == grade_number)
    if subject_id is not None:
        q = q.where(Unit.subject_id == subject_id)
    return q.order_by(Unit.position, Unit.id)


def question_counts_by_unit(db, grade_number: int | None = None, subject_id: int | None = None) -> dict[int, int]:
    sub = visible_questions(grade_number, subject_id).subquery()
    rows = db.execute(select(sub.c.unit_id, func.count()).group_by(sub.c.unit_id)).all()
    return {u: c for u, c in rows}
