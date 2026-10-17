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
