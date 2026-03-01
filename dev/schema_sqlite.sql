-- CrudApp SQLite Schema
-- Compatible schema for local development
-- Run with: sqlite3 dev.db < dev/schema_sqlite.sql

-- ============================================
-- Authentication Tables (required)
-- ============================================

CREATE TABLE IF NOT EXISTS _auth (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password_salt TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    access_rules TEXT,
    email TEXT,
    email_verified INTEGER DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Trigger for updated_at (SQLite doesn't have ON UPDATE CURRENT_TIMESTAMP)
CREATE TRIGGER IF NOT EXISTS _auth_updated_at
AFTER UPDATE ON _auth
BEGIN
    UPDATE _auth SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

CREATE TABLE IF NOT EXISTS _sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    token TEXT UNIQUE NOT NULL,
    user_id INTEGER NOT NULL,
    expires_at DATETIME NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES _auth(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_sessions_token ON _sessions(token);
CREATE INDEX IF NOT EXISTS idx_sessions_expires ON _sessions(expires_at);

-- ============================================
-- Example: Todos Table
-- ============================================

CREATE TABLE IF NOT EXISTS todos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    done INTEGER DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES _auth(id) ON DELETE CASCADE
);

CREATE TRIGGER IF NOT EXISTS todos_updated_at
AFTER UPDATE ON todos
BEGIN
    UPDATE todos SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

CREATE INDEX IF NOT EXISTS idx_todos_user ON todos(user_id);

-- ============================================
-- Login rate limiting
-- ============================================

CREATE TABLE IF NOT EXISTS _login_attempts (
    username TEXT PRIMARY KEY,
    failed_count INTEGER NOT NULL DEFAULT 0,
    locked_until INTEGER  -- Unix timestamp; NULL or past means not locked
);

-- ============================================
-- Email verification tokens
-- ============================================

CREATE TABLE IF NOT EXISTS _email_verifications (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    token TEXT UNIQUE NOT NULL,
    expires_at DATETIME NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES _auth(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_email_verif_token ON _email_verifications(token);
CREATE INDEX IF NOT EXISTS idx_email_verif_user  ON _email_verifications(user_id);

-- ============================================
-- Cleanup: Remove expired sessions
-- Run periodically or manually
-- ============================================

-- DELETE FROM _sessions WHERE expires_at < datetime('now');
