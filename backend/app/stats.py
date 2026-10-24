"""Statistics for the admin panel.

The mobile app keeps each student's learning data in one JSON document (app_states): the latest answer per question
(`a`) and the list of finished quizzes (`h`). Everything about learning is computed from those documents; account
numbers come from the users table. Questions are matched through their content key (`Question.text_key`).
"""
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from .config import get_settings
from .models import AccountStatus, AppState, Grade, PublishStatus, Question, Role, Subject, Unit, User, utcnow


def _tz() -> ZoneInfo:
    return ZoneInfo(get_settings().app_timezone)


def _pct(c: int, n: int) -> int | None:
    return round(c * 100 / n) if n else None


def key_index(db: Session) -> dict[str, dict]:
    """content key -> where that question lives (published copies win)."""
    rows = db.execute(
        select(Question.text_key, Question.status, Question.id, Unit.id, Subject.key, Subject.name, Grade.number, Subject.track)
        .join(Unit, Unit.id == Question.unit_id).join(Subject, Subject.id == Unit.subject_id).join(Grade, Grade.id == Unit.grade_id)
        .where(Question.deleted_at.is_(None)).order_by(Question.id)).all()
    out: dict[str, dict] = {}
    for key, status, qid, uid, skey, sname, gnum, track in rows:
        cur = out.get(key)
        if cur is None or (cur["status"] != PublishStatus.published and status == PublishStatus.published):
            out[key] = {"qid": qid, "status": status, "unit_id": uid, "subject": skey, "subject_name": sname, "grade": gnum, "track": track}
    return out


def _answers(state: dict, start_ms: int | None = None, end_ms: int | None = None):
    for k, v in (state.get("a") or {}).items():
        if isinstance(v, list) and len(v) == 2 and (start_ms is None or v[0] >= start_ms) and (end_ms is None or v[0] < end_ms):
            yield k, v[0], bool(v[1])


def user_progress(db: Session, state: dict) -> dict:
    idx = key_index(db)
    n = c = 0
    per: dict[str, list] = defaultdict(lambda: [0, 0, ""])
    for k, _, ok in _answers(state):
        n += 1
        c += ok
        info = idx.get(k)
        if info:
            row = per[info["subject"]]
            row[0] += 1
            row[1] += ok
            row[2] = info["subject_name"]
    hist = [h for h in (state.get("h") or []) if isinstance(h, dict)]
    hist.sort(key=lambda h: -h.get("ts", 0))
    return {"answered": n, "correct": c, "accuracy": _pct(c, n), "bookmarks": sum(1 for v in (state.get("b") or {}).values() if v[1]),
            "flags": sum(1 for v in (state.get("f") or {}).values() if v[1]),
            "sessions": len(hist), "exams": sum(1 for h in hist if h.get("m") == "exam"),
            "by_subject": sorted([{"subject": name, "answered": a, "correct": b, "accuracy": _pct(b, a)} for _, (a, b, name) in per.items()], key=lambda x: x["subject"]),
            "recent": [{"title": h.get("ti"), "mode": h.get("m"), "correct": h.get("c"), "total": h.get("n"), "at": datetime.fromtimestamp(h.get("ts", 0) / 1000, _tz()).isoformat(), "seconds": h.get("d")} for h in hist[:10]]}


def _day_series(counter: Counter, start: date, end: date) -> list[dict]:
    out, d = [], start
    while d <= end:
        out.append({"date": d.isoformat(), "count": counter.get(d, 0)})
        d += timedelta(days=1)
    return out


def compute(db: Session, start: date | None = None, end: date | None = None, min_answers: int = 5) -> dict:
    tz, now = _tz(), utcnow()
    today = now.astimezone(tz).date()
    end = end or today
    start = start or (end - timedelta(days=29))
    start_ms = int(datetime.combine(start, datetime.min.time(), tz).timestamp() * 1000)
    end_ms = int(datetime.combine(end + timedelta(days=1), datetime.min.time(), tz).timestamp() * 1000)
    idx = key_index(db)

    # ---------------- users ----------------
    users = db.scalars(select(User)).all()
    by_role = Counter(u.role.value for u in users)
    suspended = sum(1 for u in users if u.status == AccountStatus.inactive)
    new_per_day = Counter(u.created_at.astimezone(tz).date() for u in users if start <= u.created_at.astimezone(tz).date() <= end)

    def active_since(days: int) -> int:
        return sum(1 for u in users if u.last_active_at and u.last_active_at >= now - timedelta(days=days))

    def retention(days: int):
        cohort = [u for u in users if u.role == Role.student and u.created_at <= now - timedelta(days=days)]
        kept = [u for u in cohort if u.last_active_at and u.last_active_at >= u.created_at + timedelta(days=days)]
        return {"cohort": len(cohort), "returned": len(kept), "percent": _pct(len(kept), len(cohort))}

    users_block = {
        "total": len(users), "students": by_role.get("student", 0), "admins": by_role.get("admin", 0), "suspended": suspended,
        "new_in_range": sum(new_per_day.values()), "new_per_day": _day_series(new_per_day, start, end),
        "active": {"daily": active_since(1), "weekly": active_since(7), "monthly": active_since(30)},
        "retention": {"day_1": retention(1), "day_7": retention(7), "day_30": retention(30)},
        "by_grade": [{"grade": g, "users": n} for g, n in sorted(Counter(u.selected_grade for u in users if u.selected_grade).items())],
        "by_track": dict(Counter(u.selected_track or "not chosen" for u in users if u.role == Role.student)),
    }

    # ---------------- learning (from app state documents) ----------------
    per_subject: dict[str, list] = defaultdict(lambda: [0, 0, ""])
    per_grade: dict[int, list] = defaultdict(lambda: [0, 0])
    per_key: dict[str, list] = defaultdict(lambda: [0, 0])
    answered_total = correct_total = 0
    learners: set[int] = set()
    sessions_day: Counter = Counter()
    hours: Counter = Counter()
    weekdays: Counter = Counter()
    modes: dict[str, list] = defaultdict(lambda: [0, 0, 0, 0])      # sessions, sum percent, sum seconds, sessions with duration
    ever_answered: set[str] = set()
    for uid, data in db.execute(select(AppState.user_id, AppState.data)).all():
        data = data or {}
        for k, _, _ in _answers(data):
            ever_answered.add(k)
        for k, ts, ok in _answers(data, start_ms, end_ms):
            learners.add(uid)
            answered_total += 1
            correct_total += ok
            pk = per_key[k]
            pk[0] += 1
            pk[1] += ok
            info = idx.get(k)
            if info:
                ps = per_subject[info["subject"]]
                ps[0] += 1
                ps[1] += ok
                ps[2] = info["subject_name"]
                pg = per_grade[info["grade"]]
                pg[0] += 1
                pg[1] += ok
        for h in data.get("h") or []:
            if not isinstance(h, dict) or not isinstance(h.get("ts"), int) or not start_ms <= h["ts"] < end_ms:
                continue
            learners.add(uid)
            local = datetime.fromtimestamp(h["ts"] / 1000, tz)
            sessions_day[local.date()] += 1
            hours[local.hour] += 1
            weekdays[local.weekday()] += 1
            m = modes[h.get("m", "practice")]
            m[0] += 1
            m[1] += round(h.get("c", 0) * 100 / h["n"]) if h.get("n") else 0
            if isinstance(h.get("d"), int):
                m[2] += h["d"]
                m[3] += 1
    names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    learning_block = {
        "active_learners": len(learners), "questions_answered": answered_total, "correct": correct_total, "accuracy": _pct(correct_total, answered_total),
        "by_subject": sorted([{"subject": name, "answered": a, "correct": b, "accuracy": _pct(b, a)} for _, (a, b, name) in per_subject.items()], key=lambda x: x["subject"]),
        "by_grade": [{"grade": g, "answered": a, "correct": b, "accuracy": _pct(b, a)} for g, (a, b) in sorted(per_grade.items())],
        "sessions": {"total": sum(m[0] for m in modes.values()),
                     "by_mode": {k: {"sessions": m[0], "average_percent": round(m[1] / m[0]) if m[0] else None,
                                     "average_minutes": round(m[2] / m[3] / 60, 1) if m[3] else None} for k, m in modes.items()},
                     "per_day": _day_series(sessions_day, start, end)},
        "busiest_hours": [{"hour": h, "sessions": hours.get(h, 0)} for h in range(24)],
        "busiest_weekdays": [{"day": names[i], "sessions": weekdays.get(i, 0)} for i in range(7)],
    }

    # ---------------- question quality ----------------
    items = []
    for k, (n, c) in per_key.items():
        info = idx.get(k)
        if info and n >= min_answers:
            items.append({"question_id": info["qid"], "answered": n, "correct": c, "accuracy": _pct(c, n), "subject": info["subject_name"], "grade": info["grade"]})
    texts = {q.id: q.text for q in db.scalars(select(Question).where(Question.id.in_([i["question_id"] for i in items] or [0])))}
    for i in items:
        i["text"] = texts.get(i["question_id"], "")[:160]
    hardest = sorted(items, key=lambda i: (i["accuracy"], -i["answered"]))[:15]
    easiest = sorted(items, key=lambda i: (-i["accuracy"], -i["answered"]))[:15]
    suspect = [i for i in sorted(items, key=lambda i: i["accuracy"]) if i["accuracy"] < 25][:15]
    published_keys = {k for k, v in idx.items() if v["status"] == PublishStatus.published}
    unanswered = sorted(published_keys - ever_answered)
    un_ids = [idx[k]["qid"] for k in unanswered[:15]]
    un_text = {q.id: q.text for q in db.scalars(select(Question).where(Question.id.in_(un_ids or [0])))}
    quality_block = {"min_answers": min_answers, "hardest": hardest, "easiest": easiest, "may_have_wrong_answer_key": suspect,
                     "never_answered_count": len(unanswered),
                     "never_answered_sample": [{"question_id": i, "text": un_text.get(i, "")[:160]} for i in un_ids]}

    # ---------------- content ----------------
    qrows = db.execute(select(Grade.number, Subject.name, Question.status, func.count()).select_from(Question).join(Unit, Unit.id == Question.unit_id)
                       .join(Grade, Grade.id == Unit.grade_id).join(Subject, Subject.id == Unit.subject_id).where(Question.deleted_at.is_(None))
                       .group_by(Grade.number, Subject.name, Question.status)).all()
    table: dict[tuple, dict] = {}
    totals = Counter()
    for g, s, st, n in qrows:
        row = table.setdefault((g, s), {"grade": g, "subject": s, "published": 0, "draft": 0, "archived": 0})
        row[st.value] += n
        totals[st.value] += n
    unit_rows = db.execute(select(Grade.number, Subject.name, func.count()).select_from(Unit).join(Grade, Grade.id == Unit.grade_id).join(Subject, Subject.id == Unit.subject_id)
                           .where(Unit.archived_at.is_(None)).group_by(Grade.number, Subject.name)).all()
    for g, s, n in unit_rows:
        table.setdefault((g, s), {"grade": g, "subject": s, "published": 0, "draft": 0, "archived": 0})["units"] = n
    content_block = {"questions": dict(totals), "units": sum(n for _, _, n in unit_rows),
                     "subjects": db.scalar(select(func.count()).select_from(Subject).where(Subject.archived_at.is_(None))),
                     "by_grade_subject": [{"units": 0, **v} for _, v in sorted(table.items())]}
    return {"range": {"from": start.isoformat(), "to": end.isoformat(), "timezone": get_settings().app_timezone}, "users": users_block,
            "learning": learning_block, "questions": quality_block, "content": content_block}


def tables_for_export(data: dict) -> dict[str, list[list]]:
    """Flat tables for CSV/Excel export."""
    t: dict[str, list[list]] = {}
    u, l, q, c = data["users"], data["learning"], data["questions"], data["content"]
    t["summary"] = [["Metric", "Value"], ["From", data["range"]["from"]], ["To", data["range"]["to"]], ["Total users", u["total"]], ["Students", u["students"]],
                    ["Administrators", u["admins"]], ["Suspended", u["suspended"]], ["New users in range", u["new_in_range"]],
                    ["Daily active", u["active"]["daily"]], ["Weekly active", u["active"]["weekly"]], ["Monthly active", u["active"]["monthly"]],
                    ["Active learners in range", l["active_learners"]], ["Questions answered", l["questions_answered"]], ["Overall accuracy %", l["accuracy"]],
                    ["Quizzes finished", l["sessions"]["total"]], ["Questions (published)", c["questions"].get("published", 0)],
                    ["Questions (draft)", c["questions"].get("draft", 0)], ["Questions (archived)", c["questions"].get("archived", 0)]]
    t["new_users_per_day"] = [["Date", "New users"]] + [[d["date"], d["count"]] for d in u["new_per_day"]]
    t["sessions_per_day"] = [["Date", "Quizzes finished"]] + [[d["date"], d["count"]] for d in l["sessions"]["per_day"]]
    t["accuracy_by_subject"] = [["Subject", "Answered", "Correct", "Accuracy %"]] + [[r["subject"], r["answered"], r["correct"], r["accuracy"]] for r in l["by_subject"]]
    t["accuracy_by_grade"] = [["Grade", "Answered", "Correct", "Accuracy %"]] + [[r["grade"], r["answered"], r["correct"], r["accuracy"]] for r in l["by_grade"]]
    t["busiest_hours"] = [["Hour", "Quizzes"]] + [[r["hour"], r["sessions"]] for r in l["busiest_hours"]]
    t["busiest_weekdays"] = [["Day", "Quizzes"]] + [[r["day"], r["sessions"]] for r in l["busiest_weekdays"]]
    t["hardest_questions"] = [["Question id", "Grade", "Subject", "Answered", "Accuracy %", "Text"]] + [[r["question_id"], r["grade"], r["subject"], r["answered"], r["accuracy"], r["text"]] for r in q["hardest"]]
    t["possible_wrong_keys"] = [["Question id", "Grade", "Subject", "Answered", "Accuracy %", "Text"]] + [[r["question_id"], r["grade"], r["subject"], r["answered"], r["accuracy"], r["text"]] for r in q["may_have_wrong_answer_key"]]
    t["content"] = [["Grade", "Subject", "Units", "Published", "Draft", "Archived"]] + [[r["grade"], r["subject"], r.get("units", 0), r["published"], r["draft"], r["archived"]] for r in c["by_grade_subject"]]
    return t
