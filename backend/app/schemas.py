"""Pydantic request/response schemas."""
from datetime import datetime
from typing import Generic, Literal, TypeVar

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from .models import Difficulty, PublishStatus
from .phone import PhoneError, normalize_phone
from .security import password_problem

T = TypeVar("T")


class Page(BaseModel, Generic[T]):
    items: list[T]
    total: int
    page: int
    size: int


class Orm(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# ---------------- auth ----------------
class RegisterIn(BaseModel):
    full_name: str = Field(min_length=1, max_length=120)
    phone: str
    password: str
    confirm_password: str

    @field_validator("full_name")
    @classmethod
    def _name(cls, v: str) -> str:
        v = " ".join(v.split())
        if len(v) < 2:
            raise ValueError("Full name must have at least 2 characters")
        return v

    @field_validator("phone")
    @classmethod
    def _phone(cls, v: str) -> str:
        try:
            return normalize_phone(v)
        except PhoneError as e:
            raise ValueError(str(e))

    @model_validator(mode="after")
    def _pw(self):
        p = password_problem(self.password)
        if p:
            raise ValueError(p)
        if self.password != self.confirm_password:
            raise ValueError("Passwords do not match")
        return self


class LoginIn(BaseModel):
    identifier: str = Field(min_length=1, max_length=120)      # full name or phone number
    password: str = Field(min_length=1, max_length=128)


class RefreshIn(BaseModel):
    refresh_token: str


class ChangePasswordIn(BaseModel):
    current_password: str
    new_password: str

    @field_validator("new_password")
    @classmethod
    def _np(cls, v: str) -> str:
        p = password_problem(v)
        if p:
            raise ValueError(p)
        return v


class UserOut(Orm):
    id: int
    full_name: str
    phone: str
    role: str
    status: str
    selected_grade: int | None
    must_change_password: bool
    created_at: datetime


class TokenOut(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int
    user: UserOut


class ProfileUpdate(BaseModel):
    full_name: str | None = Field(default=None, min_length=2, max_length=120)
    selected_grade: int | None = Field(default=None, ge=1, le=12)


class DeleteAccountIn(BaseModel):
    password: str


# ---------------- content (student view) ----------------
class GradeOut(Orm):
    id: int
    number: int
    name: str


class SubjectOut(BaseModel):
    id: int
    key: str
    name: str
    icon: str | None
    unit_count: int
    question_count: int


class UnitOut(BaseModel):
    id: int
    title: str
    kind: str
    position: int
    subject_id: int
    grade_number: int
    question_count: int


class OptionOut(BaseModel):
    id: int
    text: str


class QuestionOut(BaseModel):
    id: int
    unit_id: int
    text: str
    image_url: str | None
    difficulty: str | None
    options: list[OptionOut]


# ---------------- quizzes ----------------
class StartSessionIn(BaseModel):
    mode: Literal["practice", "exam"]
    unit_id: int | None = None
    subject_id: int | None = None
    grade_number: int | None = Field(default=None, ge=1, le=12)
    count: int | None = Field(default=None, ge=1, le=100)
    shuffle: bool | None = None
    limit_minutes: int | None = Field(default=None, ge=1, le=240)

    @model_validator(mode="after")
    def _scope(self):
        if self.unit_id is None and self.grade_number is None:
            raise ValueError("Provide unit_id, or grade_number (with optional subject_id) for a mixed session")
        if self.mode == "practice" and self.limit_minutes:
            raise ValueError("Practice sessions have no time limit")
        return self


class SessionQuestionOut(BaseModel):
    position: int
    question_id: int | None
    text: str
    image_url: str | None
    options: list[OptionOut]
    selected_option_id: int | None = None
    # Only filled for practice sessions (immediate feedback) or after an exam is submitted:
    is_correct: bool | None = None
    correct_option_id: int | None = None
    explanation: str | None = None


class SessionOut(BaseModel):
    id: int
    mode: str
    status: str
    title: str
    started_at: datetime
    expires_at: datetime | None
    limit_seconds: int | None
    server_time: datetime
    answered: int
    total: int
    questions: list[SessionQuestionOut]


class AnswerIn(BaseModel):
    question_id: int
    selected_option_id: int | None = None       # null clears the answer (exam only)


class AnswerOut(BaseModel):
    saved: bool
    is_correct: bool | None = None
    correct_option_id: int | None = None
    explanation: str | None = None


class SubmitIn(BaseModel):
    answers: list[AnswerIn] = Field(default_factory=list, max_length=200)


class AttemptOut(Orm):
    id: int
    session_id: int
    mode: str
    title: str
    total: int
    correct: int
    wrong: int
    skipped: int
    percentage: int
    duration_seconds: int | None
    timed_out: bool
    submitted_at: datetime


class ResultOut(BaseModel):
    attempt: AttemptOut
    questions: list[SessionQuestionOut]


class SyncAnswer(BaseModel):
    question_id: int
    selected_option_id: int | None = None
    answered_at: datetime | None = None


class SyncPracticeIn(BaseModel):
    client_id: str = Field(min_length=8, max_length=64)       # idempotency key generated on the device
    title: str = Field(min_length=1, max_length=200)
    unit_id: int | None = None
    started_at: datetime | None = None
    answers: list[SyncAnswer] = Field(max_length=300)


# ---------------- admin ----------------
class GradeIn(BaseModel):
    number: int = Field(ge=1, le=12)
    name: str = Field(min_length=1, max_length=60)
    published: bool = True


class GradePatch(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=60)
    published: bool | None = None


class SubjectIn(BaseModel):
    key: str = Field(min_length=2, max_length=40, pattern=r"^[a-z0-9_-]+$")
    name: str = Field(min_length=1, max_length=80)
    icon: str | None = Field(default=None, max_length=40)
    published: bool = True


class SubjectPatch(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=80)
    icon: str | None = Field(default=None, max_length=40)
    published: bool | None = None


class AssignIn(BaseModel):
    published: bool = True


class UnitIn(BaseModel):
    grade_id: int
    subject_id: int
    title: str = Field(min_length=1, max_length=120)
    kind: Literal["unit", "extra", "quick"] = "unit"
    published: bool = True


class UnitPatch(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=120)
    kind: Literal["unit", "extra", "quick"] | None = None
    published: bool | None = None


class ReorderIn(BaseModel):
    grade_id: int
    subject_id: int
    unit_ids: list[int] = Field(min_length=1)


class OptionIn(BaseModel):
    text: str = Field(min_length=1, max_length=1000)
    is_correct: bool = False

    @field_validator("text")
    @classmethod
    def _strip(cls, v: str) -> str:
        v = " ".join(v.split())
        if not v:
            raise ValueError("Option text must not be empty")
        return v


class QuestionIn(BaseModel):
    unit_id: int
    text: str = Field(min_length=3, max_length=4000)
    explanation: str | None = Field(default=None, max_length=4000)
    difficulty: Difficulty | None = None
    image_url: str | None = Field(default=None, max_length=300)
    status: PublishStatus = PublishStatus.draft
    options: list[OptionIn] = Field(min_length=2, max_length=8)

    @field_validator("text")
    @classmethod
    def _t(cls, v: str) -> str:
        return " ".join(v.split())

    @model_validator(mode="after")
    def _opts(self):
        if sum(1 for o in self.options if o.is_correct) != 1:
            raise ValueError("Exactly one option must be marked correct")
        texts = [o.text.casefold() for o in self.options]
        if len(set(texts)) != len(texts):
            raise ValueError("Answer options must be different from each other")
        return self


class QuestionPatch(BaseModel):
    unit_id: int | None = None
    text: str | None = Field(default=None, min_length=3, max_length=4000)
    explanation: str | None = Field(default=None, max_length=4000)
    difficulty: Difficulty | None = None
    image_url: str | None = Field(default=None, max_length=300)
    options: list[OptionIn] | None = Field(default=None, min_length=2, max_length=8)
    clear_difficulty: bool = False
    clear_image: bool = False
    clear_explanation: bool = False

    @model_validator(mode="after")
    def _opts(self):
        if self.options is not None:
            if sum(1 for o in self.options if o.is_correct) != 1:
                raise ValueError("Exactly one option must be marked correct")
            texts = [o.text.casefold() for o in self.options]
            if len(set(texts)) != len(texts):
                raise ValueError("Answer options must be different from each other")
        return self


class StudentStatusIn(BaseModel):
    status: Literal["active", "inactive"]


class SettingsIn(BaseModel):
    app_name: str | None = Field(default=None, min_length=1, max_length=60)
    default_grade: int | None = Field(default=None, ge=1, le=12)
    allow_name_change: bool | None = None
    tagline: str | None = Field(default=None, max_length=120)
