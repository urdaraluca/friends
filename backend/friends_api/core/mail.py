"""Outgoing email (contract section 18).

Routers hand :class:`Email` values to :func:`send_later` (FastAPI background tasks run them after
the response), so a slow mail server never holds a request or a database transaction. The CLI's
notification job sends synchronously.
"""

import logging
import smtplib
import ssl
from collections.abc import Mapping
from dataclasses import dataclass, field
from email.message import EmailMessage
from email.utils import make_msgid
from typing import Protocol

from friends_api.core.config import Settings

logger = logging.getLogger(__name__)

SMTP_TIMEOUT_SECONDS = 20


@dataclass(frozen=True, slots=True, kw_only=True)
class Email:
    to: str
    subject: str
    text: str
    html: str
    headers: Mapping[str, str] = field(default_factory=dict)


class Mailer(Protocol):
    def send(self, email: Email) -> None:
        """Sends one email; raises on failure."""
        ...


def build_message(email: Email, sender: str) -> EmailMessage:
    message = EmailMessage()
    message["From"] = sender
    message["To"] = email.to
    message["Subject"] = email.subject
    message["Message-ID"] = make_msgid(domain=sender.rsplit("@", 1)[-1].rstrip(">"))
    for name, value in email.headers.items():
        message[name] = value
    message.set_content(email.text)
    message.add_alternative(email.html, subtype="html")
    return message


class SmtpMailer:
    """SMTP with STARTTLS on 587 (or any port but 465), implicit TLS on 465."""

    def __init__(self, settings: Settings) -> None:
        assert settings.smtp_host is not None  # noqa: S101 - create_mailer checks
        self._host = settings.smtp_host
        self._port = settings.smtp_port
        self._username = settings.smtp_username
        self._password = settings.smtp_password
        self._sender = settings.mail_sender

    def send(self, email: Email) -> None:
        context = ssl.create_default_context()
        smtp: smtplib.SMTP
        if self._port == 465:
            smtp = smtplib.SMTP_SSL(
                self._host, self._port, timeout=SMTP_TIMEOUT_SECONDS, context=context
            )
        else:
            smtp = smtplib.SMTP(self._host, self._port, timeout=SMTP_TIMEOUT_SECONDS)
        with smtp:
            if self._port != 465:
                smtp.starttls(context=context)
            if self._username and self._password:
                smtp.login(self._username, self._password)
            smtp.send_message(build_message(email, self._sender))


class LogMailer:
    """Development without SMTP: the email is logged, links included, and not sent."""

    def send(self, email: Email) -> None:
        logger.info(
            "Email to %s (not sent, SMTP_HOST is unset): %s\n%s",
            email.to,
            email.subject,
            email.text,
        )


class RecordingMailer:
    """Tests: keeps what would have been sent."""

    def __init__(self) -> None:
        self.sent: list[Email] = []

    def send(self, email: Email) -> None:
        self.sent.append(email)


def create_mailer(settings: Settings) -> Mailer:
    return SmtpMailer(settings) if settings.smtp_host else LogMailer()


def send_safely(mailer: Mailer, email: Email) -> bool:
    """Sends ``email``, logging instead of raising: a failed email never fails a request."""
    try:
        mailer.send(email)
    except Exception:
        logger.exception("Could not send %r to %s", email.subject, email.to)
        return False
    return True
