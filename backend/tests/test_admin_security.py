from tests.conftest import _h, make_content, register


ADMIN_GETS = ["/admin/dashboard", "/admin/grades", "/admin/subjects", "/admin/students", "/admin/audit", "/admin/settings",
              "/admin/questions", "/admin/analytics", "/admin/activity"]


def test_every_admin_route_rejects_anonymous_and_students(client, student):
    for path in ADMIN_GETS:
        assert client.get(path).status_code == 401, path
        assert client.get(path, headers=student["h"]).status_code == 403, path
    # write endpoints too
    for method, path in [("POST", "/admin/subjects"), ("POST", "/admin/questions"), ("POST", "/admin/units"), ("POST", "/admin/questions/import/commit")]:
        assert client.request(method, path, json={}, headers=student["h"]).status_code == 403, path


def test_no_public_admin_creation_route(client):
    from app.main import app
    for r in app.routes:
        p = getattr(r, "path", "")
        if "admin" in p and "create" in p and "admin/auth" not in p:
            raise AssertionError(p)
    assert client.post("/admin/users", json={"full_name": "X Y", "phone": "0933333333", "password": "Passw0rdxx", "role": "admin"}).status_code in (401, 404, 405)


def test_admin_creates_content_and_students_only_see_published(client, admin_h, student):
    pub = make_content(client, admin_h, publish=True, n=3, title="Published unit")
    draft = make_content(client, admin_h, publish=False, n=2, title="Draft unit", subject_key="math")
    sh = student["h"]
    units = client.get(f"/grades/11/subjects/{pub['subject_id']}/units", headers=sh).json()
    titles = {u["title"]: u["question_count"] for u in units}
    assert titles["Published unit"] == 3
    assert titles.get("Draft unit", 0) == 0                      # unit with only drafts has no visible questions
    qs = client.get("/questions", params={"unit_id": draft["unit_id"]}, headers=sh)
    assert qs.status_code == 200 and qs.json()["total"] == 0
    # student payload never leaks the answer key
    got = client.get("/questions", params={"unit_id": pub["unit_id"]}, headers=sh).json()
    text = str(got)
    assert "is_correct" not in text and "explanation" not in text
    # student cannot start a session on drafts
    r = client.post("/sessions", json={"mode": "practice", "unit_id": draft["unit_id"]}, headers=sh)
    assert r.status_code in (404, 409, 422)


def test_publish_unpublish_archive_delete_flow_and_audit(client, admin_h, student):
    c = make_content(client, admin_h, publish=False, n=1)
    qid = c["qids"][0]
    sh = student["h"]
    assert client.post(f"/admin/questions/{qid}/publish", headers=admin_h).status_code == 200
    assert client.get("/questions", params={"unit_id": c["unit_id"]}, headers=sh).json()["total"] == 1
    assert client.post(f"/admin/questions/{qid}/unpublish", headers=admin_h).status_code == 200
    assert client.get("/questions", params={"unit_id": c["unit_id"]}, headers=sh).json()["total"] == 0
    assert client.post(f"/admin/questions/{qid}/archive", headers=admin_h).status_code == 200
    assert client.delete(f"/admin/questions/{qid}", headers=admin_h).status_code in (400, 422)       # needs confirm
    assert client.delete(f"/admin/questions/{qid}", params={"confirm": "true"}, headers=admin_h).status_code in (200, 204)
    audit = client.get("/admin/audit", headers=admin_h).json()
    actions = " ".join(str(a) for a in (audit["items"] if isinstance(audit, dict) else audit))
    for word in ("publish", "unpublish", "archive", "delete"):
        assert word in actions


def test_question_validation(client, admin_h, grades):
    c = make_content(client, admin_h, n=1)
    base = {"unit_id": c["unit_id"], "text": "Which is right?", "options": [{"text": "A", "is_correct": True}, {"text": "B"}]}
    assert client.post("/admin/questions", json=base, headers=admin_h).status_code == 201
    two = {**base, "options": [{"text": "A", "is_correct": True}, {"text": "B", "is_correct": True}]}
    assert client.post("/admin/questions", json=two, headers=admin_h).status_code == 422
    none = {**base, "options": [{"text": "A"}, {"text": "B"}]}
    assert client.post("/admin/questions", json=none, headers=admin_h).status_code == 422
    dup = {**base, "options": [{"text": "A", "is_correct": True}, {"text": "a"}]}
    assert client.post("/admin/questions", json=dup, headers=admin_h).status_code == 422


def test_student_management_deactivate_and_reset_password(client, admin_h, student):
    sid = student["id"]
    r = client.get("/admin/students", params={"q": "Abebe"}, headers=admin_h).json()
    items = r["items"] if isinstance(r, dict) else r
    assert any(s["id"] == sid for s in items)
    assert "password" not in str(items).lower().replace("must_change_password", "")
    # reset gives a one-time temporary password; student is forced to change it
    rr = client.post(f"/admin/students/{sid}/reset-password", headers=admin_h)
    assert rr.status_code == 200
    temp = rr.json()["temporary_password"]
    assert client.post("/auth/login", json={"identifier": "0912345678", "password": "Student123"}).status_code == 401
    lg = client.post("/auth/login", json={"identifier": "0912345678", "password": temp})
    assert lg.status_code == 200 and lg.json()["user"]["must_change_password"] is True
    th = _h(lg.json()["access_token"])
    blocked = client.get("/grades/11/subjects", headers=th)
    assert blocked.status_code == 403 and blocked.json()["error"]["code"] == "password_change_required"
    ok = client.post("/auth/change-password", json={"current_password": temp, "new_password": "BrandNew123"}, headers=th)
    assert ok.status_code == 200
    th2 = _h(client.post("/auth/login", json={"identifier": "0912345678", "password": "BrandNew123"}).json()["access_token"])
    assert client.get("/grades/11/subjects", headers=th2).status_code == 200
    # deactivate: existing tokens stop working and login is refused
    assert client.patch(f"/admin/students/{sid}/status", json={"status": "inactive"}, headers=admin_h).status_code == 200
    assert client.get("/me", headers=th2).status_code in (401, 403)
    assert client.post("/auth/login", json={"identifier": "0912345678", "password": "BrandNew123"}).status_code in (401, 403)


def test_import_validate_commit_duplicates_and_export_roundtrip(client, admin_h):
    c = make_content(client, admin_h, n=1, title="Imp unit")
    csv = ("grade,subject,unit,question,option_a,option_b,option_c,option_d,answer,explanation\n"
           "11,Mathematics,Imp unit,What is 9 x 9?,81,72,18,99,A,Nine nines\n"
           "11,Mathematics,Imp unit,Bad row without answer,1,2,3,4,,\n"
           "11,Mathematics,Imp unit,What is 9 x 9?,81,72,18,99,A,duplicate in file\n")
    files = {"file": ("q.csv", csv.encode(), "text/csv")}
    v = client.post("/admin/questions/import/validate", files=files, headers=admin_h)
    assert v.status_code == 200, v.text
    body = v.json()
    assert body["summary"]["ok"] == 1 and body["summary"]["errors"] == 1 and body["summary"]["duplicates"] == 1
    cm = client.post("/admin/questions/import/commit", files={"file": ("q.csv", csv.encode(), "text/csv")}, data={"create_missing": "true"}, headers=admin_h)
    assert cm.status_code == 200, cm.text
    assert cm.json()["created"]["questions"] == 1
    again = client.post("/admin/questions/import/commit", files={"file": ("q.csv", csv.encode(), "text/csv")}, data={"create_missing": "true"}, headers=admin_h)
    assert again.json()["created"]["questions"] == 0                           # duplicates are not re-created
    ex = client.get("/admin/questions/export", params={"format": "json"}, headers=admin_h)
    assert ex.status_code == 200 and "9 x 9" in ex.text


def test_csv_export_neutralises_formulas(client, admin_h):
    c = make_content(client, admin_h, n=0)
    r = client.post("/admin/questions", headers=admin_h, json={"unit_id": c["unit_id"], "text": "=HYPERLINK(\"http://x\",\"y\") what", "status": "published",
                                                              "options": [{"text": "+1", "is_correct": True}, {"text": "-2"}]})
    assert r.status_code == 201
    ex = client.get("/admin/questions/export", params={"format": "csv"}, headers=admin_h).text
    assert "'=HYPERLINK" in ex and "'+1" in ex


def test_upload_rejects_non_images(client, admin_h):
    bad = client.post("/admin/uploads", files={"file": ("x.png", b"<script>alert(1)</script>", "image/png")}, headers=admin_h)
    assert bad.status_code in (400, 415, 422)
    png = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64
    ok = client.post("/admin/uploads", files={"file": ("../../evil.png", png, "image/png")}, headers=admin_h)
    assert ok.status_code in (200, 201), ok.text
    assert ".." not in str(ok.json())
