"""
email_utils.py — Template rendering and SMTP email sending.

Mirrors CrudApp::Email: same {{variable}} substitution syntax, same
Subject: first-line parsing, same STARTTLS / SSL / plain SMTP options.
"""
import re
import smtplib
import ssl
from email.message import EmailMessage
from pathlib import Path

from config import SmtpConfig


def render_template(template_path: str | Path, vars: dict) -> tuple[str, str]:
    """
    Load template, substitute {{variable}} placeholders, return (subject, body).

    Template format (same as example/email_templates/verify_email.txt):
        Subject: Welcome to {{app_name}}
        <blank line>
        Hi {{username}}, ...

    Missing variables are replaced with empty string — matching Perl behaviour.
    """
    content = Path(template_path).read_text(encoding="utf-8")

    def replacer(m: re.Match) -> str:
        return str(vars.get(m.group(1), ""))

    content = re.sub(r"\{\{(\w+)\}\}", replacer, content)

    # Split on first blank line to separate Subject from body
    match = re.match(r"Subject:\s*([^\n]*)\n\n?(.*)", content, re.DOTALL)
    if match:
        return match.group(1).strip(), match.group(2)
    return "(no subject)", content


def send_email(cfg: SmtpConfig, to: str, subject: str, body: str) -> None:
    """
    Send a plain-text email via smtplib.
    Supports direct SSL (port 465, cfg.ssl=True) and STARTTLS (port 587, cfg.starttls=True).
    Raises on failure — callers should catch and warn.
    """
    msg = EmailMessage()
    msg["From"] = f"{cfg.from_name} <{cfg.from_addr}>" if cfg.from_name else cfg.from_addr
    msg["To"] = to
    msg["Subject"] = subject
    msg.set_content(body)

    if cfg.ssl:
        ctx = ssl.create_default_context()
        with smtplib.SMTP_SSL(cfg.host, cfg.port, context=ctx, timeout=30) as s:
            if cfg.user:
                s.login(cfg.user, cfg.password)
            s.send_message(msg)
    else:
        with smtplib.SMTP(cfg.host, cfg.port, timeout=30) as s:
            if cfg.starttls:
                s.starttls(context=ssl.create_default_context())
            if cfg.user:
                s.login(cfg.user, cfg.password)
            s.send_message(msg)


def send_template_email(
    cfg: SmtpConfig,
    to: str,
    template_path: str | Path,
    vars: dict,
) -> None:
    """Render template then send — convenience wrapper."""
    subject, body = render_template(template_path, vars)
    send_email(cfg, to, subject, body)
