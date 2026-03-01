"""
main.py — FastAPI backend for the CrudApp todo example app.

Peer to the Perl backend (port 3000).  Runs on port 3001.

The frontend is SHARED — both backends serve the exact same
example/index.html and example/js/crud-client.js unchanged.
The JS client uses new CrudClient('.') so it always talks to
whichever backend served the page: visit :3000 → Perl, :3001 → Python.
"""

import asyncio
import json
import time
from pathlib import Path
from typing import Annotated, Any

from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text
from sqlalchemy.engine import Connection

from auth import (
    check_rate_limit,
    clear_login_failures,
    extract_bearer_token,
    generate_salt,
    generate_token,
    hash_password,
    make_get_current_user,
    record_login_failure,
)
from config import load_config
from database import (
    delete_row,
    get_db_dependency,
    get_row,
    get_rows,
    insert_row,
    make_engine,
    update_row,
)
from email_utils import send_template_email

# ── Startup ───────────────────────────────────────────────────────────────────

BASE_DIR = Path(__file__).parent.parent       # repo root
EXAMPLE_DIR = BASE_DIR / "example"
EMAIL_TEMPLATE_DIR = EXAMPLE_DIR / "email_templates"

config = load_config()
engine = make_engine(config)
get_db = get_db_dependency(engine)
get_current_user = make_get_current_user(get_db)

app = FastAPI(title="CrudApp Python", version="1.0.0")

# ── Static files — serve the SHARED frontend ──────────────────────────────────
# /js/crud-client.js  →  example/js/crud-client.js  (no copy; same file)
app.mount("/js", StaticFiles(directory=str(EXAMPLE_DIR / "js")), name="js")


@app.get("/", include_in_schema=False)
async def serve_index() -> FileResponse:
    """Serve the shared Vue SPA (example/index.html) — identical to Perl."""
    return FileResponse(str(EXAMPLE_DIR / "index.html"))


# ── Helpers ───────────────────────────────────────────────────────────────────

def err(message: str, status: int = 400) -> JSONResponse:
    return JSONResponse({"error": message}, status_code=status)


def get_user_filters(user: dict) -> dict[str, Any]:
    """
    Resolve access_rules JSON filters for the 'todos' table.
    Mirrors Perl's get_filters(): '$user.id' → user['id'], etc.
    """
    try:
        rules = json.loads(user.get("access_rules") or "{}")
    except (json.JSONDecodeError, TypeError):
        rules = {}
    raw = rules.get("tables", {}).get("todos", {}).get("filters", {})
    resolved: dict[str, Any] = {}
    for k, v in raw.items():
        if v == "$user.id":
            resolved[k] = user["id"]
        elif isinstance(v, str) and v.startswith("$user."):
            resolved[k] = user.get(v[len("$user."):])
        else:
            resolved[k] = v
    return resolved


# ── Public routes ─────────────────────────────────────────────────────────────

@app.get("/index")
async def api_index() -> dict:
    return {"status": "ok", "message": "CrudApp API", "version": "1.0.0"}


@app.post("/login")
async def login(request: Request, db: Connection = Depends(get_db)):
    try:
        body = await request.json()
    except Exception:
        return err("Missing credentials", 400)

    username = (body.get("username") or "").strip()
    password = body.get("password") or ""
    if not username or not password:
        return err("Missing credentials", 400)

    # Rate limit check — before touching the password (mirrors Perl)
    rate_msg = check_rate_limit(db, username)
    if rate_msg:
        return err(rate_msg, 429)

    # Fetch user
    user = get_row(db, "_auth", {"username": username})

    # Always hash — timing attack mitigation (mirrors Perl)
    salt = user["password_salt"] if user else "0" * 32
    ok = user is not None and hash_password(salt, password) == user["password_hash"]

    if not ok:
        record_login_failure(db, username)
        return err("Invalid credentials", 401)

    clear_login_failures(db, username)

    # Email verification gate (require_email_verified = 1 in MyApi)
    if not user.get("email_verified"):
        return err("Please verify your email before logging in", 403)

    # Create session — 7 days
    token = generate_token()
    expires = int(time.time()) + 86400 * 7
    db.execute(
        text("""
            INSERT INTO _sessions (token, user_id, expires_at)
            VALUES (:token, :user_id, datetime(:expires, 'unixepoch'))
        """),
        {"token": token, "user_id": user["id"], "expires": expires},
    )
    return {"token": token, "expires": expires}


@app.post("/logout")
async def logout(request: Request, db: Connection = Depends(get_db)):
    token = extract_bearer_token(request.headers.get("authorization"))
    if token:
        db.execute(text("DELETE FROM _sessions WHERE token = :t"), {"t": token})
    return {"ok": 1}


@app.post("/register", status_code=201)
async def register(request: Request, db: Connection = Depends(get_db)):
    try:
        body = await request.json()
    except Exception:
        return err("POST with JSON body required", 400)

    username = (body.get("username") or "").strip()
    password = body.get("password") or ""
    email = (body.get("email") or "").strip()

    if not username or not password or not email:
        return err("username, password and email are required", 400)

    import re
    if not re.match(r"\A[^@\s]+@[^@\s]+\.[^@\s]+\Z", email):
        return err("Invalid email address", 400)

    if len(password) < 8:
        return err("Password must be at least 8 characters", 400)

    if get_row(db, "_auth", {"username": username}):
        return err("Username already taken", 409)
    if get_row(db, "_auth", {"email": email}):
        return err("Email already registered", 409)

    # Create user (email_verified = 0)
    salt = generate_salt()
    access_rules = json.dumps({
        "tables": {
            "todos": {
                "access": ["create", "read", "update", "delete"],
                "filters": {"user_id": "$user.id"},
            }
        }
    })
    db.execute(
        text("""
            INSERT INTO _auth
                (username, password_salt, password_hash, access_rules, email, email_verified)
            VALUES (:username, :salt, :hash, :rules, :email, 0)
        """),
        {
            "username": username,
            "salt": salt,
            "hash": hash_password(salt, password),
            "rules": access_rules,
            "email": email,
        },
    )
    user_id = db.execute(
        text("SELECT id FROM _auth WHERE username = :u"), {"u": username}
    ).scalar()

    # One-time verification token (24 h)
    vtoken = generate_token()
    db.execute(text("DELETE FROM _email_verifications WHERE user_id = :uid"), {"uid": user_id})
    db.execute(
        text("""
            INSERT INTO _email_verifications (user_id, token, expires_at)
            VALUES (:uid, :token, datetime(:exp, 'unixepoch'))
        """),
        {"uid": user_id, "token": vtoken, "exp": int(time.time()) + 86400},
    )

    # Build verify URL
    base_url = (
        config.server.app_url
        or request.headers.get("origin")
        or f"http://{request.headers.get('host', 'localhost')}"
    )
    verify_url = f"{base_url}/?verify={vtoken}"

    # Send email — silently skip if SMTP not configured
    if config.smtp.host:
        template = EMAIL_TEMPLATE_DIR / "verify_email.txt"
        try:
            await asyncio.to_thread(
                send_template_email,
                config.smtp,
                email,
                template,
                {"username": username, "app_name": config.server.app_name, "verify_url": verify_url},
            )
        except Exception as exc:
            print(f"Warning: verification email failed: {exc}")

    return JSONResponse(
        {"ok": 1, "message": "Account created. Please check your email to verify your address."},
        status_code=201,
    )


@app.get("/verify_email/{token}")
async def verify_email(token: str, db: Connection = Depends(get_db)):
    row = db.execute(
        text("""
            SELECT user_id
            FROM   _email_verifications
            WHERE  token = :token
              AND  expires_at > datetime('now')
        """),
        {"token": token},
    ).mappings().first()

    if not row:
        return err("Invalid or expired verification link", 400)

    db.execute(text("UPDATE _auth SET email_verified = 1 WHERE id = :uid"), {"uid": row["user_id"]})
    db.execute(text("DELETE FROM _email_verifications WHERE token = :token"), {"token": token})
    return {"ok": 1, "message": "Email verified. You can now log in."}


# ── Authenticated todo routes ─────────────────────────────────────────────────

@app.get("/todos")
async def list_todos(
    limit: int = 20,
    offset: int = 0,
    user: dict = Depends(get_current_user),
    db: Connection = Depends(get_db),
):
    limit = min(limit, 100)   # cap at 100 — same as Perl
    rows = get_rows(db, "todos", get_user_filters(user), limit, offset)
    return {"data": rows, "limit": limit, "offset": offset}


@app.get("/todos/{todo_id}")
async def get_todo(
    todo_id: int,
    user: dict = Depends(get_current_user),
    db: Connection = Depends(get_db),
):
    row = get_row(db, "todos", {**get_user_filters(user), "id": todo_id})
    return row if row else err("Not found", 404)


@app.post("/todos")
async def upsert_todo(
    request: Request,
    user: dict = Depends(get_current_user),
    db: Connection = Depends(get_db),
):
    """
    Single endpoint for create AND update — mirrors Perl's _crud_upsert():
      body has 'id'  → update (returns 200 + updated record)
      body has no id → create (returns 201 + created record)
    """
    try:
        body = await request.json()
    except Exception:
        return err("Invalid JSON body", 400)

    filters = get_user_filters(user)
    # Merge ownership filters into input so user_id is always set correctly
    data = {**body, **filters}
    todo_id = data.get("id")

    if todo_id:
        # Update — verify ownership first
        if not get_row(db, "todos", {"id": todo_id, **filters}):
            return err("Not found", 404)
        update_row(db, "todos", todo_id, data)
        updated = get_row(db, "todos", {"id": todo_id})
        return JSONResponse(updated, status_code=200)
    else:
        new_id = insert_row(db, "todos", data)
        created = get_row(db, "todos", {"id": new_id})
        return JSONResponse(created, status_code=201)


@app.delete("/todos/{todo_id}")
async def delete_todo(
    todo_id: int,
    user: dict = Depends(get_current_user),
    db: Connection = Depends(get_db),
):
    n = delete_row(db, "todos", {**get_user_filters(user), "id": todo_id})
    return {"deleted": todo_id} if n else err("Not found", 404)


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host=config.server.host,
        port=3001,
        reload=True,
        log_level="info",
    )
