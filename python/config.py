"""
config.py — Load configuration from ../crudapp.conf (INI format).

Mirrors CrudApp::Config in structure and CRUDAPP_* env var names.
"""
import configparser
import os
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class DatabaseConfig:
    type: str = "sqlite"
    path: str = "./dev.db"
    name: str = ""
    user: str = ""
    password: str = ""
    host: str = "localhost"


@dataclass
class ServerConfig:
    port: int = 3001          # Python default; Perl stays on 3000
    host: str = "127.0.0.1"
    static_dir: str = "../example"
    app_url: str = ""
    app_name: str = "Todo App"


@dataclass
class SmtpConfig:
    host: str = ""
    port: int = 587
    user: str = ""
    password: str = ""        # INI key is 'pass' — Python keyword, mapped here
    from_addr: str = "noreply@localhost"
    from_name: str = ""
    ssl: bool = False
    starttls: bool = False


@dataclass
class AppConfig:
    database: DatabaseConfig = field(default_factory=DatabaseConfig)
    server: ServerConfig = field(default_factory=ServerConfig)
    smtp: SmtpConfig = field(default_factory=SmtpConfig)


def load_config(config_file: str | None = None) -> AppConfig:
    """
    Load from (in priority order):
      1. CRUDAPP_* environment variables
      2. crudapp.conf INI file
    """
    base_dir = Path(__file__).parent.parent  # repo root

    candidates = [
        Path(config_file) if config_file else None,
        base_dir / "crudapp.conf",
        base_dir / ".crudapp.conf",
    ]

    parser = configparser.ConfigParser()
    for candidate in candidates:
        if candidate and candidate.is_file():
            parser.read(candidate)
            break

    def get(section: str, key: str, fallback: str = "") -> str:
        try:
            return parser.get(section, key).strip()
        except (configparser.NoSectionError, configparser.NoOptionError):
            return fallback

    def get_int(section: str, key: str, fallback: int) -> int:
        v = get(section, key)
        return int(v) if v.isdigit() else fallback

    def get_bool(section: str, key: str) -> bool:
        return get(section, key) in ("1", "true", "yes", "on")

    db = DatabaseConfig(
        type=get("database", "type", "sqlite"),
        path=get("database", "path", "./dev.db"),
        name=get("database", "name"),
        user=get("database", "user"),
        password=get("database", "pass"),
        host=get("database", "host", "localhost"),
    )
    srv = ServerConfig(
        port=get_int("server", "port", 3001),
        host=get("server", "host", "127.0.0.1"),
        static_dir=get("server", "static_dir", "../example"),
        app_url=get("server", "app_url"),
        app_name=get("server", "app_name", "Todo App"),
    )
    smtp = SmtpConfig(
        host=get("smtp", "host"),
        port=get_int("smtp", "port", 587),
        user=get("smtp", "user"),
        password=get("smtp", "pass"),
        from_addr=get("smtp", "from", "noreply@localhost"),
        from_name=get("smtp", "from_name"),
        ssl=get_bool("smtp", "ssl"),
        starttls=get_bool("smtp", "starttls"),
    )

    # Environment variable overrides — identical names to Perl CRUDAPP_*
    if v := os.getenv("CRUDAPP_DB_TYPE"):        db.type = v
    if v := os.getenv("CRUDAPP_DB_PATH"):        db.path = v
    if v := os.getenv("CRUDAPP_DB_NAME"):        db.name = v
    if v := os.getenv("CRUDAPP_DB_USER"):        db.user = v
    if v := os.getenv("CRUDAPP_DB_PASS"):        db.password = v
    if v := os.getenv("CRUDAPP_DB_HOST"):        db.host = v
    if v := os.getenv("CRUDAPP_PORT"):           srv.port = int(v)
    if v := os.getenv("CRUDAPP_HOST"):           srv.host = v
    if v := os.getenv("CRUDAPP_STATIC_DIR"):     srv.static_dir = v
    if v := os.getenv("CRUDAPP_APP_URL"):        srv.app_url = v
    if v := os.getenv("CRUDAPP_SMTP_HOST"):      smtp.host = v
    if v := os.getenv("CRUDAPP_SMTP_PORT"):      smtp.port = int(v)
    if v := os.getenv("CRUDAPP_SMTP_USER"):      smtp.user = v
    if v := os.getenv("CRUDAPP_SMTP_PASS"):      smtp.password = v
    if v := os.getenv("CRUDAPP_SMTP_FROM"):      smtp.from_addr = v
    if v := os.getenv("CRUDAPP_SMTP_FROM_NAME"): smtp.from_name = v
    if v := os.getenv("CRUDAPP_SMTP_SSL"):       smtp.ssl = v in ("1", "true")
    if v := os.getenv("CRUDAPP_SMTP_STARTTLS"):  smtp.starttls = v in ("1", "true")

    return AppConfig(database=db, server=srv, smtp=smtp)
