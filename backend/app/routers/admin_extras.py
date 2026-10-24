"""Admin: statistics (+ Excel/CSV export), announcements, question reports. Student-facing halves live under /app."""
import csv
import io
from datetime import date, datetime
from typing import Literal

from fastapi import APIRouter, Depends, Query, Request, Response
from openpyxl import Workbook
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from .. import ratelimit, stats
from ..db import get_db
from ..deps import admin_user, audit, current_user, err
from ..models import Announcement, Question, QuestionReport, User, utcnow
from ..schemas import Page

admin_router = APIRouter(prefix="/admin", tags=["admin"], dependencies=[Depends(admin_user)])
app_router = APIRouter(prefix="/app", tags=["mobile app"])


# ------------------------------------------------------------------ statistics
@admin_router.get("/stats")
def get_stats(date_from: date | None = Query(None, alias="from"), date_to: date | None = Query(None, alias="to"), min_answers: int = Query(5, ge=1, le=1000),
              db: Session = Depends(get_db)):
    if date_from and date_to and date_from > date_to:
        raise err(422, "bad_range", "'from' must not be after 'to'.")
    return stats.compute(db, date_from, date_to, min_answers)


def _xlsx_safe(v):
    return "'" + v if isinstance(v, str) and v[:1] in ("=", "+", "-", "@") else v        # never let imported text run as a formula


@admin_router.get("/stats/export")
def export_stats(format: Literal["xlsx", "csv"] = "xlsx", table: str | None = None, date_from: date | None = Query(None, alias="from"),
                 date_to: date | None = Query(None, alias="to"), request: Request = None, db: Session = Depends(get_db), admin: User = Depends(admin_user)):
    tables = stats.tables_for_export(stats.compute(db, date_from, date_to))
    audit(db, admin, "stats.export", "stats", None, {"format": format, "table": table}, request)
    db.commit()
    if format == "csv":
        name = table or "summary"
        if name not in tables:
            raise err(404, "unknown_table", f"Unknown table. Choose one of: {', '.join(tables)}")
        buf = io.StringIO()
        csv.writer(buf).writerows([[_xlsx_safe(c) for c in row] for row in tables[name]])
        return Response("﻿" + buf.getvalue(), media_type="text/csv; charset=utf-8", headers={"Content-Disposition": f'attachment; filename="squiz-{name}.csv"'})
    wb = Workbook()
    wb.remove(wb.active)
    for name, rows in tables.items():
        ws = wb.create_sheet(name[:31])
        for row in rows:
            ws.append([_xlsx_safe(c) for c in row])
        ws.freeze_panes = "A2"
        for col in ws.columns:
            ws.column_dimensions[col[0].column_letter].width = min(60, max(10, max(len(str(c.value or "")) for c in col) + 2))
    out = io.BytesIO()
    wb.save(out)
    return Response(out.getvalue(), media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                    headers={"Content-Disposition": 'attachment; filename="squiz-statistics.xlsx"'})


# ------------------------------------------------------------------ announcements
class AnnouncementIn(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    body: str = Field(min_length=1, max_length=2000)
    expires_at: datetime | None = None
    active: bool = True


class AnnouncementPatch(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=120)
    body: str | None = Field(default=None, min_length=1, max_length=2000)
    expires_at: datetime | None = None
    clear_expiry: bool = False
    active: bool | None = None


def _ann(a: Announcement) -> dict:
    return {"id": a.id, "title": a.title, "body": a.body, "active": a.active, "expires_at": a.expires_at, "created_at": a.created_at}


@admin_router.get("/announcements")
def list_announcements(db: Session = Depends(get_db)):
    return [_ann(a) for a in db.scalars(select(Announcement).order_by(Announcement.id.desc()).limit(200))]


@admin_router.post("/announcements", status_code=201)
def create_announcement(body: AnnouncementIn, request: Request, db: Session = Depends(get_db), admin: User = Depends(admin_user)):
    a = Announcement(title=body.title.strip(), body=body.body.strip(), expires_at=body.expires_at, active=body.active, created_by=admin.id)
    db.add(a)
    db.flush()
    audit(db, admin, "announcement.create", "announcement", a.id, {"title": a.title}, request)
    db.commit()
    return _ann(a)


@admin_router.patch("/announcements/{aid}")
def update_announcement(aid: int, body: AnnouncementPatch, request: Request, db: Session = Depends(get_db), admin: User = Depends(admin_user)):
    a = db.get(Announcement, aid) or (_ for _ in ()).throw(err(404, "not_found", "Announcement not found."))
    data = body.model_dump(exclude_unset=True)
    if data.pop("clear_expiry", False):
        a.expires_at = None
    for k, v in data.items():
        setattr(a, k, v)
    audit(db, admin, "announcement.update", "announcement", a.id, None, request)
    db.commit()
    return _ann(a)


@admin_router.delete("/announcements/{aid}", status_code=204)
def delete_announcement(aid: int, request: Request, db: Session = Depends(get_db), admin: User = Depends(admin_user)):
    a = db.get(Announcement, aid) or (_ for _ in ()).throw(err(404, "not_found", "Announcement not found."))
    audit(db, admin, "announcement.delete", "announcement", a.id, {"title": a.title}, request)
    db.delete(a)
    db.commit()
    return Response(status_code=204)


@app_router.get("/announcements")
def student_announcements(db: Session = Depends(get_db), _: User = Depends(current_user)):
    now = utcnow()
    rows = db.scalars(select(Announcement).where(Announcement.active.is_(True)).order_by(Announcement.id.desc()).limit(20)).all()
    return [{"id": a.id, "title": a.title, "body": a.body, "created_at": a.created_at} for a in rows if a.expires_at is None or a.expires_at > now]


# ------------------------------------------------------------------ question reports
class ReportIn(BaseModel):
    key: str = Field(min_length=8, max_length=80)
    reason: Literal["wrong_answer", "typo", "unclear", "other"]
    note: str | None = Field(default=None, max_length=500)


@app_router.post("/reports", status_code=201)
def create_report(body: ReportIn, request: Request, db: Session = Depends(get_db), user: User = Depends(current_user)):
    ratelimit.check(f"report-user:{user.id}", 20, 3600)
    q = db.scalar(select(Question).where(Question.text_key == body.key, Question.deleted_at.is_(None)).order_by(Question.id))
    if q is None:
        raise err(404, "question_not_found", "That question is no longer in the bank.")
    dup = db.scalar(select(QuestionReport.id).where(QuestionReport.user_id == user.id, QuestionReport.question_key == body.key, QuestionReport.status == "open"))
    if dup:
        return {"id": dup, "duplicate": True}
    r = QuestionReport(user_id=user.id, question_key=body.key, question_id=q.id, question_text=q.text, reason=body.reason, note=(body.note or "").strip() or None)
    db.add(r)
    db.commit()
    return {"id": r.id, "duplicate": False}


def _report(r: QuestionReport, reporter: str | None, count: int) -> dict:
    return {"id": r.id, "question_id": r.question_id, "question_text": r.question_text, "reason": r.reason, "note": r.note, "status": r.status,
            "reporter": reporter, "created_at": r.created_at, "resolved_at": r.resolved_at, "reports_for_question": count}


@admin_router.get("/reports")
def list_reports(status: Literal["open", "resolved", "dismissed"] | None = "open", page: int = Query(1, ge=1), size: int = Query(20, ge=1, le=100),
                 db: Session = Depends(get_db)):
    st = select(QuestionReport)
    if status:
        st = st.where(QuestionReport.status == status)
    total = db.scalar(select(func.count()).select_from(st.subquery()))
    rows = db.scalars(st.order_by(QuestionReport.id.desc()).offset((page - 1) * size).limit(size)).all()
    names = {u.id: u.full_name for u in db.scalars(select(User).where(User.id.in_([r.user_id for r in rows if r.user_id] or [0])))}
    counts = dict(db.execute(select(QuestionReport.question_key, func.count()).where(QuestionReport.question_key.in_([r.question_key for r in rows] or [""])).group_by(QuestionReport.question_key)).all())
    return Page(items=[_report(r, names.get(r.user_id), counts.get(r.question_key, 1)) for r in rows], total=total, page=page, size=size)


def _close(rid: int, status: str, request: Request, db: Session, admin: User):
    r = db.get(QuestionReport, rid) or (_ for _ in ()).throw(err(404, "not_found", "Report not found."))
    r.status, r.resolved_by, r.resolved_at = status, admin.id, utcnow()
    audit(db, admin, f"report.{status}", "report", r.id, None, request)
    db.commit()
    return _report(r, None, 1)


@admin_router.post("/reports/{rid}/resolve")
def resolve_report(rid: int, request: Request, db: Session = Depends(get_db), admin: User = Depends(admin_user)):
    return _close(rid, "resolved", request, db, admin)


@admin_router.post("/reports/{rid}/dismiss")
def dismiss_report(rid: int, request: Request, db: Session = Depends(get_db), admin: User = Depends(admin_user)):
    return _close(rid, "dismissed", request, db, admin)
