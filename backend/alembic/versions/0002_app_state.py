"""per-student app state document

Revision ID: 0002
Revises: 0001
Create Date: 2026-10-17 12:00:00
"""
from alembic import op
import sqlalchemy as sa

revision = '0002'
down_revision = '0001'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table('app_states',
                    sa.Column('user_id', sa.Integer(), nullable=False),
                    sa.Column('data', sa.JSON(), nullable=False),
                    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
                    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
                    sa.PrimaryKeyConstraint('user_id'))


def downgrade() -> None:
    op.drop_table('app_states')
