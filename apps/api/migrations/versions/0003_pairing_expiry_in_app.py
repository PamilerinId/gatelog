"""pairing expiry checked by the app clock

Revision ID: 0003
Revises: 0002

gatelog_find_pairing compared expiry with the database's now(), while the API sets expiry
from its own clock. One clock decides: the function returns the expiry and the API checks it.
"""

from alembic import op

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None

APP_ROLE = "gatelog_app"


def upgrade() -> None:
    op.execute(f"""
        DROP FUNCTION gatelog_find_pairing(text);
        CREATE FUNCTION gatelog_find_pairing(code_hash text)
          RETURNS TABLE (device_id uuid, estate_id uuid, expires_at timestamptz)
          LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
            SELECT d.id, d.estate_id, d.pairing_expires_at FROM devices d
            WHERE d.pairing_code_hash = code_hash AND d.revoked_at IS NULL
          $$;
        REVOKE ALL ON FUNCTION gatelog_find_pairing(text) FROM PUBLIC;
        GRANT EXECUTE ON FUNCTION gatelog_find_pairing(text) TO {APP_ROLE};
    """)


def downgrade() -> None:
    raise NotImplementedError("0003 is not reversible; restore from a backup")
