from datetime import datetime, timedelta, timezone

from app.models import QuizSession
from tests.conftest import _h, make_content, register


def _correct_text(q):          # test helper: questions are "What is i + i": correct option is str(2*i)
    i = int(q["text"].split()[2])
    return str(2 * i)


def _pick(q, correct=True):
    want = _correct_text(q)
    for o in q["options"]:
        if (o["text"] == want) == correct:
            return o["id"]


def test_practice_flow_feedback_progress_and_history(client, admin_h, student):
    c = make_content(client, admin_h, n=4)
    sh = student["h"]
    s = client.post("/sessions", json={"mode": "practice", "unit_id": c["unit_id"]}, headers=sh)
    assert s.status_code in (200, 201), s.text
    s = s.json()
    assert s["total"] == 4 and s["mode"] == "practice" and s["expires_at"] is None
    q0, q1 = s["questions"][0], s["questions"][1]
    r = client.put(f"/sessions/{s['id']}/answers", json={"question_id": q0["question_id"], "selected_option_id": _pick(q0)}, headers=sh).json()
    assert r["is_correct"] is True and r["explanation"] and r["correct_option_id"] == _pick(q0)
    wrong = _pick(q1, correct=False)
    r = client.put(f"/sessions/{s['id']}/answers", json={"question_id": q1["question_id"], "selected_option_id": wrong}, headers=sh).json()
    assert r["is_correct"] is False
    # locked after first answer
    again = client.put(f"/sessions/{s['id']}/answers", json={"question_id": q1["question_id"], "selected_option_id": _pick(q1)}, headers=sh)
    assert again.status_code == 409 and again.json()["error"]["code"] == "already_answered"
    # resume shows saved state
    back = client.get(f"/sessions/{s['id']}", headers=sh).json()
    assert back["answered"] == 2
    fin = client.post(f"/sessions/{s['id']}/submit", json={}, headers=sh)
    assert fin.status_code == 200
    res = client.get(f"/sessions/{s['id']}/result", headers=sh).json()
    assert res["attempt"]["correct"] == 1 and res["attempt"]["wrong"] == 1 and res["attempt"]["skipped"] == 2
    assert len(client.get("/attempts", headers=sh).json()["items"]) == 1
    stats = client.get("/me/stats", headers=sh).json()
    assert stats["questions_answered"] >= 2
    inc = client.get("/me/incorrect", headers=sh).json()
    assert q1["question_id"] in [x["id"] for x in (inc["items"] if isinstance(inc, dict) else inc)]


def test_exam_hides_answers_until_submit_and_locks_afterwards(client, admin_h, student):
    c = make_content(client, admin_h, n=4)
    sh = student["h"]
    s = client.post("/sessions", json={"mode": "exam", "unit_id": c["unit_id"], "count": 4, "limit_minutes": 10}, headers=sh).json()
    assert s["expires_at"] and s["limit_seconds"] == 600
    blob = str(s)
    assert "correct_option_id" in blob and all(q["correct_option_id"] is None and q["is_correct"] is None and q["explanation"] is None for q in s["questions"])
    q = s["questions"][0]
    r = client.put(f"/sessions/{s['id']}/answers", json={"question_id": q["question_id"], "selected_option_id": _pick(q, correct=False)}, headers=sh).json()
    assert r["saved"] is True and r["is_correct"] is None and r["correct_option_id"] is None and r["explanation"] is None
    # answers can be changed before submit
    assert client.put(f"/sessions/{s['id']}/answers", json={"question_id": q["question_id"], "selected_option_id": _pick(q)}, headers=sh).status_code == 200
    # result not available before submit
    assert client.get(f"/sessions/{s['id']}/result", headers=sh).status_code in (400, 403, 404, 409)
    mid = client.get(f"/sessions/{s['id']}", headers=sh).json()
    assert all(x["correct_option_id"] is None for x in mid["questions"])
    # server grades: a client cannot claim a score; unanswered submitted answers are applied
    sub = client.post(f"/sessions/{s['id']}/submit", json={"answers": [{"question_id": s["questions"][1]["question_id"], "selected_option_id": _pick(s["questions"][1])}]}, headers=sh)
    assert sub.status_code == 200
    res = client.get(f"/sessions/{s['id']}/result", headers=sh).json()
    assert res["attempt"]["correct"] == 2 and res["attempt"]["skipped"] == 2
    assert all(x["correct_option_id"] for x in res["questions"])
    # locked
    assert client.put(f"/sessions/{s['id']}/answers", json={"question_id": q["question_id"], "selected_option_id": _pick(q, correct=False)}, headers=sh).status_code in (400, 409)
    # idempotent submit
    again = client.post(f"/sessions/{s['id']}/submit", json={}, headers=sh)
    assert again.status_code == 200
    assert len(client.get("/attempts", headers=sh).json()["items"]) == 1
    assert client.get(f"/sessions/{s['id']}/result", headers=sh).json()["attempt"]["correct"] == 2


def test_exam_expiry_is_enforced_by_the_server(client, admin_h, student, db):
    c = make_content(client, admin_h, n=3)
    sh = student["h"]
    s = client.post("/sessions", json={"mode": "exam", "unit_id": c["unit_id"], "limit_minutes": 5}, headers=sh).json()
    q = s["questions"][0]
    client.put(f"/sessions/{s['id']}/answers", json={"question_id": q["question_id"], "selected_option_id": _pick(q)}, headers=sh)
    row = db.get(QuizSession, s["id"])
    row.expires_at = datetime.now(timezone.utc) - timedelta(minutes=5)        # well past the grace period
    db.commit()
    late = client.put(f"/sessions/{s['id']}/answers", json={"question_id": q["question_id"], "selected_option_id": _pick(q, correct=False)}, headers=sh)
    assert late.status_code in (400, 409, 410)
    res = client.get(f"/sessions/{s['id']}/result", headers=sh).json()
    assert res["attempt"]["timed_out"] is True and res["attempt"]["correct"] == 1     # only the answer given in time counts


def test_sessions_are_private_between_students(client, admin_h, student):
    c = make_content(client, admin_h, n=2)
    s = client.post("/sessions", json={"mode": "practice", "unit_id": c["unit_id"]}, headers=student["h"]).json()
    other = register(client, name="Other Student", phone="0944444444")
    oh = _h(other["access_token"])
    assert client.get(f"/sessions/{s['id']}", headers=oh).status_code == 404
    q = s["questions"][0]
    assert client.put(f"/sessions/{s['id']}/answers", json={"question_id": q["question_id"], "selected_option_id": _pick(q)}, headers=oh).status_code == 404
    assert client.post(f"/sessions/{s['id']}/submit", json={}, headers=oh).status_code == 404


def test_invalid_option_rejected(client, admin_h, student):
    c = make_content(client, admin_h, n=2)
    s = client.post("/sessions", json={"mode": "practice", "unit_id": c["unit_id"]}, headers=student["h"]).json()
    r = client.put(f"/sessions/{s['id']}/answers", json={"question_id": s["questions"][0]["question_id"], "selected_option_id": 999999}, headers=student["h"])
    assert r.status_code in (400, 404, 422)


def test_editing_or_deleting_question_does_not_change_history(client, admin_h, student):
    c = make_content(client, admin_h, n=2)
    sh = student["h"]
    s = client.post("/sessions", json={"mode": "practice", "unit_id": c["unit_id"]}, headers=sh).json()
    for q in s["questions"]:
        client.put(f"/sessions/{s['id']}/answers", json={"question_id": q["question_id"], "selected_option_id": _pick(q)}, headers=sh)
    client.post(f"/sessions/{s['id']}/submit", json={}, headers=sh)
    before = client.get(f"/sessions/{s['id']}/result", headers=sh).json()
    qid = c["qids"][0]
    assert client.patch(f"/admin/questions/{qid}", json={"text": "Totally rewritten question text"}, headers=admin_h).status_code == 200
    client.delete(f"/admin/questions/{c['qids'][1]}", params={"confirm": "true"}, headers=admin_h)
    after = client.get(f"/sessions/{s['id']}/result", headers=sh).json()
    assert [q["text"] for q in after["questions"]] == [q["text"] for q in before["questions"]]
    assert after["attempt"]["correct"] == before["attempt"]["correct"] == 2


def test_offline_practice_sync_is_idempotent(client, admin_h, student):
    c = make_content(client, admin_h, n=3)
    sh = student["h"]
    pack = client.get("/content/offline-pack", params={"grade": 11}, headers=sh)
    assert pack.status_code == 200
    qs = [q for q in str(pack.json()) and _flatten_questions(pack.json())]
    assert len(qs) >= 3
    first = qs[0]
    body = {"client_id": "device-abc-123456", "title": "Offline practice", "unit_id": c["unit_id"],
            "answers": [{"question_id": first["id"], "selected_option_id": next(o["id"] for o in first["options"] if o["is_correct"])}]}
    a = client.post("/sync/practice", json=body, headers=sh)
    assert a.status_code in (200, 201), a.text
    b = client.post("/sync/practice", json=body, headers=sh)
    assert b.status_code in (200, 201)
    assert len(client.get("/attempts", headers=sh).json()["items"]) == 1       # not duplicated


def _flatten_questions(pack):
    out = []
    def walk(x):
        if isinstance(x, dict):
            if "text" in x and "options" in x and "id" in x:
                out.append(x)
            for v in x.values():
                walk(v)
        elif isinstance(x, list):
            for v in x:
                walk(v)
    walk(pack)
    return out


def test_bookmarks_and_flags(client, admin_h, student):
    c = make_content(client, admin_h, n=2)
    sh = student["h"]
    qid = c["qids"][0]
    assert client.put(f"/bookmarks/{qid}", headers=sh).status_code in (200, 201, 204)
    assert client.put(f"/bookmarks/{qid}", headers=sh).status_code in (200, 201, 204)       # idempotent
    bm = client.get("/bookmarks", headers=sh).json()
    assert len(bm["items"] if isinstance(bm, dict) else bm) == 1
    assert client.delete(f"/bookmarks/{qid}", headers=sh).status_code in (200, 204)
    bm = client.get("/bookmarks", headers=sh).json()
    assert len(bm["items"] if isinstance(bm, dict) else bm) == 0
    assert client.put(f"/flags/{qid}", headers=sh).status_code in (200, 201, 204)


def test_dashboard_and_search(client, admin_h, student):
    make_content(client, admin_h, n=3)
    sh = student["h"]
    assert client.get("/me/dashboard", headers=sh).status_code == 200
    r = client.get("/search", params={"q": "What is"}, headers=sh)
    assert r.status_code == 200
    assert "is_correct" not in str(r.json())
