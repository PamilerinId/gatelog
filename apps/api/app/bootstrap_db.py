"""Prepare a deployed database, then prove Row-Level Security applies to the API's role.

Run as a one-off job with the same image as the API (python -m app.bootstrap_db):

  1. create the app role gatelog_app if missing, and set its password (APP_DB_PASSWORD);
     never superuser, never BYPASSRLS, never a member of cloudsqlsuperuser;
  2. alembic upgrade head, as the owner (DATABASE_OWNER_URL);
  3. check: gatelog_app owns no table, cannot bypass RLS, is in no admin role, and every
     table with estate_id has RLS on. Any failure exits non-zero, so a deploy stops.

The local equivalent of step 1 is apps/api/db/init/01-roles.sql.
"""

import os
import subprocess
import sys

from sqlalchemy import create_engine, text

from .config import get_settings

APP_ROLE = "gatelog_app"


def main() -> int:
    password = os.environ.get("APP_DB_PASSWORD")
    if not password:
        print("APP_DB_PASSWORD is required", file=sys.stderr)
        return 2
    engine = create_engine(get_settings().database_owner_url)

    with engine.begin() as c:
        exists = c.execute(text("SELECT 1 FROM pg_roles WHERE rolname = :r"), {"r": APP_ROLE}).first()
        if not exists:
            c.execute(text(f"CREATE ROLE {APP_ROLE} LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE"))
            print(f"created role {APP_ROLE}")
        # Quoted as a literal by the driver's own escaping: the password never reaches a log.
        quoted = c.execute(text("SELECT quote_literal(:p)"), {"p": password}).scalar()
        c.execute(text(f"ALTER ROLE {APP_ROLE} WITH LOGIN NOBYPASSRLS PASSWORD {quoted}"))
        c.execute(text(f"GRANT CONNECT ON DATABASE {c.engine.url.database} TO {APP_ROLE}"))
        c.execute(text(f"GRANT USAGE ON SCHEMA public TO {APP_ROLE}"))

    print("alembic upgrade head")
    r = subprocess.run([sys.executable, "-m", "alembic", "upgrade", "head"])
    if r.returncode:
        return r.returncode

    problems: list[str] = []
    with engine.connect() as c:
        role = c.execute(text("SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname = :r"), {"r": APP_ROLE}).one()
        if role.rolsuper or role.rolbypassrls:
            problems.append(f"{APP_ROLE} is superuser or has BYPASSRLS")
        admin_roles = c.execute(text(
            "SELECT b.rolname FROM pg_auth_members m JOIN pg_roles a ON a.oid = m.member JOIN pg_roles b ON b.oid = m.roleid "
            "WHERE a.rolname = :r"), {"r": APP_ROLE}).scalars().all()
        if admin_roles:
            problems.append(f"{APP_ROLE} is a member of {admin_roles}")
        owned = c.execute(text("SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tableowner = :r"), {"r": APP_ROLE}).scalars().all()
        if owned:
            problems.append(f"{APP_ROLE} owns {owned}")
        no_rls = c.execute(text(
            "SELECT t.relname FROM pg_class t JOIN pg_namespace n ON n.oid = t.relnamespace "
            "JOIN information_schema.columns col ON col.table_name = t.relname AND col.table_schema = 'public' AND col.column_name = 'estate_id' "
            "WHERE n.nspname = 'public' AND t.relkind = 'r' AND NOT t.relrowsecurity AND t.relname <> 'staff_users'")).scalars().all()
        if no_rls:
            problems.append(f"tables with estate_id but no RLS: {no_rls}")
    for p in problems:
        print("ISOLATION CHECK FAILED: " + p, file=sys.stderr)
    if not problems:
        print(f"isolation checks passed: {APP_ROLE} cannot bypass RLS, owns nothing, is in no admin role; every estate table has RLS")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
