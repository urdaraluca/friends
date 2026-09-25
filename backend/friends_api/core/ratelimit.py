"""In-process sliding-window rate limiting (the app runs as a single process)."""

import math
import threading
import time
from collections import deque
from collections.abc import Callable

from fastapi import Request

from friends_api.core.errors import RateLimited


class SlidingWindowLimiter:
    def __init__(
        self, limit: int, window_seconds: float, clock: Callable[[], float] = time.monotonic
    ) -> None:
        self.limit = limit
        self.window = window_seconds
        self._clock = clock
        self._hits: dict[str, deque[float]] = {}
        self._lock = threading.Lock()
        self._calls = 0

    def hit(self, key: str) -> None:
        """Records a hit for ``key``; raises RateLimited when the window is full."""
        now = self._clock()
        with self._lock:
            hits = self._hits.setdefault(key, deque())
            while hits and hits[0] <= now - self.window:
                hits.popleft()
            if len(hits) >= self.limit:
                raise RateLimited(math.ceil(hits[0] + self.window - now))
            hits.append(now)
            self._calls += 1
            if self._calls % 1000 == 0:
                self._prune(now)

    def _prune(self, now: float) -> None:
        stale = [
            key for key, hits in self._hits.items() if not hits or hits[-1] <= now - self.window
        ]
        for key in stale:
            del self._hits[key]


class RateLimits:
    """The app's named limiters, created per app instance (so tests start clean)."""

    def __init__(self, clock: Callable[[], float] = time.monotonic) -> None:
        self.login = SlidingWindowLimiter(10, 60, clock)
        self.register = SlidingWindowLimiter(5, 3600, clock)
        self.refresh = SlidingWindowLimiter(30, 60, clock)
        self.invites = SlidingWindowLimiter(20, 60, clock)


def client_ip(request: Request) -> str:
    # uvicorn --proxy-headers already resolved X-Forwarded-For from trusted proxies.
    return request.client.host if request.client else "unknown"


def limit_by_ip(name: str) -> Callable[[Request], None]:
    def dependency(request: Request) -> None:
        if not request.app.state.settings.rate_limit_enabled:
            return
        limiter: SlidingWindowLimiter = getattr(request.app.state.rate_limits, name)
        limiter.hit(client_ip(request))

    return dependency
