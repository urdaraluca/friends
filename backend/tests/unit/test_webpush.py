"""RFC 8291: what :func:`encrypt` produces decrypts as a browser would; VAPID signs for the
push service's origin."""

import jwt
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from friends_api.core.webpush import (
    Vapid,
    _hkdf,
    _raw_public,
    b64url_decode,
    b64url_encode,
    encrypt,
)


def decrypt(body: bytes, ua_private: ec.EllipticCurvePrivateKey, auth: bytes) -> bytes:
    """The user agent's side of RFC 8291."""
    salt, record_size, id_len = body[:16], int.from_bytes(body[16:20], "big"), body[20]
    as_public_raw = body[21 : 21 + id_len]
    assert record_size == 4096
    as_public = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), as_public_raw)
    ecdh = ua_private.exchange(ec.ECDH(), as_public)
    ua_public_raw = _raw_public(ua_private.public_key())
    ikm = _hkdf(auth, b"WebPush: info\x00" + ua_public_raw + as_public_raw, 32, ecdh)
    cek = _hkdf(salt, b"Content-Encoding: aes128gcm\x00", 16, ikm)
    nonce = _hkdf(salt, b"Content-Encoding: nonce\x00", 12, ikm)
    plain = AESGCM(cek).decrypt(nonce, body[21 + id_len :], None)
    assert plain.endswith(b"\x02")
    return plain[:-1]


def test_a_push_message_round_trips() -> None:
    ua_private = ec.generate_private_key(ec.SECP256R1())
    auth = b"0123456789abcdef"
    p256dh = b64url_encode(_raw_public(ua_private.public_key()))

    body = encrypt(b'{"title": "Hi"}', p256dh, b64url_encode(auth))

    assert decrypt(body, ua_private, auth) == b'{"title": "Hi"}'


def test_vapid_signs_for_the_push_service_origin() -> None:
    vapid = Vapid.from_setting(Vapid.generate_private_key(), "mailto:ops@example.com")

    header = vapid.authorization("https://fcm.googleapis.com/fcm/send/abc")

    token = header.split("t=", 1)[1].split(",", 1)[0]
    key = header.split("k=", 1)[1]
    assert key == vapid.public_key
    assert len(b64url_decode(key)) == 65
    public = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), b64url_decode(key))
    claims = jwt.decode(token, public, algorithms=["ES256"], audience="https://fcm.googleapis.com")
    assert claims["sub"] == "mailto:ops@example.com"
