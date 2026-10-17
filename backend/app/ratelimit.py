"""Small in-memory sliding-window rate limiter for auth endpoints.

Per-process only: with several workers/instances use a shared store (e.g. Redis) or a gateway limiter.
"""
import time
from collections import defaultdict, deque

from fastapi import HTTPException, Request

from .config import get_settings

_hits: dict[str, deque] = defaultdict(deque)


def reset() -> None:
    _hits.clear()


def check(key: str, limit: int, window_s: int) -> None:
    if not get_settings().rate_limit_enabled:
        return
    now = time.monotonic()
    q = _hits[key]
    while q and now - q[0] > window_s:
        q.popleft()
    if len(q) >= limit:
        raise HTTPException(429, detail={"code": "rate_limited", "message": "Too many attempts. Please wait a few minutes and try again."},
                            headers={"Retry-After": str(window_s)})
    q.append(now)


def client_ip(request: Request) -> str:
    return request.client.host if request.client else "unknown"
