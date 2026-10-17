import time

from tests.conftest import _h, make_content, register

K1, K2, K3 = "a" * 64, "b" * 64, "c" * 64


def now_ms():
    return int(time.time() * 1000)


def put(client, h, state):
    return client.put("/app/state", json={"state": state}, headers=h)


# ---------------------------------------------------------------- bank
def test_bank_requires_sign_in(client):
    assert client.get("/app/bank").status_code == 401


def test_bank_has_app_shape_and_only_published_content(client, admin_h, student):
    make_content(client, admin_h, n=3, title="Visible unit")
    make_content(client, admin_h, publish=False, n=2, title="Draft unit")
    r = client.get("/app/bank", headers=student["h"])
    assert r.status_code == 200
    b = r.json()
    assert b["version"] == 2 and [s["id"] for s in b["subjects"]] == ["math"]
    titles = [u["title"] for u in b["units"]]
    assert titles == ["Visible unit"]                                  # draft-only unit is absent
    u = b["units"][0]
    assert u["grade"] == 11 and u["subject"] == "math" and u["no"] == 1 and len(u["qs"]) == 3
    q = u["qs"][0]
    assert set(q) >= {"id", "k", "q", "o", "a"} and len(q["k"]) == 64
    assert q["o"][q["a"]] == "0"                                       # first generated question: 0 + 0 = 0, answer index points at the correct option
    assert "Draft" not in r.text


def test_bank_etag_and_change_detection(client, admin_h, student):
    c = make_content(client, admin_h, n=2)
    r1 = client.get("/app/bank", headers=student["h"])
    etag = r1.headers["etag"]
    assert client.get("/app/bank", headers={**student["h"], "If-None-Match": etag}).status_code == 304
    client.patch(f"/admin/questions/{c['qids'][0]}", json={"text": "Edited question text here"}, headers=admin_h)
    r2 = client.get("/app/bank", headers={**student["h"], "If-None-Match": etag})
    assert r2.status_code == 200 and r2.headers["etag"] != etag and "Edited question text here" in r2.text
    client.post(f"/admin/questions/{c['qids'][0]}/unpublish", headers=admin_h)
    assert "Edited question text here" not in client.get("/app/bank", headers=student["h"]).text


# ---------------------------------------------------------------- state
def test_state_starts_empty_and_requires_auth(client, student):
    assert client.get("/app/state").status_code == 401
    assert client.get("/app/state", headers=student["h"]).json()["state"] == {"b": {}, "f": {}, "a": {}, "h": []}


def test_state_round_trip(client, student):
    t = now_ms() - 1000
    st = {"b": {K1: [t, 1]}, "f": {K2: [t, 1]}, "a": {K1: [t, 0], K3: [t, 1]}, "h": [{"id": "s1", "ti": "Math", "m": "exam", "n": 10, "c": 7, "ts": t, "d": 300}]}
    r = put(client, student["h"], st)
    assert r.status_code == 200 and r.json()["state"] == st
    assert client.get("/app/state", headers=student["h"]).json()["state"] == st


def test_last_write_wins_per_key_and_devices_converge(client, student):
    h = student["h"]
    t = now_ms() - 10_000
    put(client, h, {"b": {K1: [t, 1]}, "a": {K1: [t, 0]}})                          # phone A: bookmarked K1, answered it wrong
    r = put(client, h, {"b": {K1: [t + 5000, 0], K2: [t, 1]}, "a": {K1: [t - 5, 1]}})   # phone B: un-bookmarked K1 later; older correct answer
    s = r.json()["state"]
    assert s["b"][K1] == [t + 5000, 0] and s["b"][K2] == [t, 1]                    # newer removal wins, new bookmark kept
    assert s["a"][K1] == [t, 0]                                                    # older answer does not overwrite the newer one
    again = put(client, h, {"b": {K1: [t + 5000, 0]}}).json()["state"]
    assert again == s                                                               # idempotent


def test_history_is_unioned_and_capped(client, student):
    h = student["h"]
    t = now_ms() - 100_000
    mk = lambda i, ts: {"id": f"h{i}", "ti": "x", "m": "practice", "n": 5, "c": 3, "ts": ts}
    put(client, h, {"h": [mk(1, t), mk(2, t + 1)]})
    s = put(client, h, {"h": [mk(2, t + 1), mk(3, t + 2)]}).json()["state"]
    assert [x["id"] for x in s["h"]] == ["h3", "h2", "h1"]
    s = put(client, h, {"h": [mk(i, t + 10 + i) for i in range(100, 350)]}).json()["state"]     # 250 new entries
    assert len(s["h"]) == 200
    assert s["h"][0]["id"] == "h349" and "h1" not in [x["id"] for x in s["h"]]                 # newest kept, oldest dropped


def test_state_validation(client, student):
    h = student["h"]
    t = now_ms()
    bad = [
        {"b": {"short": [t, 1]}},                                  # key too short
        {"b": {K1: [t, 2]}},                                       # value must be 0/1
        {"b": {K1: [t]}},                                          # wrong shape
        {"b": {K1: [True, 1]}},                                    # bool is not a timestamp
        {"b": {K1: [-1, 1]}},
        {"b": [K1]},
        {"h": [{"id": "x", "ti": "t", "m": "weird", "n": 1, "c": 1, "ts": t}]},
        {"h": [{"id": "x", "ti": "t", "m": "exam", "n": 1, "c": 5, "ts": t}]},   # correct > total
        {"h": [{"ti": "t", "m": "exam", "n": 1, "c": 1, "ts": t}]},              # no id
    ]
    for b in bad:
        r = put(client, h, b)
        assert r.status_code == 422 and r.json()["error"]["code"] == "bad_state", b
    assert client.put("/app/state", json={"state": [1]}, headers=h).status_code == 422
    assert client.put("/app/state", content=b"not json", headers=h).status_code == 422


def test_future_timestamps_are_clamped(client, student):
    h = student["h"]
    far = now_ms() + 10 ** 12
    s = put(client, h, {"b": {K1: [far, 1]}}).json()["state"]
    assert s["b"][K1][0] < now_ms() + 10 * 60 * 1000
    # a normal write made right now is older than the clamped one, so it loses: that is the documented cost of clamping
    s = put(client, h, {"b": {K1: [now_ms(), 0]}}).json()["state"]
    assert s["b"][K1][1] == 1


def test_state_is_private_per_student_and_deleted_with_account(client, student):
    t = now_ms() - 1000
    put(client, student["h"], {"b": {K1: [t, 1]}})
    other = register(client, name="Other Student", phone="0955555555")
    oh = _h(other["access_token"])
    assert client.get("/app/state", headers=oh).json()["state"]["b"] == {}
    assert client.request("DELETE", "/me", json={"password": "Student123"}, headers=student["h"]).status_code == 204
    from tests.conftest import STUDENT_PW
    again = register(client, name="Abebe Kebede", phone="0912345678", pw=STUDENT_PW)
    assert client.get("/app/state", headers=_h(again["access_token"])).json()["state"]["b"] == {}


def test_oversized_state_rejected(client, student):
    t = now_ms() - 1000
    big = {"b": {f"{i:064d}": [t, 1] for i in range(21_000)}}
    r = put(client, student["h"], big)
    assert r.status_code == 422 and r.json()["error"]["code"] == "bad_state"


def test_reset_progress_keeps_bookmarks(client, student):
    h = student["h"]
    t = now_ms() - 1000
    put(client, h, {"b": {K1: [t, 1]}, "a": {K2: [t, 0]}, "h": [{"id": "h1", "ti": "x", "m": "practice", "n": 2, "c": 1, "ts": t}]})
    assert client.delete("/app/state", headers=h).status_code == 204
    s = client.get("/app/state", headers=h).json()["state"]
    assert s["a"] == {} and s["h"] == [] and s["b"] == {K1: [t, 1]}
    assert client.delete("/app/state").status_code == 401
