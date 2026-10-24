from datetime import datetime, timedelta, timezone

import jwt

from app.models import Role, User
from tests.conftest import STUDENT_PW, _h, register


def _reg(client, **kw):
    body = {"full_name": "Abebe Kebede", "username": "abebe_k", "phone": "0912345678", "password": STUDENT_PW, "confirm_password": STUDENT_PW, **kw}
    return client.post("/auth/register", json=body)


def test_phone_normalisation_and_duplicates(client, grades):
    t = register(client, phone="0912 345 678")
    assert t["user"]["phone"] == "+251912345678"
    for i, variant in enumerate(("+251912345678", "251912345678", "912345678", "09-12-345-678", "00251912345678")):
        r = _reg(client, full_name="Other Person", username=f"other{i}", phone=variant)
        assert r.status_code == 409 and r.json()["error"]["code"] == "phone_taken", variant


def test_register_validation_messages(client, grades):
    assert "at least 6" in _reg(client, password="Ab1", confirm_password="Ab1").json()["error"]["message"]
    assert "do not match" in _reg(client, confirm_password="Different123").json()["error"]["message"]
    assert _reg(client, phone="12345").status_code == 422
    assert _reg(client, phone="abc").status_code == 422
    assert _reg(client, full_name="   ").status_code == 422
    assert _reg(client, full_name="A").status_code == 422
    for bad in ("ab", "has space", "bad!char", "12345678", "x" * 31):
        assert _reg(client, username=bad).status_code == 422, bad
    assert _reg(client).status_code == 201


def test_password_needs_only_six_characters_of_any_kind(client, grades):
    for i, pw in enumerate(("aaaaaa", "123456", "!!!!!!", "pass word")):
        r = _reg(client, username=f"pw{i}", phone=f"09{i}1111111", password=pw, confirm_password=pw)
        assert r.status_code == 201, (pw, r.text)
        assert client.post("/auth/login", json={"identifier": f"pw{i}", "password": pw}).status_code == 200
    assert _reg(client, username="short1", phone="0966666666", password="12345", confirm_password="12345").status_code == 422


def test_username_is_unique_case_insensitive_and_login_works_with_username_or_phone(client, grades):
    assert _reg(client, username="Abebe_K").status_code == 201
    dup = _reg(client, username="abebe_k", phone="0922222222")
    assert dup.status_code == 409 and dup.json()["error"]["code"] == "username_taken"
    assert client.get("/auth/username-available", params={"username": "ABEBE_K"}).json()["available"] is False
    assert client.get("/auth/username-available", params={"username": "free_name"}).json()["available"] is True
    for ident in ("abebe_k", "  ABEBE_K ", "0912345678", "+251 912 345 678"):
        r = client.post("/auth/login", json={"identifier": ident, "password": STUDENT_PW})
        assert r.status_code == 200, ident
        assert r.json()["user"]["username"] == "abebe_k"


def test_role_cannot_be_chosen_at_registration(client, grades, db):
    r = _reg(client, full_name="Sneaky User", username="sneaky", phone="0922222222", role="admin", is_admin=True, is_owner=True)
    assert r.status_code == 201 and r.json()["user"]["role"] == "student" and r.json()["user"]["is_owner"] is False
    assert client.get("/admin/dashboard", headers=_h(r.json()["access_token"])).status_code == 403
    assert db.query(User).filter(User.role == Role.admin).count() == 0


def test_login_errors_do_not_reveal_which_part_was_wrong(client, grades):
    register(client)
    bad = client.post("/auth/login", json={"identifier": "0912345678", "password": "wrong-pass1"})
    unknown = client.post("/auth/login", json={"identifier": "nobody_here", "password": "wrong-pass1"})
    assert bad.status_code == unknown.status_code == 401
    assert bad.json() == unknown.json()
    body = client.post("/auth/login", json={"identifier": "0912345678", "password": STUDENT_PW}).json()
    assert "password" not in str(body["user"]).lower().replace("must_change_password", "")
    assert client.post("/auth/login", json={"identifier": "Abebe Kebede", "password": STUDENT_PW}).status_code == 401   # full name no longer signs in


def test_one_login_for_everyone_and_role_is_returned(client, grades, admin):
    from tests.conftest import ADMIN_PW
    a = client.post("/auth/login", json={"identifier": "siteadmin", "password": ADMIN_PW})
    assert a.status_code == 200 and a.json()["user"]["role"] == "admin" and a.json()["user"]["is_owner"] is True
    assert client.get("/admin/dashboard", headers=_h(a.json()["access_token"])).status_code == 200
    register(client)
    s = client.post("/auth/login", json={"identifier": "0912345678", "password": STUDENT_PW}).json()
    assert s["user"]["role"] == "student"
    assert client.get("/admin/dashboard", headers=_h(s["access_token"])).status_code == 403
    # the dedicated admin endpoint (used by the web panel) still refuses students
    assert client.post("/admin/auth/login", json={"identifier": "0912345678", "password": STUDENT_PW}).status_code == 401


def test_refresh_rotation_and_reuse_detection(client, student):
    t1 = student["tokens"]
    r = client.post("/auth/refresh", json={"refresh_token": t1["refresh_token"]})
    assert r.status_code == 200
    t2 = r.json()
    assert t2["refresh_token"] != t1["refresh_token"]
    # replaying the old (rotated) token is treated as theft: the whole family is revoked
    assert client.post("/auth/refresh", json={"refresh_token": t1["refresh_token"]}).status_code == 401
    assert client.post("/auth/refresh", json={"refresh_token": t2["refresh_token"]}).status_code == 401


def test_logout_revokes_refresh_token(client, student):
    rt = student["tokens"]["refresh_token"]
    assert client.post("/auth/logout", json={"refresh_token": rt}).status_code == 204
    assert client.post("/auth/refresh", json={"refresh_token": rt}).status_code == 401
    assert client.post("/auth/logout", json={"refresh_token": rt}).status_code == 204      # idempotent


def test_change_password(client, student):
    h = student["h"]
    assert client.post("/auth/change-password", json={"current_password": "nope12345", "new_password": "NewPass123"}, headers=h).status_code == 400
    assert client.post("/auth/change-password", json={"current_password": STUDENT_PW, "new_password": "short"}, headers=h).status_code == 422
    r = client.post("/auth/change-password", json={"current_password": STUDENT_PW, "new_password": "NewPass123"}, headers=h)
    assert r.status_code == 200
    assert client.post("/auth/refresh", json={"refresh_token": student["tokens"]["refresh_token"]}).status_code == 401   # other devices signed out
    assert client.post("/auth/login", json={"identifier": "0912345678", "password": STUDENT_PW}).status_code == 401
    assert client.post("/auth/login", json={"identifier": "0912345678", "password": "NewPass123"}).status_code == 200


def test_tokens_expired_forged_and_role_claim_ignored(client, student, db):
    from app.config import get_settings
    secret = get_settings().jwt_secret
    uid = student["id"]
    expired = jwt.encode({"sub": str(uid), "role": "student", "typ": "access", "exp": datetime.now(timezone.utc) - timedelta(seconds=5)}, secret, algorithm="HS256")
    r = client.get("/me", headers=_h(expired))
    assert r.status_code == 401 and r.json()["error"]["code"] == "token_expired"
    forged = jwt.encode({"sub": str(uid), "role": "admin", "typ": "access", "exp": datetime.now(timezone.utc) + timedelta(minutes=5)}, "another-secret-another-secret-123456", algorithm="HS256")
    assert client.get("/me", headers=_h(forged)).status_code == 401
    # even a correctly signed token that CLAIMS admin does not make the student an admin: role comes from the database
    claims_admin = jwt.encode({"sub": str(uid), "role": "admin", "typ": "access", "exp": datetime.now(timezone.utc) + timedelta(minutes=5)}, secret, algorithm="HS256")
    assert client.get("/me", headers=_h(claims_admin)).status_code == 200
    assert client.get("/admin/dashboard", headers=_h(claims_admin)).status_code == 403
    none_alg = jwt.encode({"sub": str(uid), "typ": "access", "exp": datetime.now(timezone.utc) + timedelta(minutes=5)}, None, algorithm="none")
    assert client.get("/me", headers=_h(none_alg)).status_code == 401
    refresh_as_access = student["tokens"]["refresh_token"]
    assert client.get("/me", headers=_h(refresh_as_access)).status_code == 401


def test_login_rate_limit(client, grades):
    register(client)
    codes = [client.post("/auth/login", json={"identifier": "0912345678", "password": f"wrongpass{i}1"}).status_code for i in range(10)]
    assert codes[:8] == [401] * 8 and 429 in codes[8:]
    # a correct password is also blocked while the limiter is active (prevents guessing around the limit)
    assert client.post("/auth/login", json={"identifier": "0912345678", "password": STUDENT_PW}).status_code == 429


def test_unauthenticated_and_error_shape(client):
    r = client.get("/me")
    assert r.status_code == 401 and set(r.json()["error"]) >= {"code", "message"}
    r = client.get("/does-not-exist")
    assert r.status_code == 404 and r.json()["error"]["code"] == "not_found"


def test_profile_grade_and_account_deletion(client, student):
    h = student["h"]
    assert client.patch("/me", json={"selected_grade": 99}, headers=h).status_code == 422
    assert client.patch("/me", json={"selected_grade": 11}, headers=h).json()["selected_grade"] == 11
    assert client.patch("/me", json={"full_name": "Abebe K. Bekele"}, headers=h).json()["full_name"] == "Abebe K. Bekele"
    assert client.request("DELETE", "/me", json={"password": "wrong-pass1"}, headers=h).status_code == 400
    assert client.request("DELETE", "/me", json={"password": STUDENT_PW}, headers=h).status_code == 204
    assert client.get("/me", headers=h).status_code == 401
    assert client.post("/auth/login", json={"identifier": "0912345678", "password": STUDENT_PW}).status_code == 401
