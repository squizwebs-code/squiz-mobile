"""usernames, owner/promotion chain, suspension details, Matric tracks, archiving, import batches, announcements, reports

Revision ID: 0003
Revises: 0002
"""
import re

import sqlalchemy as sa
from alembic import op

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None

NATURAL = ("physics", "chemistry", "biology")
SOCIAL = ("geography", "history", "economics")


def upgrade() -> None:
    ts = sa.DateTime(timezone=True)
    # ---- users
    op.add_column("users", sa.Column("selected_track", sa.String(10), nullable=True))
    op.add_column("users", sa.Column("username", sa.String(30), nullable=True))
    op.add_column("users", sa.Column("is_owner", sa.Boolean(), nullable=False, server_default=sa.false()))
    op.add_column("users", sa.Column("promoted_by_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True))
    op.add_column("users", sa.Column("suspended_reason", sa.String(200), nullable=True))
    op.add_column("users", sa.Column("suspended_at", ts, nullable=True))
    op.add_column("users", sa.Column("suspended_until", ts, nullable=True))
    op.add_column("users", sa.Column("suspended_by_id", sa.Integer(), nullable=True))

    bind = op.get_bind()
    users = bind.execute(sa.text("SELECT id, name_key FROM users ORDER BY id")).all()
    taken: set[str] = set()
    for uid, name_key in users:        # existing accounts get a readable, unique username they can see in their profile
        base = re.sub(r"[^a-z0-9]+", "_", (name_key or "").lower()).strip("_")[:22] or "user"
        if len(base) < 3:
            base = f"user_{base}"
        cand = base
        if cand in taken:
            cand = f"{base[:22]}_{uid}"
        taken.add(cand)
        bind.execute(sa.text("UPDATE users SET username = :u WHERE id = :i"), {"u": cand, "i": uid})
    op.alter_column("users", "username", nullable=False)
    op.create_unique_constraint("uq_users_username", "users", ["username"])

    owner = bind.execute(sa.text("SELECT id FROM users WHERE role = 'admin' ORDER BY id LIMIT 1")).scalar()
    if owner:
        bind.execute(sa.text("UPDATE users SET is_owner = true WHERE id = :o"), {"o": owner})
        bind.execute(sa.text("UPDATE users SET promoted_by_id = :o WHERE role = 'admin' AND id <> :o"), {"o": owner})

    # ---- content: archiving, tracks, ordering
    for t in ("grades", "subjects", "units"):
        op.add_column(t, sa.Column("archived_at", ts, nullable=True))
    op.add_column("subjects", sa.Column("track", sa.String(10), nullable=False, server_default="all"))
    op.add_column("subjects", sa.Column("position", sa.Integer(), nullable=False, server_default="0"))
    for key in NATURAL:
        bind.execute(sa.text("UPDATE subjects SET track = 'natural' WHERE key = :k"), {"k": key})
    for key in SOCIAL:
        bind.execute(sa.text("UPDATE subjects SET track = 'social' WHERE key = :k"), {"k": key})

    # ---- new tables
    op.create_table(
        "import_batches",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("admin_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("admin_name", sa.String(120), nullable=True),
        sa.Column("filename", sa.String(200), nullable=False),
        sa.Column("policy", sa.String(10), nullable=False),
        sa.Column("status", sa.String(12), nullable=False),
        sa.Column("counts", sa.JSON(), nullable=False),
        sa.Column("items", sa.JSON(), nullable=False),
        sa.Column("created_at", ts, nullable=False),
        sa.Column("undone_at", ts, nullable=True),
    )
    op.create_index("ix_import_batches_created_at", "import_batches", ["created_at"])
    op.create_table(
        "announcements",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("title", sa.String(120), nullable=False),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column("active", sa.Boolean(), nullable=False),
        sa.Column("expires_at", ts, nullable=True),
        sa.Column("created_by", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("created_at", ts, nullable=False),
    )
    op.create_index("ix_announcements_created_at", "announcements", ["created_at"])
    op.create_table(
        "question_reports",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("question_key", sa.String(64), nullable=False),
        sa.Column("question_id", sa.Integer(), nullable=True),
        sa.Column("question_text", sa.Text(), nullable=False),
        sa.Column("reason", sa.String(20), nullable=False),
        sa.Column("note", sa.String(500), nullable=True),
        sa.Column("status", sa.String(10), nullable=False),
        sa.Column("created_at", ts, nullable=False),
        sa.Column("resolved_by", sa.Integer(), nullable=True),
        sa.Column("resolved_at", ts, nullable=True),
    )
    op.create_index("ix_question_reports_question_key", "question_reports", ["question_key"])
    op.create_index("ix_question_reports_status", "question_reports", ["status"])
    op.create_index("ix_question_reports_created_at", "question_reports", ["created_at"])


def downgrade() -> None:
    op.drop_table("question_reports")
    op.drop_table("announcements")
    op.drop_table("import_batches")
    op.drop_column("subjects", "position")
    op.drop_column("subjects", "track")
    for t in ("units", "subjects", "grades"):
        op.drop_column(t, "archived_at")
    op.drop_constraint("uq_users_username", "users", type_="unique")
    for c in ("suspended_by_id", "suspended_until", "suspended_at", "suspended_reason", "promoted_by_id", "is_owner", "username", "selected_track"):
        op.drop_column("users", c)
