"""Quiz building and authoritative grading helpers (pure functions where possible)."""
import random
import re

from .models import Question

# Options that refer to each other ("All of the above", "Both A and B") must keep their order.
_ORDER_RE = re.compile(r"\b(above|below|both|neither|none of|all of|a and b|b and c|a and c|a & b)\b", re.I)


def order_sensitive(option_texts: list[str]) -> bool:
    return any(_ORDER_RE.search(t) for t in option_texts)


def snapshot_question(q: Question) -> dict:
    return {"text": q.text, "explanation": q.explanation, "image_url": q.image_url, "version": q.version,
            "options": [{"id": o.id, "text": o.text, "is_correct": o.is_correct} for o in q.options]}


def option_order(snap: dict, shuffle: bool, rng: random.Random | None = None) -> list[int]:
    ids = [o["id"] for o in snap["options"]]
    if shuffle and not order_sensitive([o["text"] for o in snap["options"]]):
        (rng or random).shuffle(ids)
    return ids


def correct_option_id(snap: dict) -> int | None:
    for o in snap["options"]:
        if o["is_correct"]:
            return o["id"]
    return None


def is_correct(snap: dict, selected_option_id: int | None) -> bool | None:
    if selected_option_id is None:
        return None
    return selected_option_id == correct_option_id(snap)


def valid_option(snap: dict, option_id: int) -> bool:
    return any(o["id"] == option_id for o in snap["options"])


def tally(correct_flags: list[bool | None]) -> dict:
    total = len(correct_flags)
    correct = sum(1 for c in correct_flags if c is True)
    wrong = sum(1 for c in correct_flags if c is False)
    skipped = total - correct - wrong
    pct = round(correct * 100 / total) if total else 0
    return {"total": total, "correct": correct, "wrong": wrong, "skipped": skipped, "percentage": pct}
