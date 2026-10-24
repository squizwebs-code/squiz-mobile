"""Command line tools.

  python -m app.cli create-admin            first administrator (reads ADMIN_* env vars, prompts for anything missing)
  python -m app.cli seed-grades             creates Grades 9-12 if missing
  python -m app.cli import-bank [--file data/question_bank.json] [--draft]
                                            migrates the original SQUIZ question bank (idempotent)
"""
import argparse
import getpass
import json
import os
import sys

from sqlalchemy import func, select

from .db import session_factory
from .models import (AnswerOption, Grade, GradeSubject, PublishStatus, Question, Role, Subject, Unit, User)
from .phone import PhoneError, name_key, normalize_phone, normalize_username
from .routers.admin_questions import qkey
from .security import hash_password, password_problem


# Ethiopian Matric streams. Subjects not listed here are open to both streams.
SUBJECT_TRACK = {"physics": "natural", "chemistry": "natural", "biology": "natural", "geography": "social", "history": "social", "economics": "social"}


def _db():
    return session_factory()()


def create_admin(args) -> int:
    name = os.environ.get("ADMIN_FULL_NAME") or input("Administrator full name: ").strip()
    phone_raw = os.environ.get("ADMIN_PHONE") or input("Administrator phone number: ").strip()
    uname_raw = os.environ.get("ADMIN_USERNAME") or input("Administrator username: ").strip()
    pw = os.environ.get("ADMIN_PASSWORD")
    if not pw:
        pw = getpass.getpass("Password: ")
        if pw != getpass.getpass("Repeat password: "):
            print("Passwords do not match.", file=sys.stderr)
            return 1
    try:
        phone = normalize_phone(phone_raw)
    except PhoneError as e:
        print(f"Invalid phone number: {e}", file=sys.stderr)
        return 1
    try:
        username = normalize_username(uname_raw)
    except ValueError as e:
        print(f"Invalid username: {e}", file=sys.stderr)
        return 1
    problem = password_problem(pw)
    if problem or len(pw) < 10:
        print(f"Weak password: {problem or 'administrator passwords must have at least 10 characters'}", file=sys.stderr)
        return 1
    if len(" ".join(name.split())) < 2:
        print("Full name is required.", file=sys.stderr)
        return 1
    db = _db()
    if db.scalar(select(User.id).where(User.phone == phone)):
        print("A user with this phone number already exists. Nothing was changed.", file=sys.stderr)
        return 1
    if db.scalar(select(User.id).where(User.username == username)):
        print("That username is already taken. Nothing was changed.", file=sys.stderr)
        return 1
    owner = db.scalar(select(User).where(User.is_owner.is_(True)))
    # The first administrator created here is the owner. Later ones created here are promoted by the owner.
    db.add(User(full_name=" ".join(name.split()), username=username, name_key=name_key(name), phone=phone, password_hash=hash_password(pw),
                role=Role.admin, is_owner=owner is None, promoted_by_id=owner.id if owner else None))
    db.commit()
    print(f"{'Owner' if owner is None else 'Administrator'} account created for {phone} (username: {username}).")
    return 0


def seed_grades(args=None) -> int:
    db = _db()
    n = 0
    for g in (9, 10, 11, 12):
        if not db.scalar(select(Grade.id).where(Grade.number == g)):
            db.add(Grade(number=g, name=f"Grade {g}", published=True))
            n += 1
    db.commit()
    print(f"Grades ready ({n} created).")
    return 0


def import_bank(args) -> int:
    seed_grades()
    path = args.file
    with open(path, encoding="utf-8") as f:
        bank = json.load(f)
    db = _db()
    status = PublishStatus.draft if args.draft else PublishStatus.published
    grades = {g.number: g for g in db.scalars(select(Grade))}
    names = {s["id"]: s["name"] for s in bank["subjects"]}
    subjects = {s.key: s for s in db.scalars(select(Subject))}
    created = {"subjects": 0, "units": 0, "questions": 0, "skipped_existing": 0, "skipped_invalid": 0}
    invalid: list[str] = []
    for u in bank["units"]:
        targets = [u["grade"]] if u["grade"] else [9, 10, 11, 12]      # "all grades" quick checks are attached to every grade
        sub = subjects.get(u["subject"])
        if sub is None:
            sub = Subject(key=u["subject"], name=names.get(u["subject"], u["subject"].title()), icon=u["subject"], published=True,
                          track=SUBJECT_TRACK.get(u["subject"], "all"))
            db.add(sub)
            db.flush()
            subjects[sub.key] = sub
            created["subjects"] += 1
        for gn in targets:
            g = grades[gn]
            if db.get(GradeSubject, (g.id, sub.id)) is None:
                db.add(GradeSubject(grade_id=g.id, subject_id=sub.id, published=True))
            title = u["title"] if u["kind"] != "quick" else "Quick check"
            unit = db.scalar(select(Unit).where(Unit.grade_id == g.id, Unit.subject_id == sub.id, Unit.title == title))
            if unit is None:
                pos = {"unit": 0, "extra": 100, "quick": 200}[u["kind"]] + (u["no"] % 100)
                unit = Unit(grade_id=g.id, subject_id=sub.id, title=title, kind=u["kind"], position=pos, published=True)
                db.add(unit)
                db.flush()
                created["units"] += 1
            for q in u["qs"]:
                if q.get("bad") or q["a"] < 0 or len(q["o"]) < 2:
                    created["skipped_invalid"] += 1
                    invalid.append(f'{u["source"]}: {q["q"][:70]}')
                    continue
                key = qkey(q["q"])
                if db.scalar(select(Question.id).where(Question.unit_id == unit.id, Question.text_key == key)):
                    created["skipped_existing"] += 1
                    continue
                row = Question(unit_id=unit.id, text=q["q"], text_key=key, explanation=q.get("e"), status=status, source_ref=u["source"])
                row.options = [AnswerOption(text=t, is_correct=(i == q["a"]), position=i) for i, t in enumerate(q["o"])]
                db.add(row)
                created["questions"] += 1
        db.commit()
    print(json.dumps(created))
    if invalid:
        print("Skipped (the source answer matched no option; fix them in the admin panel):", *sorted(set(invalid)), sep="\n  ")
    return 0


def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog="python -m app.cli")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("create-admin").set_defaults(fn=create_admin)
    sub.add_parser("seed-grades").set_defaults(fn=seed_grades)
    ib = sub.add_parser("import-bank")
    ib.add_argument("--file", default=os.path.join(os.path.dirname(__file__), "..", "data", "question_bank.json"))
    ib.add_argument("--draft", action="store_true", help="import as drafts instead of publishing")
    ib.set_defaults(fn=import_bank)
    args = p.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
