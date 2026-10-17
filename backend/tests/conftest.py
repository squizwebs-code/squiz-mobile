"""Tests run against a REAL PostgreSQL database (default: local test instance). Set TEST_DATABASE_URL to override."""
import os

os.environ.setdefault("ENV", "test")
os.environ["DATABASE_URL"] = os.environ.get("TEST_DATABASE_URL", "postgresql+psycopg2://postgres@127.0.0.1:5433/squiz_test")
os.environ["JWT_SECRET"] = "test-secret-test-secret-test-secret-1234567890"
os.environ["UPLOAD_DIR"] = "/tmp/squiz-test-uploads"
os.environ["RATE_LIMIT_ENABLED"] = "true"

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import text  # noqa: E402

from app import ratelimit  # noqa: E402
from app.db import Base, engine, session_factory  # noqa: E402
from app.main import app  # noqa: E402
from app.models import Grade, Role, User  # noqa: E402
from app.phone import name_key, normalize_phone  # noqa: E402
from app.security import hash_password  # noqa: E402

ADMIN_PW = "Adm1n-Passw0rd!"
STUDENT_PW = "Student123"


@pytest.fixture(scope="session", autouse=True)
def _schema():
    e = engine()
    Base.metadata.drop_all(e)
    Base.metadata.create_all(e)
    yield


@pytest.fixture(autouse=True)
def _clean():
    ratelimit.reset()
    with engine().begin() as c:
        c.execute(text("TRUNCATE users, grades, subjects, app_settings, audit_logs RESTART IDENTITY CASCADE"))
    yield


@pytest.fixture
def client():
    with TestClient(app, raise_server_exceptions=False) as c:
        yield c


@pytest.fixture
def db():
    s = session_factory()()
    yield s
    s.close()


@pytest.fixture
def grades(db):
    for n in (9, 10, 11, 12):
        db.add(Grade(number=n, name=f"Grade {n}", published=True))
    db.commit()


@pytest.fixture
def admin(db):
    u = User(full_name="Site Admin", name_key=name_key("Site Admin"), phone=normalize_phone("0911000000"), password_hash=hash_password(ADMIN_PW), role=Role.admin)
    db.add(u)
    db.commit()
    return u


def _h(tok):
    return {"Authorization": f"Bearer {tok}"}


@pytest.fixture
def admin_h(client, admin, grades):
    r = client.post("/admin/auth/login", json={"identifier": "0911000000", "password": ADMIN_PW})
    assert r.status_code == 200, r.text
    return _h(r.json()["access_token"])


def register(client, name="Abebe Kebede", phone="0912345678", pw=STUDENT_PW):
    r = client.post("/auth/register", json={"full_name": name, "phone": phone, "password": pw, "confirm_password": pw})
    assert r.status_code == 201, r.text
    return r.json()


@pytest.fixture
def student(client, grades):
    t = register(client)
    return {"h": _h(t["access_token"]), "tokens": t, "id": t["user"]["id"]}


def make_content(client, admin_h, publish=True, n=4, subject_key="math", subject_name="Mathematics", grade_number=11, title="Unit 1"):
    """Creates subject -> unit -> n questions through the admin API. Returns ids."""
    gid = next(g["id"] for g in client.get("/admin/grades", headers=admin_h).json() if g["number"] == grade_number)
    s = client.post("/admin/subjects", json={"key": subject_key, "name": subject_name}, headers=admin_h)
    sid = s.json()["id"] if s.status_code == 201 else next(x["id"] for x in client.get("/admin/subjects", headers=admin_h).json() if x["key"] == subject_key)
    u = client.post("/admin/units", json={"grade_id": gid, "subject_id": sid, "title": title}, headers=admin_h)
    assert u.status_code == 201, u.text
    uid = u.json()["id"]
    qids = []
    for i in range(n):
        r = client.post("/admin/questions", headers=admin_h, json={
            "unit_id": uid, "text": f"What is {i} + {i} in {title}?", "explanation": f"Because {i}+{i}={2 * i}.",
            "status": "published" if publish else "draft",
            "options": [{"text": str(2 * i), "is_correct": True}, {"text": str(2 * i + 1)}, {"text": str(2 * i + 2)}, {"text": str(2 * i + 3)}]})
        assert r.status_code == 201, r.text
        qids.append(r.json()["id"])
    return {"grade_id": gid, "subject_id": sid, "unit_id": uid, "qids": qids}
