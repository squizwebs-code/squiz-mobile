from datetime import datetime, timedelta, timezone

import jwt

from app.models import Role, User
from tests.conftest import STUDENT_PW, _h, register


def test_phone_normalisation_and_duplicates(client, grades):
    t = register(client, phone="0912 345 678")
    assert t["user"]["phone"] == "+251912345678"
    for variant in ("+251912345678", "251912345678", "912345678", "09-12-345-678", "00251912345678"):
        r = client.post("/auth/register", json={"full_name": "Other Person", "phone": variant, "password": STUDENT_PW, "confirm_password": STUDENT_PW})
        assert r.status_code == 409 and r.json()["error"]["code"] == "phone_taken", variant


def test_register_validation_messages(client, grades):
    def go(**kw):
        body = {"full_name": "Abebe Kebede", "phone": "0912345678", "password": STUDENT_PW, "confirm_password": STUDENT_PW, **kw}
        return client.post("/auth/register", json=body)
    assert "at least 8" in go(password="Ab1", confirm_password="Ab1").json()["error"]["message"]
    assert "letter and one number" in go(password="abcdefgh", confirm_password="abcdefgh").json()["error"]["message"]
    assert "do not match" in go(confirm_password="Different123").json()["error"]["message"]
    assert go(phone="12345").status_code == 422
    assert go(phone="abc").status_code == 422
    assert go(full_name="   ").status_code == 422
    assert go(full_name="A").status_code == 422
    assert go().status_code == 201


def test_role_cannot_be_chosen_at_registration(client, grades, db):
    r = client.post("/auth/register", json={"full_name": "Sneaky User", "phone": "0922222222", "password": STUDENT_PW, "confirm_password": STUDENT_PW,
                                            "role": "admin", "is_admin": True})
    assert r.status_code == 201 and r.json()["user"]["role"] == "student"
    assert client.get("/admin/dashboard", headers=_h(r.json()["access_token"])).status_code == 403
    assert db.query(User).filter(User.role == Role.admin).count() == 0


def test_login_by_phone_and_name_and_errors(client, grades):
    register(client)
    assert client.post("/auth/login", json={"identifier": "0912345678", "password": STUDENT_PW}).status_code == 200
    assert client.post("/auth/login", json={"identifier": "+251 912 345 678", "password": STUDENT_PW}).status_code == 200
    assert client.post("/auth/login", json={"identifier": "  abebe   KEBEDE ", "password": STUDENT_PW}).status_code == 200
    bad = client.post("/auth/login", json={"identifier": "0912345678", "password": "wrong-pass1"})
    unknown = client.post("/auth/login", json={"identifier": "0999999999", "password": "wrong-pass1"})
    assert bad.status_code == unknown.status_code == 401
    assert bad.json() == unknown.json()                      # no account enumeration
    body = client.post("/auth/login", json={"identifier": "0912345678", "password": STUDENT_PW}).json()
    assert "password" not in str(body["user"]).lower().replace("must_change_password", "")


def test_duplicate_full_name_requires_phone(client, grades):
    register(client, name="Abebe Kebede", phone="0911111111")
    register(client, name="abebe kebede", phone="0922222222")
    r = client.post("/auth/login", json={"identifier": "Abebe Kebede", "password": STUDENT_PW})
    assert r.status_code == 409 and r.json()["error"]["code"] == "ambiguous_name"
    assert client.post("/auth/login", json={"identifier": "0911111111", "password": STUDENT_PW}).status_code == 200


def test_admin_cannot_use_student_login_and_vice_versa(client, grades, admin):
    from tests.conftest import ADMIN_PW
    assert client.post("/auth/login", json={"identifier": "0911000000", "password": ADMIN_PW}).status_code == 401
    register(client)
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
