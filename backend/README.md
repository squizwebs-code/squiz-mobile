# SQUIZ backend

See the top-level README for setup. Layout:

```
app/main.py          app factory (CORS, security headers, error format, static /media and /admin-ui)
app/routers/         auth, content (student), quiz, student (profile/bookmarks/stats), admin, admin_questions
app/models.py        SQLAlchemy models        alembic/versions/   migrations
app/cli.py           create-admin | seed-grades | import-bank
app/admin_ui/        admin web dashboard (vanilla JS, no inline scripts)
tests/               pytest suite against real PostgreSQL     tests_ui/  browser smoke test (Playwright)
```

Error format everywhere: `{"error": {"code": "...", "message": "...", "details": ...}}`.
Interactive API docs at `/docs`.

## App sync endpoints (`/app/*`) — used by the Flutter app v2

All require a student/admin bearer token. Tested in `tests/test_app_sync.py` (12 tests).

| Method | Path | What it does |
|---|---|---|
| GET | `/app/bank` | Published question bank in the app's JSON shape (drafts are never included). Sends an `ETag`; `If-None-Match` returns 304. Each question carries a content key `k = sha256(normalised text)`. |
| GET | `/app/state` | The signed-in user's synced learning state (bookmarks, flags, last answers, history). |
| PUT | `/app/state` | Merges the app's state into the server copy and returns the merged result. Last-write-wins per key, history is a union by id (newest 200), timestamps are clamped to now+5 min, body limit 2 MB, invalid entries are rejected with `422 bad_state`. |
| DELETE | `/app/state` | "Reset progress": clears answers and history, keeps bookmarks and flags. |

Migration `0002_app_state` adds the `app_states` table (`alembic upgrade head`).
Note: the correct answer index is part of `/app/bank` because the app grades quizzes on the phone so it works offline. A determined student can read it from the downloaded bank.


## v3: admin, roles, tracks, import, statistics

Migration `0003_v3_admin_tracks_username` (run `alembic upgrade head`) adds usernames, roles/owner/promotion chain, suspension fields, `archived_at`, subject `track`/`position`, and the tables `import_batches`, `announcements`, `question_reports`.

- **Login:** `POST /auth/login {identifier, password}` — identifier is a username or phone number. Password: 6+ characters. Registration always creates a student. `GET /auth/username-available`, `POST /auth/logout-all`.
- **First admin (owner):** `ADMIN_USERNAME=… ADMIN_PHONE=… ADMIN_PASSWORD=… ADMIN_NAME=… python -m app.cli create-admin` (password 10+ characters). There is no public API to create an admin.
- **Users** `/admin/users…`: list/filter, detail with progress and promotion chain, `role`, `suspend` (reason, optional days, sessions revoked at once), `activate`, `reset-password` (temporary password returned once), `force-password-change`, `logout-everywhere`, `DELETE ?confirm=true`. Every response carries `can_manage` and `cannot_manage_reason`; the same rule is enforced on the server.
- **Content** `/admin/grades|subjects|units|questions…`: create/patch, publish/hide, archive (DELETE) and `/restore`, `/reorder`, subject `track`; questions have `publish|unpublish|archive`.
- **Import** `/admin/questions/import/{template,validate,commit,history,{id}/undo}` and `/admin/questions/export?format=xlsx|csv|json`. Commit re-validates, imports as drafts unless `publish=true`, policy `skip|update|add`, one transaction, undoable batch. Images must be `/media/…` paths.
- **Statistics** `GET /admin/stats?from=&to=` and `/admin/stats/export` (xlsx). Computed from the `app_states` documents plus the database.
- **Also:** `/admin/announcements`, `/admin/reports`, `/admin/audit`, `/admin/settings`, `/admin/uploads`; students get `/app/announcements` and `POST /app/reports`.
- The legacy web dashboard in `app/admin_ui/` still works (same brand colours now). `tests_ui/admin_ui_smoke.py` was **not re-run** after v3: its last step expects delete, which is archive now.
- Tests: `pytest` → 70 passed against real PostgreSQL.
