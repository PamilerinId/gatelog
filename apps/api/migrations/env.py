"""Migrations run as the table owner (DATABASE_OWNER_URL), never as the app role."""

from alembic import context
from sqlalchemy import create_engine

from app.config import get_settings
from app.models import Base

url = context.config.attributes.get("url") or get_settings().database_owner_url

with create_engine(url).connect() as connection:
    context.configure(connection=connection, target_metadata=Base.metadata, compare_type=True)
    with context.begin_transaction():
        context.run_migrations()
