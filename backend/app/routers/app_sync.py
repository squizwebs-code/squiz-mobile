"""Endpoints for the offline-first Flutter app.

* GET /app/bank   the published question bank in the app's own JSON shape (ETag cached) so admin edits reach phones.
* GET/PUT /app/state   per-student state (bookmarks, flags, latest answer per question, quiz history) with a
  deterministic last-write-wins merge, so several devices and offline edits converge without losing data.
"""
import hashlib
import json
import time

from fastapi import APIRouter, Depends, Request, Response
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from ..db import get_db
from ..deps import current_user, err
from ..models import AppState, Grade, Question, Subject, Unit, User, utcnow
from ..visibility import visible_questions, visible_units

router = APIRouter(prefix="/app", tags=["mobile app"])

MAX_BODY_BYTES = 2_000_000
MAX_SET = 20_000          # per map (bookmarks / flags / answers)
MAX_HISTORY = 200
FUTURE_SKEW_MS = 5 * 60 * 1000


# ------------------------------------------------------------------ bank
@router.get("/bank")
def bank(request: Request, response: Response, db: Session = Depends(get_db), _: User = Depends(current_user)):
    """Everything the app needs, with answers (used for offline practice and on-device exams). Unpublished content is never included."""
    units, subjects = [], {}
    sub_rows = {s.id: s for s in db.scalars(select(Subject))}
    by_unit: dict[int, list] = {}
    rows = db.scalars(visible_questions().options(selectinload(Question.options)).order_by(Question.unit_id, Question.id)).all()
    for q in rows:
        opts = sorted(q.options, key=lambda o: o.position)
        correct = next((i for i, o in enumerate(opts) if o.is_correct), None)
        if correct is None or len(opts) < 2:
            continue
        item = {"id": f"q{q.id}", "k": q.text_key, "q": q.text, "o": [o.text for o in opts], "a": correct}
        if q.explanation:
            item["e"] = q.explanation
        if q.image_url:
            item["img"] = q.image_url
        by_unit.setdefault(q.unit_id, []).append(item)
    counters: dict[tuple, int] = {}
    grades = {g.id: g.number for g in db.scalars(select(Grade))}
    for u in db.scalars(visible_units()):
        qs = by_unit.get(u.id)
        if not qs:
            continue
        sub = sub_rows[u.subject_id]
        subjects[sub.key] = sub
        no = 0
        if u.kind == "unit":
            counters[(u.grade_id, u.subject_id)] = counters.get((u.grade_id, u.subject_id), 0) + 1
            no = counters[(u.grade_id, u.subject_id)]
        units.append({"id": f"u{u.id}", "grade": grades[u.grade_id], "subject": sub.key, "no": no, "title": u.title, "kind": u.kind, "qs": qs})
    body = {"version": 2, "generated": utcnow().date().isoformat(), "subjects": [{"id": k, "name": v.name, "t": v.track} for k, v in sorted(subjects.items(), key=lambda kv: (kv[1].position, kv[1].name))], "units": units}
    payload = json.dumps(body, separators=(",", ":"), ensure_ascii=False)
    etag = '"' + hashlib.sha256(payload.encode()).hexdigest()[:24] + '"'
    if request.headers.get("if-none-match") == etag:
        return Response(status_code=304, headers={"ETag": etag})
    return Response(payload, media_type="application/json", headers={"ETag": etag, "Cache-Control": "private, no-cache"})


# ------------------------------------------------------------------ state
def _entry_map(raw, name: str) -> dict[str, list[int]]:
    if raw is None:
        return {}
    if not isinstance(raw, dict) or len(raw) > MAX_SET:
        raise err(422, "bad_state", f"'{name}' is not valid.")
    now_cap = int(time.time() * 1000) + FUTURE_SKEW_MS
    out = {}
    for k, v in raw.items():
        if (not isinstance(k, str) or not 8 <= len(k) <= 80 or not isinstance(v, list) or len(v) != 2
                or not all(isinstance(x, int) and not isinstance(x, bool) for x in v) or v[1] not in (0, 1) or v[0] < 0):
            raise err(422, "bad_state", f"'{name}' contains an invalid entry.")
        out[k] = [min(v[0], now_cap), v[1]]            # a client cannot win every future merge with a far-future timestamp
    return out


def _history(raw) -> list[dict]:
    if raw is None:
        return []
    if not isinstance(raw, list) or len(raw) > MAX_HISTORY * 2:
        raise err(422, "bad_state", "'h' is not valid.")
    out = []
    for h in raw:
        try:
            ok = (isinstance(h, dict) and isinstance(h["id"], str) and 1 <= len(h["id"]) <= 40 and isinstance(h["ti"], str) and len(h["ti"]) <= 200
                  and h["m"] in ("practice", "exam") and isinstance(h["n"], int) and 0 <= h["n"] <= 500 and isinstance(h["c"], int) and 0 <= h["c"] <= h["n"]
                  and isinstance(h["ts"], int) and h["ts"] >= 0 and (h.get("d") is None or (isinstance(h["d"], int) and 0 <= h["d"] <= 86400)))
        except (KeyError, TypeError):
            ok = False
        if not ok:
            raise err(422, "bad_state", "'h' contains an invalid entry.")
        out.append({k: h[k] for k in ("id", "ti", "m", "n", "c", "ts") if k in h} | ({"d": h["d"]} if h.get("d") is not None else {}))
    return out


def clean_state(raw) -> dict:
    if not isinstance(raw, dict):
        raise err(422, "bad_state", "State must be an object.")
    return {"b": _entry_map(raw.get("b"), "b"), "f": _entry_map(raw.get("f"), "f"), "a": _entry_map(raw.get("a"), "a"), "h": _history(raw.get("h"))}


def merge_state(server: dict, client: dict) -> dict:
    """Per-key last-write-wins (ties keep the server's value); history is a union by id, newest 200 kept."""
    out = {}
    for name in ("b", "f", "a"):
        m = dict(server.get(name, {}))
        for k, v in client.get(name, {}).items():
            cur = m.get(k)
            if cur is None or v[0] > cur[0]:
                m[k] = v
        out[name] = m
    hist = {h["id"]: h for h in server.get("h", [])}
    for h in client.get("h", []):
        hist.setdefault(h["id"], h)
    out["h"] = sorted(hist.values(), key=lambda h: h["ts"], reverse=True)[:MAX_HISTORY]
    return out


def _row(db: Session, user_id: int, lock: bool) -> AppState | None:
    st = select(AppState).where(AppState.user_id == user_id)
    return db.scalar(st.with_for_update() if lock else st)


@router.get("/state")
def get_state(db: Session = Depends(get_db), user: User = Depends(current_user)):
    row = _row(db, user.id, False)
    return {"state": clean_state(row.data) if row else {"b": {}, "f": {}, "a": {}, "h": []}, "updated_at": row.updated_at if row else None}


@router.put("/state")
async def put_state(request: Request, db: Session = Depends(get_db), user: User = Depends(current_user)):
    raw = await request.body()
    if len(raw) > MAX_BODY_BYTES:
        raise err(413, "too_large", "That sync is too large.")
    try:
        body = json.loads(raw)
    except ValueError:
        raise err(422, "bad_state", "Body must be JSON.")
    incoming = clean_state(body.get("state") if isinstance(body, dict) else None)
    for attempt in (0, 1):
        row = _row(db, user.id, True)                         # row lock: two devices syncing at once are applied one after the other
        try:
            if row is None:
                row = AppState(user_id=user.id, data=merge_state({}, incoming))
                db.add(row)
            else:
                row.data = merge_state(clean_state(row.data), incoming)
            db.commit()
            break
        except IntegrityError:
            db.rollback()                                      # lost the insert race: retry once and merge into the other device's row
            if attempt:
                raise
    return {"state": row.data, "updated_at": row.updated_at}


@router.delete("/state", status_code=204)
def reset_progress(db: Session = Depends(get_db), user: User = Depends(current_user)):
    """Clears answers and quiz history ("reset my progress"). Bookmarks and flags are kept."""
    row = _row(db, user.id, True)
    if row is not None:
        data = clean_state(row.data)
        row.data = {"b": data["b"], "f": data["f"], "a": {}, "h": []}
        db.commit()
    return Response(status_code=204)
