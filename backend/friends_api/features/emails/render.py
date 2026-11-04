"""Plain-text and HTML bodies for every email (contract section 18). English only (section 16)."""

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from html import escape

from friends_api.core.mail import Email


@dataclass(frozen=True, slots=True)
class Action:
    label: str
    url: str


def compose(
    *,
    to: str,
    subject: str,
    paragraphs: Sequence[str],
    action: Action | None = None,
    after: Sequence[str] = (),
    footer: str | None = None,
    unsubscribe_url: str | None = None,
    one_click_url: str | None = None,
    headers: Mapping[str, str] | None = None,
) -> Email:
    """One email: ``paragraphs``, a button for ``action``, ``after`` and a small ``footer``.

    With ``unsubscribe_url`` (the app's page), the footer links to it; ``one_click_url`` (the API,
    which takes a POST) goes into the RFC 8058 ``List-Unsubscribe`` headers.
    """
    text_parts = [*paragraphs]
    if action is not None:
        text_parts.append(f"{action.label}: {action.url}")
    text_parts += after
    footer_text = footer or ""
    if unsubscribe_url:
        footer_text = f"{footer_text}\nUnsubscribe: {unsubscribe_url}".strip()
    text = "\n\n".join(text_parts) + (f"\n\n-- \n{footer_text}\n" if footer_text else "\n")

    html_parts = [f"<p>{escape(part)}</p>" for part in paragraphs]
    if action is not None:
        html_parts.append(
            f'<p><a href="{escape(action.url)}" style="display:inline-block;padding:10px 18px;'
            "background:#3949ab;color:#ffffff;border-radius:6px;text-decoration:none;"
            f'font-weight:600">{escape(action.label)}</a></p>'
            f'<p style="font-size:12px;color:#666">Or open this link: '
            f'<a href="{escape(action.url)}">{escape(action.url)}</a></p>'
        )
    html_parts += [f"<p>{escape(part)}</p>" for part in after]
    if footer or unsubscribe_url:
        footer_html = escape(footer or "")
        if unsubscribe_url:
            footer_html += f' <a href="{escape(unsubscribe_url)}">Unsubscribe</a>'
        html_parts.append(
            f'<hr style="border:none;border-top:1px solid #ddd">'
            f'<p style="font-size:12px;color:#666">{footer_html.strip()}</p>'
        )
    html = (
        '<!doctype html><html><body style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;'
        'font-size:15px;line-height:1.5;color:#222;max-width:560px">'
        + "".join(html_parts)
        + "</body></html>"
    )

    all_headers = dict(headers or {})
    if one_click_url:
        all_headers["List-Unsubscribe"] = f"<{one_click_url}>"
        all_headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
    return Email(to=to, subject=subject, text=text, html=html, headers=all_headers)
