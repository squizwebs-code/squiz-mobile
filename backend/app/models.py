"""SQLAlchemy models. Hierarchy: Grade -> (GradeSubject) Subject -> Unit -> Question -> AnswerOption.

History is preserved by snapshotting questions into SessionQuestion at quiz start, so editing,
archiving or soft-deleting a question never changes past results.
"""
import enum
from datetime import datetime, timezone

from sqlalchemy import (JSON, BigInteger, Boolean, CheckConstraint, DateTime, Enum, ForeignKey, Index, Integer, String,
                        Text, UniqueConstraint, func)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .db import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Role(str, enum.Enum):
    student = "student"
    admin = "admin"


class AccountStatus(str, enum.Enum):
    active = "active"
    inactive = "inactive"


class Difficulty(str, enum.Enum):
    easy = "easy"
    medium = "medium"
    hard = "hard"


class PublishStatus(str, enum.Enum):
    draft = "draft"
    published = "published"
    archived = "archived"


class SessionMode(str, enum.Enum):
    practice = "practice"
    exam = "exam"


class SessionStatus(str, enum.Enum):
    in_progress = "in_progress"
    submitted = "submitted"


TS = DateTime(timezone=True)


class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    full_name: Mapped[str] = mapped_column(String(120))
    name_key: Mapped[str] = mapped_column(String(120), index=True)          # casefolded, whitespace-collapsed full name
    phone: Mapped[str] = mapped_column(String(20), unique=True)              # normalized E.164
    password_hash: Mapped[str] = mapped_column(String(255))
    role: Mapped[Role] = mapped_column(Enum(Role, name="role"), default=Role.student)
    status: Mapped[AccountStatus] = mapped_column(Enum(AccountStatus, name="account_status"), default=AccountStatus.active)
    selected_grade: Mapped[int | None] = mapped_column(Integer, nullable=True)
    selected_track: Mapped[str | None] = mapped_column(String(10), nullable=True)   # natural | social | None (grades 11-12 stream)
    username: Mapped[str] = mapped_column(String(30), unique=True)                  # stored lower-case; sign in with username or phone
    is_owner: Mapped[bool] = mapped_column(Boolean, default=False)                  # the first administrator: cannot be demoted, suspended or deleted
    promoted_by_id: Mapped[int | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    suspended_reason: Mapped[str | None] = mapped_column(String(200), nullable=True)
    suspended_at: Mapped[datetime | None] = mapped_column(TS, nullable=True)
    suspended_until: Mapped[datetime | None] = mapped_column(TS, nullable=True)     # None = until an administrator re-activates
    suspended_by_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    must_change_password: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(TS, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(TS, default=utcnow, onupdate=utcnow)
    last_active_at: Mapped[datetime | None] = mapped_column(TS, nullable=True)


class RefreshToken(Base):
    __tablename__ = "refresh_tokens"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    family_id: Mapped[str] = mapped_column(String(36), index=True)
    expires_at: Mapped[datetime] = mapped_column(TS)
    revoked_at: Mapped[datetime | None] = mapped_column(TS, nullable=True)
    created_at: Mapped[datetime] = mapped_column(TS, default=utcnow)
    scope: Mapped[str] = mapped_column(String(10), default="student")        # student | admin


class Grade(Base):
    __tablename__ = "grades"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    number: Mapped[int] = mapped_column(Integer, unique=True)
    name: Mapped[str] = mapped_column(String(60))
    published: Mapped[bool] = mapped_column(Boolean, default=True)
    archived_at: Mapped[datetime | None] = mapped_column(TS, nullable=True)
    subject_links: Mapped[list["GradeSubject"]] = relationship(back_populates="grade", cascade="all, delete-orphan")


class Subject(Base):
    __tablename__ = "subjects"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    key: Mapped[str] = mapped_column(String(40), unique=True)
    name: Mapped[str] = mapped_column(String(80))
    icon: Mapped[str | None] = mapped_column(String(40), nullable=True)
    track: Mapped[str] = mapped_column(String(10), default="all")             # all | natural | social (Matric stream the subject belongs to)
    position: Mapped[int] = mapped_column(Integer, default=0)
    published: Mapped[bool] = mapped_column(Boolean, default=True)
    archived_at: Mapped[datetime | None] = mapped_column(TS, nullable=True)
    grade_links: Mapped[list["GradeSubject"]] = relationship(back_populates="subject", cascade="all, delete-orphan")


class GradeSubject(Base):
    """Assigns a subject to a grade and controls its visibility there."""
    __tablename__ = "grade_subjects"
    grade_id: Mapped[int] = mapped_column(ForeignKey("grades.id", ondelete="CASCADE"), primary_key=True)
    subject_id: Mapped[int] = mapped_column(ForeignKey("subjects.id", ondelete="CASCADE"), primary_key=True)
    published: Mapped[bool] = mapped_column(Boolean, default=True)
    grade: Mapped[Grade] = relationship(back_populates="subject_links")
    subject: Mapped[Subject] = relationship(back_populates="grade_links")


class Unit(Base):
    __tablename__ = "units"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    grade_id: Mapped[int] = mapped_column(ForeignKey("grades.id", ondelete="CASCADE"))
    subject_id: Mapped[int] = mapped_column(ForeignKey("subjects.id", ondelete="CASCADE"))
    title: Mapped[str] = mapped_column(String(120))
    kind: Mapped[str] = mapped_column(String(10), default="unit")           # unit | extra | quick
    position: Mapped[int] = mapped_column(Integer, default=0)
    published: Mapped[bool] = mapped_column(Boolean, default=True)
    archived_at: Mapped[datetime | None] = mapped_column(TS, nullable=True)
    created_at: Mapped[datetime] = mapped_column(TS, default=utcnow)
    grade: Mapped[Grade] = relationship()
    subject: Mapped[Subject] = relationship()
    __table_args__ = (UniqueConstraint("grade_id", "subject_id", "title", name="uq_unit_title"),
                      Index("ix_units_grade_subject", "grade_id", "subject_id", "position"))


class Question(Base):
    __tablename__ = "questions"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    unit_id: Mapped[int] = mapped_column(ForeignKey("units.id", ondelete="RESTRICT"), index=True)
    text: Mapped[str] = mapped_column(Text)
    text_key: Mapped[str] = mapped_column(String(64), index=True)           # sha256 of normalised text, for duplicate detection
    explanation: Mapped[str | None] = mapped_column(Text, nullable=True)
    difficulty: Mapped[Difficulty | None] = mapped_column(Enum(Difficulty, name="difficulty"), nullable=True)
    image_url: Mapped[str | None] = mapped_column(String(300), nullable=True)
    status: Mapped[PublishStatus] = mapped_column(Enum(PublishStatus, name="publish_status"), default=PublishStatus.draft, index=True)
    version: Mapped[int] = mapped_column(Integer, default=1)
    source_ref: Mapped[str | None] = mapped_column(String(160), nullable=True)
    created_at: Mapped[datetime] = mapped_column(TS, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(TS, default=utcnow, onupdate=utcnow)
    deleted_at: Mapped[datetime | None] = mapped_column(TS, nullable=True)  # soft delete keeps history intact
    unit: Mapped[Unit] = relationship()
    options: Mapped[list["AnswerOption"]] = relationship(back_populates="question", cascade="all, delete-orphan", order_by="AnswerOption.position")


class AnswerOption(Base):
    __tablename__ = "answer_options"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    question_id: Mapped[int] = mapped_column(ForeignKey("questions.id", ondelete="CASCADE"), index=True)
    text: Mapped[str] = mapped_column(Text)
    is_correct: Mapped[bool] = mapped_column(Boolean, default=False)
    position: Mapped[int] = mapped_column(Integer, default=0)
    question: Mapped[Question] = relationship(back_populates="options")


class QuizSession(Base):
    __tablename__ = "quiz_sessions"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    mode: Mapped[SessionMode] = mapped_column(Enum(SessionMode, name="session_mode"))
    status: Mapped[SessionStatus] = mapped_column(Enum(SessionStatus, name="session_status"), default=SessionStatus.in_progress)
    title: Mapped[str] = mapped_column(String(200))
    grade_number: Mapped[int | None] = mapped_column(Integer, nullable=True)
    subject_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    unit_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    limit_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)
    started_at: Mapped[datetime] = mapped_column(TS, default=utcnow)
    expires_at: Mapped[datetime | None] = mapped_column(TS, nullable=True)
    submitted_at: Mapped[datetime | None] = mapped_column(TS, nullable=True)
    client_id: Mapped[str | None] = mapped_column(String(64), nullable=True)   # idempotency key for offline sync
    questions: Mapped[list["SessionQuestion"]] = relationship(back_populates="session", cascade="all, delete-orphan", order_by="SessionQuestion.position")
    __table_args__ = (UniqueConstraint("user_id", "client_id", name="uq_session_client"),
                      Index("ix_sessions_user_status", "user_id", "status"))


class SessionQuestion(Base):
    """Question as it was when the session started (snapshot) + the student's answer."""
    __tablename__ = "session_questions"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    session_id: Mapped[int] = mapped_column(ForeignKey("quiz_sessions.id", ondelete="CASCADE"), index=True)
    question_id: Mapped[int | None] = mapped_column(Integer, nullable=True)  # plain int: survives deletion of the question
    position: Mapped[int] = mapped_column(Integer)
    snapshot: Mapped[dict] = mapped_column(JSON)                              # {text, explanation, image_url, options:[{id,text,is_correct}], version}
    option_order: Mapped[list] = mapped_column(JSON)                          # option ids in display order
    selected_option_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    is_correct: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    answered_at: Mapped[datetime | None] = mapped_column(TS, nullable=True)
    session: Mapped[QuizSession] = relationship(back_populates="questions")
    __table_args__ = (UniqueConstraint("session_id", "position", name="uq_session_position"),
                      Index("ix_sq_question", "question_id"))


class QuizAttempt(Base):
    """Authoritative, server-computed result of a submitted session."""
    __tablename__ = "quiz_attempts"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    session_id: Mapped[int] = mapped_column(ForeignKey("quiz_sessions.id", ondelete="CASCADE"), unique=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    mode: Mapped[str] = mapped_column(String(10))
    title: Mapped[str] = mapped_column(String(200))
    subject_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    unit_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    grade_number: Mapped[int | None] = mapped_column(Integer, nullable=True)
    total: Mapped[int] = mapped_column(Integer)
    correct: Mapped[int] = mapped_column(Integer)
    wrong: Mapped[int] = mapped_column(Integer)
    skipped: Mapped[int] = mapped_column(Integer)
    percentage: Mapped[int] = mapped_column(Integer)
    duration_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)
    timed_out: Mapped[bool] = mapped_column(Boolean, default=False)
    submitted_at: Mapped[datetime] = mapped_column(TS, default=utcnow, index=True)
    __table_args__ = (CheckConstraint("total >= 0"),)


class Bookmark(Base):
    __tablename__ = "bookmarks"
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    question_id: Mapped[int] = mapped_column(ForeignKey("questions.id", ondelete="CASCADE"), primary_key=True)
    created_at: Mapped[datetime] = mapped_column(TS, default=utcnow)


class StudentProgress(Base):
    """Per-student, per-question stats (powers accuracy, mistakes list, flags)."""
    __tablename__ = "student_progress"
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    question_id: Mapped[int] = mapped_column(ForeignKey("questions.id", ondelete="CASCADE"), primary_key=True)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    correct_count: Mapped[int] = mapped_column(Integer, default=0)
    last_correct: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    last_at: Mapped[datetime | None] = mapped_column(TS, nullable=True)
    flagged: Mapped[bool] = mapped_column(Boolean, default=False)


class AuditLog(Base):
    __tablename__ = "audit_logs"
    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    admin_id: Mapped[int | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    admin_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    action: Mapped[str] = mapped_column(String(60), index=True)
    entity: Mapped[str | None] = mapped_column(String(40), nullable=True)
    entity_id: Mapped[str | None] = mapped_column(String(40), nullable=True)
    details: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    ip: Mapped[str | None] = mapped_column(String(45), nullable=True)
    created_at: Mapped[datetime] = mapped_column(TS, default=utcnow, index=True)


class AppSetting(Base):
    __tablename__ = "app_settings"
    key: Mapped[str] = mapped_column(String(60), primary_key=True)
    value: Mapped[dict] = mapped_column(JSON)


class AppState(Base):
    """Per-student learning state for the offline-first mobile app (bookmarks, flags, last answers, history).

    Stored as one JSON document keyed by question *content key* (sha256 of the normalised question text), so state
    created against the bundled question bank still matches questions served from the database.
    """
    __tablename__ = "app_states"
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    data: Mapped[dict] = mapped_column(JSON, default=dict)
    updated_at: Mapped[datetime] = mapped_column(TS, default=utcnow, onupdate=utcnow)


class ImportBatch(Base):
    """One Excel/CSV/JSON import. `items` records exactly what was created or changed so the whole batch can be undone."""
    __tablename__ = "import_batches"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    admin_id: Mapped[int | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    admin_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    filename: Mapped[str] = mapped_column(String(200))
    policy: Mapped[str] = mapped_column(String(10), default="skip")          # skip | update | add
    status: Mapped[str] = mapped_column(String(12), default="committed")     # committed | undone
    counts: Mapped[dict] = mapped_column(JSON, default=dict)
    items: Mapped[list] = mapped_column(JSON, default=list)
    created_at: Mapped[datetime] = mapped_column(TS, default=utcnow, index=True)
    undone_at: Mapped[datetime | None] = mapped_column(TS, nullable=True)


class Announcement(Base):
    __tablename__ = "announcements"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    title: Mapped[str] = mapped_column(String(120))
    body: Mapped[str] = mapped_column(Text)
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    expires_at: Mapped[datetime | None] = mapped_column(TS, nullable=True)
    created_by: Mapped[int | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(TS, default=utcnow, index=True)


class QuestionReport(Base):
    """A student says a question looks wrong. Matched by content key because the app identifies questions that way."""
    __tablename__ = "question_reports"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    question_key: Mapped[str] = mapped_column(String(64), index=True)
    question_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    question_text: Mapped[str] = mapped_column(Text)
    reason: Mapped[str] = mapped_column(String(20))                          # wrong_answer | typo | unclear | other
    note: Mapped[str | None] = mapped_column(String(500), nullable=True)
    status: Mapped[str] = mapped_column(String(10), default="open", index=True)   # open | resolved | dismissed
    created_at: Mapped[datetime] = mapped_column(TS, default=utcnow, index=True)
    resolved_by: Mapped[int | None] = mapped_column(Integer, nullable=True)
    resolved_at: Mapped[datetime | None] = mapped_column(TS, nullable=True)
