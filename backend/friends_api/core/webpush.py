"""Web Push (contract section 18.6): RFC 8291 message encryption and RFC 8292 VAPID, on
``cryptography`` (pywebpush needs packages without Python 3.15 wheels).
"""

import base64
import logging
import os
import time
from dataclasses import dataclass
from typing import Protocol
from urllib.parse import urlsplit

import httpx2
import jwt
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

from friends_api.core.config import Settings

logger = logging.getLogger(__name__)

RECORD_SIZE = 4096
TTL_SECONDS = 24 * 3600
TIMEOUT_SECONDS = 10.0


def b64url_decode(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def b64url_encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode()


def _raw_public(key: ec.EllipticCurvePublicKey) -> bytes:
    return key.public_bytes(
        serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint
    )


def _hkdf(salt: bytes, info: bytes, length: int, ikm: bytes) -> bytes:
    return HKDF(algorithm=hashes.SHA256(), length=length, salt=salt, info=info).derive(ikm)


def encrypt(
    payload: bytes,
    p256dh: str,
    auth: str,
    *,
    salt: bytes | None = None,
    sender: ec.EllipticCurvePrivateKey | None = None,
) -> bytes:
    """The ``aes128gcm`` body for one subscription (RFC 8291, a single record)."""
    ua_public_raw = b64url_decode(p256dh)
    ua_public = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), ua_public_raw)
    auth_secret = b64url_decode(auth)
    sender = sender or ec.generate_private_key(ec.SECP256R1())
    as_public_raw = _raw_public(sender.public_key())
    salt = salt or os.urandom(16)

    ecdh_secret = sender.exchange(ec.ECDH(), ua_public)
    key_info = b"WebPush: info\x00" + ua_public_raw + as_public_raw
    ikm = _hkdf(auth_secret, key_info, 32, ecdh_secret)
    cek = _hkdf(salt, b"Content-Encoding: aes128gcm\x00", 16, ikm)
    nonce = _hkdf(salt, b"Content-Encoding: nonce\x00", 12, ikm)
    ciphertext = AESGCM(cek).encrypt(nonce, payload + b"\x02", None)
    header = salt + RECORD_SIZE.to_bytes(4, "big") + bytes([len(as_public_raw)]) + as_public_raw
    return header + ciphertext


@dataclass(frozen=True, slots=True)
class Vapid:
    """The server's VAPID key pair; ``VAPID_PRIVATE_KEY`` is the base64url raw P-256 scalar."""

    private_key: ec.EllipticCurvePrivateKey
    subject: str

    @classmethod
    def from_setting(cls, private_key: str, subject: str) -> Vapid:
        scalar = int.from_bytes(b64url_decode(private_key), "big")
        return cls(ec.derive_private_key(scalar, ec.SECP256R1()), subject)

    @staticmethod
    def generate_private_key() -> str:
        key = ec.generate_private_key(ec.SECP256R1())
        return b64url_encode(key.private_numbers().private_value.to_bytes(32, "big"))

    @property
    def public_key(self) -> str:
        """The ``applicationServerKey`` browsers subscribe with (base64url, uncompressed)."""
        return b64url_encode(_raw_public(self.private_key.public_key()))

    def authorization(self, endpoint: str) -> str:
        parts = urlsplit(endpoint)
        claims = {
            "aud": f"{parts.scheme}://{parts.netloc}",
            "exp": int(time.time()) + 12 * 3600,
            "sub": self.subject,
        }
        token = jwt.encode(claims, self.private_key, algorithm="ES256")
        return f"vapid t={token}, k={self.public_key}"


@dataclass(frozen=True, slots=True)
class PushTarget:
    endpoint: str
    p256dh: str
    auth: str


class PushResult:
    SENT = "sent"
    GONE = "gone"
    """The subscription expired or was revoked: delete it."""
    FAILED = "failed"


class Pusher(Protocol):
    @property
    def public_key(self) -> str | None: ...

    def close(self) -> None: ...

    def push(self, target: PushTarget, payload: bytes) -> str:
        """Delivers ``payload``; returns a :class:`PushResult` value, never raises."""
        ...


class WebPusher:
    def __init__(self, vapid: Vapid | None, client: httpx2.Client | None = None) -> None:
        self._vapid = vapid
        self._client = client or httpx2.Client(timeout=TIMEOUT_SECONDS)

    @property
    def public_key(self) -> str | None:
        return self._vapid.public_key if self._vapid else None

    def close(self) -> None:
        self._client.close()

    def push(self, target: PushTarget, payload: bytes) -> str:
        if self._vapid is None:
            return PushResult.FAILED
        try:
            body = encrypt(payload, target.p256dh, target.auth)
            response = self._client.post(
                target.endpoint,
                content=body,
                headers={
                    "Content-Encoding": "aes128gcm",
                    "Content-Type": "application/octet-stream",
                    "TTL": str(TTL_SECONDS),
                    "Urgency": "normal",
                    "Authorization": self._vapid.authorization(target.endpoint),
                },
            )
        except (httpx2.HTTPError, ValueError) as exc:
            logger.warning("Push to %s failed: %s", urlsplit(target.endpoint).netloc, exc)
            return PushResult.FAILED
        if response.status_code in (404, 410):
            return PushResult.GONE
        if response.status_code >= 300:
            logger.warning(
                "Push to %s answered %s", urlsplit(target.endpoint).netloc, response.status_code
            )
            return PushResult.FAILED
        return PushResult.SENT


def create_pusher(settings: Settings) -> WebPusher:
    vapid = (
        Vapid.from_setting(settings.vapid_private_key, settings.push_subject)
        if settings.vapid_private_key
        else None
    )
    return WebPusher(vapid)


class RecordingPusher:
    """Tests: keeps the (target, decoded JSON payload bytes) pairs."""

    public_key = "test-public-key"

    def __init__(self) -> None:
        self.pushed: list[tuple[PushTarget, bytes]] = []
        self.gone: set[str] = set()

    def close(self) -> None:
        pass

    def push(self, target: PushTarget, payload: bytes) -> str:
        if target.endpoint in self.gone:
            return PushResult.GONE
        self.pushed.append((target, payload))
        return PushResult.SENT
