"""Shared database connection for STAT 315 notebooks."""

from __future__ import annotations

import os

from sqlalchemy import URL, create_engine


DATABASE_URL = URL.create(
    drivername="postgresql+psycopg",
    username=os.environ.get("STAT315_DB_USER", "stat315_student"),
    password=os.environ.get("STAT315_DB_PASSWORD", "stat315_local_only"),
    host=os.environ.get("STAT315_DB_HOST", "postgres"),
    port=int(os.environ.get("STAT315_DB_PORT", "5432")),
    database=os.environ.get("STAT315_DB_NAME", "sqlda"),
)

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
