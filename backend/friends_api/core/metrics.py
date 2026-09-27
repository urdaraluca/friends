"""In-process metrics in the Prometheus text format (contract section 1.13).

Requests are counted by the request middleware, per method, route template and status, with a
latency histogram per route template. Route templates (``/events/{event_id}``), not
raw paths, keep the number of series bounded.
"""

import math
import threading
from collections import defaultdict
from collections.abc import Iterable

DURATION_BUCKETS = (0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0)
"""Seconds, for ``friends_http_request_duration_seconds``."""

CONTENT_TYPE = "text/plain; version=0.0.4; charset=utf-8"


def escape_label(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def labels(**values: str) -> str:
    """``{a="1",b="2"}``, or empty without labels."""
    if not values:
        return ""
    inner = ",".join(f'{key}="{escape_label(value)}"' for key, value in values.items())
    return "{" + inner + "}"


def number(value: float) -> str:
    if math.isinf(value):
        return "+Inf" if value > 0 else "-Inf"
    return repr(float(value)) if not float(value).is_integer() else str(int(value))


class RequestMetrics:
    """Thread-safe counters for the request middleware (uvicorn serves sync endpoints from a
    thread pool, but the middleware itself runs on the event loop)."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._requests: defaultdict[tuple[str, str, str], int] = defaultdict(int)
        self._buckets: defaultdict[str, list[int]] = defaultdict(
            lambda: [0] * len(DURATION_BUCKETS)
        )
        self._sums: defaultdict[str, float] = defaultdict(float)
        self._counts: defaultdict[str, int] = defaultdict(int)

    def observe(self, *, method: str, route: str, status: int, seconds: float) -> None:
        with self._lock:
            self._requests[method, route, str(status)] += 1
            buckets = self._buckets[route]
            for index, bound in enumerate(DURATION_BUCKETS):
                if seconds <= bound:
                    buckets[index] += 1
            self._sums[route] += seconds
            self._counts[route] += 1

    def lines(self) -> Iterable[str]:
        with self._lock:
            requests = sorted(self._requests.items())
            histograms = sorted(
                (route, list(buckets), self._sums[route], self._counts[route])
                for route, buckets in self._buckets.items()
            )
        yield "# HELP friends_http_requests_total HTTP requests, by method, route and status."
        yield "# TYPE friends_http_requests_total counter"
        for (method, route, status), count in requests:
            label_text = labels(method=method, route=route, status=status)
            yield f"friends_http_requests_total{label_text} {count}"
        yield "# HELP friends_http_request_duration_seconds HTTP request latency, by route."
        yield "# TYPE friends_http_request_duration_seconds histogram"
        for route, buckets, total, count in histograms:
            for bound, bucket_count in zip(DURATION_BUCKETS, buckets, strict=True):
                bucket = labels(route=route, le=number(bound))
                yield f"friends_http_request_duration_seconds_bucket{bucket} {bucket_count}"
            yield (
                f"friends_http_request_duration_seconds_bucket{labels(route=route, le='+Inf')} "
                f"{count}"
            )
            yield f"friends_http_request_duration_seconds_sum{labels(route=route)} {total!r}"
            yield f"friends_http_request_duration_seconds_count{labels(route=route)} {count}"


def gauge(name: str, help_text: str, samples: Iterable[tuple[dict[str, str], float]]) -> list[str]:
    """A gauge's ``# HELP``/``# TYPE`` lines and its samples."""
    lines = [f"# HELP {name} {help_text}", f"# TYPE {name} gauge"]
    lines += [
        f"{name}{labels(**sample_labels)} {number(value)}" for sample_labels, value in samples
    ]
    return lines
