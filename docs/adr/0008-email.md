# ADR 0008: Email: verification, password reset, invites and notifications

- **Status:** Accepted
- **Date:** 2026-11-04
- **Related:** [contract section 18](../api/contract.md), issues #15 and #18.

## Context

Until now the app sent no email: a forgotten password needed the operator's `reset-password` CLI,
invites travelled as links people copied by hand, and nothing told members about new polls, wheel
results or what's coming up. An SMTP account (SMTP2GO) is now available.

## Decision

| Question | Decision | Why |
|---|---|---|
| Transport | Plain SMTP from the stdlib (`smtplib`), configured by `SMTP_*`; logged instead when `SMTP_HOST` is unset | Works with any provider, no SDK or API key format to follow, nothing new to install. Development and tests need no mail server. |
| When request-time emails go out | FastAPI background tasks, after the response | A slow or failing mail server never delays or fails sign-up, a reset request or an invite. |
| Verification | Soft: a banner, nothing blocked | Friends is invite-only, so a hard gate mostly adds friction. What matters is that a reset link only goes to an address that proved it is the user's. |
| Who gets a reset link | Only a verified address; always a 202 | An unverified address may be a typo belonging to a stranger, who would otherwise get a way into the account. The 202 doesn't reveal accounts. |
| Link tokens | Random, single use, only the sha256 stored, bound to the address they were sent to | The same pattern as refresh tokens; a leaked database doesn't give working links, and changing the address voids old links. |
| Notifications | A cron job (`send-notifications`, every 5 minutes) reading `group_log` and the calendar | No scheduler thread in the web process, nothing to hook into every service, and the same cron the backups use. A missed run catches up from the log. |
| Channels | Browser push (Web Push with VAPID) first; email only when the user turns it on | Push is instant and needs no inbox; email notifications are easy to ignore or mark as spam. Push needs no Firebase: the standard works in every current browser. |
| Push implementation | RFC 8291/8292 written on `cryptography` | `pywebpush` pulls in packages without Python 3.15 wheels; the two RFCs are about 150 lines. |
| Duplicates | A `notification_deliveries` row (unique per user, channel, kind and subject) committed before sending; a notice that went out on any channel isn't sent on another | At most once: a crash between the two can drop a notification but never sends it twice, and turning email on doesn't resend the past. |
| Unsubscribing | One switch per kind, a signed token without expiry in every email, RFC 8058 one-click headers | Old emails must keep working; Gmail and Yahoo expect one-click unsubscribe from bulk-ish senders. |
| Language | English only | As for server errors (section 16); the app's languages can come later with `users.locale`. |

## Consequences

- Production sets the `SMTP_*` variables and adds the `send-notifications` cron line (deploy
  README). The sender domain needs SPF and DKIM at the provider, or the emails land in spam.
- Existing accounts start unverified; they see the banner and confirm with one tap.
- Production also sets `VAPID_PRIVATE_KEY` (deploy README) for push.
- Native Android push (FCM) would be one more channel in the same job; it needs a Firebase project.
