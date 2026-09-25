import pytest

from friends_api.core.errors import RateLimited
from friends_api.core.ratelimit import SlidingWindowLimiter


class FakeClock:
    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now


def test_allows_up_to_the_limit_then_rejects_with_retry_after() -> None:
    clock = FakeClock()
    limiter = SlidingWindowLimiter(3, 60, clock)

    for _ in range(3):
        limiter.hit("1.2.3.4")
        clock.now += 10
    with pytest.raises(RateLimited) as exc_info:
        limiter.hit("1.2.3.4")

    # The oldest hit (t=1000) leaves the window at t=1060; now is t=1030.
    assert exc_info.value.headers["Retry-After"] == "30"


def test_the_window_slides() -> None:
    clock = FakeClock()
    limiter = SlidingWindowLimiter(2, 60, clock)
    limiter.hit("k")
    clock.now += 30
    limiter.hit("k")

    clock.now += 31  # the first hit expired
    limiter.hit("k")

    with pytest.raises(RateLimited):
        limiter.hit("k")


def test_keys_are_independent() -> None:
    limiter = SlidingWindowLimiter(1, 60, FakeClock())
    limiter.hit("a")

    limiter.hit("b")

    with pytest.raises(RateLimited):
        limiter.hit("a")


def test_stale_keys_are_pruned() -> None:
    clock = FakeClock()
    limiter = SlidingWindowLimiter(1000, 1, clock)
    for i in range(999):
        limiter.hit(f"ip-{i}")
    clock.now += 5

    limiter.hit("trigger")  # the 1000th call prunes keys whose hits all expired

    assert set(limiter._hits) == {"trigger"}
