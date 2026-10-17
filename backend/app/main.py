import logging
import os

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from starlette.exceptions import HTTPException as StarletteHTTPException

from .config import get_settings
from .routers import admin, admin_questions, app_sync, auth, content, quiz, student

log = logging.getLogger("squiz")
DESCRIPTION = """
SQUIZ REST API for the student mobile app and the admin dashboard.

- **Auth**: register/login with phone number (or full name), JWT access tokens (short-lived) + rotating refresh tokens.
- **Students** can only see published content; exams are graded on the server from a snapshot taken at start.
- **Admin** endpoints live under `/admin` and always re-check the administrator role in the database.
Errors always look like `{"error": {"code": "...", "message": "...", "details": [...]}}`.
"""


def create_app() -> FastAPI:
    cfg = get_settings()
    app = FastAPI(title="SQUIZ API", version="1.0.0", description=DESCRIPTION)

    if cfg.cors_origin_list:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=cfg.cors_origin_list,
            allow_credentials=False,
            allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
            allow_headers=["Authorization", "Content-Type"],
        )

    @app.middleware("http")
    async def security_headers(request: Request, call_next):
        resp = await call_next(request)
        resp.headers.setdefault("X-Content-Type-Options", "nosniff")
        resp.headers.setdefault("Referrer-Policy", "no-referrer")
        resp.headers.setdefault("X-Frame-Options", "DENY")
        if request.url.path.startswith("/admin-ui"):
            resp.headers["Content-Security-Policy"] = (
                "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; "
                "script-src 'self'; connect-src 'self'; frame-ancestors 'none'"
            )
        if request.url.path.startswith(("/auth", "/admin", "/me")):
            resp.headers["Cache-Control"] = "no-store"
        return resp

    @app.exception_handler(StarletteHTTPException)
    async def http_error(request: Request, exc: StarletteHTTPException):
        d = exc.detail
        body = (
            d
            if isinstance(d, dict) and "code" in d
            else {
                "code": {
                    404: "not_found",
                    405: "method_not_allowed",
                }.get(exc.status_code, "http_error"),
                "message": d if isinstance(d, str) else "Request failed",
            }
        )
        return JSONResponse(
            {"error": body},
            status_code=exc.status_code,
            headers=getattr(exc, "headers", None),
        )

    @app.exception_handler(RequestValidationError)
    async def validation_error(request: Request, exc: RequestValidationError):
        details = []
        for e in exc.errors():
            loc = [
                str(x)
                for x in e.get("loc", [])
                if x not in ("body", "query", "path")
            ]
            details.append(
                {
                    "field": ".".join(loc),
                    "message": str(e.get("msg", "")).removeprefix(
                        "Value error, "
                    ),
                }
            )
        first = details[0]["message"] if details else "Invalid request"
        return JSONResponse(
            {
                "error": {
                    "code": "validation_error",
                    "message": first,
                    "details": details,
                }
            },
            status_code=422,
        )

    @app.exception_handler(Exception)
    async def unhandled(request: Request, exc: Exception):
        log.exception(
            "Unhandled error on %s %s", request.method, request.url.path
        )  # details stay in server logs only
        return JSONResponse(
            {
                "error": {
                    "code": "internal_error",
                    "message": (
                        "Something went wrong on our side. Please try again."
                    ),
                }
            },
            status_code=500,
        )

    @app.get("/health", tags=["meta"])
    @app.head("/health", tags=["meta"])
    def health():
        return {"status": "ok"}

    @app.on_event("startup")
    def on_startup():
        try:
            from .db import Base, engine
            actual_engine = engine() if callable(engine) else engine
            Base.metadata.create_all(bind=actual_engine)
            log.info("Database tables verified/created successfully on startup.")
        except Exception as e:
            log.exception("Failed to create database tables on startup: %s", e)

    for r in (
        auth.router,
        content.router,
        quiz.router,
        student.router,
        app_sync.router,
        admin.router,
        admin_questions.router,
    ):
        app.include_router(r)

    os.makedirs(cfg.upload_dir, exist_ok=True)
    app.mount("/media", StaticFiles(directory=cfg.upload_dir), name="media")
    ui = os.path.join(os.path.dirname(__file__), "admin_ui")
    if os.path.isdir(ui):
        app.mount("/admin-ui", StaticFiles(directory=ui, html=True), name="admin-ui")
    return app


app = create_app()