from pydantic import BaseModel


class CalendarFeed(BaseModel):
    """My webcal subscription (contract section 5.10). Both URLs are null when it is off."""

    url: str | None
    """``https://…/calendar-feed/<token>.ics``: for apps that take a plain URL."""
    webcal_url: str | None
    """The same URL with the ``webcal://`` scheme: opens the device's calendar app."""
