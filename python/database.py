"""
database.py — SQLAlchemy engine + raw SQL helpers.

Uses SQLAlchemy Core (text() queries) rather than ORM — the schema is owned
by dev/setup.pl and shared with the Perl backend.  No migrations here.
"""
from pathlib import Path
from typing import Any, Generator

from sqlalchemy import create_engine, text, Engine, Connection

from config import AppConfig


def make_engine(cfg: AppConfig) -> Engine:
    db = cfg.database
    if db.type == "sqlite":
        # Resolve path relative to repo root so it works regardless of CWD
        base = Path(__file__).parent.parent
        db_path = (base / db.path).resolve()
        engine = create_engine(
            f"sqlite:///{db_path}",
            connect_args={"check_same_thread": False},
        )
        # WAL mode: allows concurrent reads from Perl (port 3000) + Python (port 3001)
        with engine.connect() as conn:
            conn.execute(text("PRAGMA journal_mode = WAL"))
            conn.execute(text("PRAGMA foreign_keys = ON"))
            conn.commit()
        return engine
    else:
        raise NotImplementedError(f"DB type '{db.type}' not yet supported in Python backend")


def get_db_dependency(engine: Engine):
    """
    Returns a FastAPI Depends-compatible generator dependency.

    Usage in routes:
        db: Connection = Depends(get_db)   # where get_db = get_db_dependency(engine)
    """
    def get_db() -> Generator[Connection, None, None]:
        with engine.connect() as conn:
            conn.execute(text("PRAGMA foreign_keys = ON"))
            try:
                yield conn
                conn.commit()
            except Exception:
                conn.rollback()
                raise

    return get_db


# ── Raw SQL helpers (mirror Perl's get_row / get_rows / insert_row / …) ──────

def get_row(conn: Connection, table: str, where: dict[str, Any]) -> dict | None:
    cols = list(where.keys())
    clause = " AND ".join(f'"{c}" = :{c}' for c in cols)
    sql = f'SELECT * FROM "{table}"'
    if clause:
        sql += f" WHERE {clause}"
    sql += " LIMIT 1"
    row = conn.execute(text(sql), where).mappings().first()
    return dict(row) if row else None


def get_rows(
    conn: Connection,
    table: str,
    where: dict[str, Any],
    limit: int = 20,
    offset: int = 0,
) -> list[dict]:
    cols = list(where.keys())
    clause = " AND ".join(f'"{c}" = :{c}' for c in cols)
    params: dict[str, Any] = dict(where)
    params["_limit"] = limit
    params["_offset"] = offset
    sql = f'SELECT * FROM "{table}"'
    if clause:
        sql += f" WHERE {clause}"
    sql += " LIMIT :_limit OFFSET :_offset"
    rows = conn.execute(text(sql), params).mappings().all()
    return [dict(r) for r in rows]


def insert_row(conn: Connection, table: str, data: dict[str, Any]) -> int:
    cols = list(data.keys())
    col_sql = ", ".join(f'"{c}"' for c in cols)
    val_sql = ", ".join(f":{c}" for c in cols)
    result = conn.execute(text(f'INSERT INTO "{table}" ({col_sql}) VALUES ({val_sql})'), data)
    return result.lastrowid


def update_row(conn: Connection, table: str, row_id: int, data: dict[str, Any]) -> int:
    update_data = {k: v for k, v in data.items() if k != "id"}
    if not update_data:
        return 0
    set_sql = ", ".join(f'"{c}" = :{c}' for c in update_data)
    params: dict[str, Any] = dict(update_data)
    params["_id"] = row_id
    result = conn.execute(text(f'UPDATE "{table}" SET {set_sql} WHERE id = :_id'), params)
    return result.rowcount


def delete_row(conn: Connection, table: str, where: dict[str, Any]) -> int:
    cols = list(where.keys())
    clause = " AND ".join(f'"{c}" = :{c}' for c in cols)
    result = conn.execute(text(f'DELETE FROM "{table}" WHERE {clause}'), where)
    return result.rowcount
