"""GET /api/v1/metrics (contract section 1.13, issue #18)."""

import os
import re
from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient

from friends_api.core.config import Settings
from friends_api.core.metrics import RequestMetrics, labels, number
from friends_api.main import create_app
from tests.factories import bearer, create_group, register

TOKEN = "scrape-me-" + "x" * 24
METRICS = "/api/v1/metrics"


@pytest.fixture
def scraped(settings: Settings) -> Iterator[TestClient]:
    with TestClient(create_app(settings.model_copy(update={"metrics_token": TOKEN}))) as client:
        yield client


def sample(text: str, name: str, **label_values: str) -> float | None:
    """The value of the sample ``name{labels}``, or None."""
    pattern = "^" + re.escape(name + labels(**label_values)) + r" (\S+)$"
    match = re.search(pattern, text, re.MULTILINE)
    return float(match.group(1)) if match else None


def test_metrics_are_off_without_a_token(client: TestClient) -> None:
    response = client.get(METRICS)

    assert response.status_code == 404
    assert response.json()["code"] == "not_found"


@pytest.mark.parametrize("header", [None, "Bearer wrong", f"Basic {TOKEN}", TOKEN])
def test_the_token_is_required(scraped: TestClient, header: str | None) -> None:
    headers = {"Authorization": header} if header else {}

    response = scraped.get(METRICS, headers=headers)

    assert response.status_code == 401
    assert response.json()["code"] == "unauthenticated"


def test_metrics_count_requests_rows_and_backups(scraped: TestClient, settings: Settings) -> None:
    ana = register(scraped)
    group = create_group(scraped, ana)
    scraped.get(f"/api/v1/groups/{group['id']}", headers=ana.headers)
    scraped.get("/api/v1/nothing-here")
    backups = settings.backup_dir
    backups.mkdir(parents=True)
    for name, mtime in (
        ("friends-20261001T031500Z.db.gz", 1_790_000_000),
        ("friends-20261002T031500Z.db.gz", 1_790_086_400),
    ):
        path = backups / name
        path.write_bytes(b"")
        os.utime(path, (mtime, mtime))
    (backups / "pre-migrate-20261001T000000Z.db.gz").write_bytes(b"")  # not a scheduled one

    response = scraped.get(METRICS, headers=bearer(TOKEN))

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/plain; version=0.0.4")
    text = response.text
    assert sample(text, "friends_build_info", version="test", git_sha="unknown") == 1
    assert sample(text, "friends_db_up") == 1
    assert sample(text, "friends_rows", table="users") == 1
    assert sample(text, "friends_rows", table="groups") == 1
    assert sample(text, "friends_backups") == 2
    assert sample(text, "friends_last_backup_timestamp_seconds") == 1_790_086_400
    route = "/groups/{group_id}"  # the template within the API, without /api/v1
    assert sample(text, "friends_http_requests_total", method="GET", route=route, status="200") == 1
    assert (
        sample(
            text,
            "friends_http_requests_total",
            method="GET",
            route="unmatched",
            status="404",
        )
        == 1
    )
    assert sample(text, "friends_http_request_duration_seconds_count", route=route) == 1
    assert sample(text, "friends_http_request_duration_seconds_bucket", route=route, le="+Inf") == 1
    assert "# TYPE friends_http_request_duration_seconds histogram" in text


def test_without_backups_there_is_no_timestamp(scraped: TestClient) -> None:
    text = scraped.get(METRICS, headers=bearer(TOKEN)).text

    assert sample(text, "friends_backups") == 0
    assert sample(text, "friends_last_backup_timestamp_seconds") is None


def test_request_metrics_buckets_and_formatting() -> None:
    metrics = RequestMetrics()
    metrics.observe(method="GET", route="/a", status=200, seconds=0.02)
    metrics.observe(method="GET", route="/a", status=200, seconds=3.0)

    lines = list(metrics.lines())

    assert 'friends_http_requests_total{method="GET",route="/a",status="200"} 2' in lines
    assert 'friends_http_request_duration_seconds_bucket{route="/a",le="0.025"} 1' in lines
    assert 'friends_http_request_duration_seconds_bucket{route="/a",le="5"} 2' in lines
    assert 'friends_http_request_duration_seconds_bucket{route="/a",le="+Inf"} 2' in lines
    assert labels(path='a "quoted"\\ value\n') == '{path="a \\"quoted\\"\\\\ value\\n"}'
    assert number(float("inf")) == "+Inf"
    assert number(0.5) == "0.5"
    assert number(3.0) == "3"
