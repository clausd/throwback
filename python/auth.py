"""
auth.py — Password hashing, token handling, and login rate limiting.

All logic mirrors CrudApp.pm exactly so that the Perl and Python backends
are interchangeable: a token minted by Perl is valid on Python and vice versa.
"""
import hashlib
import os
import time
from typing import Annotated

from fastapi import Depends, Header, HTTPException
from sqlalchemy import text
from sqlalchemy.engine import Connection


# ── Password helpers ──────────────────────────────────────────────────────────

def hash_password(salt: str, password: str) -> str:
    """SHA256(salt + password) — identical to Perl's sha256_hex($salt . $password)."""
    return hashlib.sha256((salt + password).encode()).hexdigest()


def generate_token() -> str:
    """SHA256(32 random bytes) — identical to Perl's generate_token()."""
    return hashlib.sha256(os.urandom(32)).hexdigest()


def generate_salt() -> str:
    """First 32 hex chars of a token — matches Perl's substr(generate_token, 0, 32)."""
    return generate_token()[:32]


# ── Bearer token extraction ───────────────────────────────────────────────────

def extract_bearer_token(authorization: str | None) -> str | None:
    """Parse 'Bearer <token>' from the Authorization header value."""
    if not authorization:
        return None
    parts = authorization.split()
    if len(parts) == 2 and parts[0].lower() == "bearer":
        return parts[1]
    return None


# ── Current-user dependency factory ──────────────────────────────────────────

def make_get_current_user(get_db):
    """
    Returns a FastAPI dependency that resolves the bearer token to a user row.
    Raises 401 if no valid token.  Call once at app startup, pass result to Depends().
    """
    def get_current_user(
        authorization: Annotated[str | None, Header()] = None,
        db: Connection = Depends(get_db),
    ) -> dict:
        token = extract_bearer_token(authorization)
        if not token:
            raise HTTPException(status_code=401, detail="Unauthorized")

        row = db.execute(
            text("""
                SELECT u.*
                FROM   _auth u
                JOIN   _sessions s ON s.user_id = u.id
                WHERE  s.token = :token
                  AND  s.expires_at > CURRENT_TIMESTAMP
            """),
            {"token": token},
        ).mappings().first()

        if not row:
            raise HTTPException(status_code=401, detail="Unauthorized")

        return dict(row)

    return get_current_user


# ── Rate limiting (mirrors Perl _check/_record/_clear_login_failures) ─────────

def check_rate_limit(conn: Connection, username: str) -> str | None:
    """
    Return an error string if the account is locked, or None if login is allowed.
    _login_attempts.locked_until is a Unix timestamp INTEGER — compare with time().
    """
    row = conn.execute(
        text("SELECT failed_count, locked_until FROM _login_attempts WHERE username = :u"),
        {"u": username},
    ).mappings().first()

    if not row or not row["locked_until"]:
        return None

    wait = int(row["locked_until"]) - int(time.time())
    if wait <= 0:
        return None

    if wait >= 3600:
        return f"Too many failed login attempts. Try again in {wait // 3600} hour(s)."
    if wait >= 60:
        return f"Too many failed login attempts. Try again in {wait // 60} minute(s)."
    return f"Too many failed login attempts. Try again in {wait}s."


def record_login_failure(conn: Connection, username: str) -> None:
    """
    Exponential backoff: penalty = 2^(count-1) seconds, capped at 86400.
    Matches Perl's _record_login_failure() exactly.
    """
    row = conn.execute(
        text("SELECT failed_count FROM _login_attempts WHERE username = :u"),
        {"u": username},
    ).mappings().first()

    current = row["failed_count"] if row else 0
    count = current + 1
    penalty = min(2 ** (count - 1), 86400)
    locked_until = int(time.time()) + penalty

    if row:
        conn.execute(
            text("""
                UPDATE _login_attempts
                SET    failed_count = :count, locked_until = :lu
                WHERE  username = :u
            """),
            {"count": count, "lu": locked_until, "u": username},
        )
    else:
        conn.execute(
            text("""
                INSERT INTO _login_attempts (username, failed_count, locked_until)
                VALUES (:u, :count, :lu)
            """),
            {"u": username, "count": count, "lu": locked_until},
        )


def clear_login_failures(conn: Connection, username: str) -> None:
    """Delete the rate-limit record on successful login."""
    conn.execute(
        text("DELETE FROM _login_attempts WHERE username = :u"),
        {"u": username},
    )
