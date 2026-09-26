"""Same-origin hosting: web build, SPA fallback, assetlinks.json, API 404s (contract 1.1)."""

import errno
import logging
import os
import uuid
from collections.abc import Callable, Iterator
from pathlib import Path

import httpx2
import pytest
from fastapi.testclient import TestClient
from starlette.staticfiles import StaticFiles
from starlette.websockets import WebSocketDisconnect

from friends_api.core.config import Settings
from friends_api.main import create_app

PROBLEM = "application/problem+json"
INDEX_HTML = '<!DOCTYPE html><html><head><base href="/"></head><body><script src="flutter_bootstrap.js" async></script></body></html>'
BOOTSTRAP_JS = "_flutter.loader.load();"
MAIN_JS = "(function dartProgram(){})();"
PNG = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR"
WEB_FILES = {
    "index.html": INDEX_HTML.encode(),
    "flutter_bootstrap.js": BOOTSTRAP_JS.encode(),
    "main.dart.js": MAIN_JS.encode(),
    "assets/x.png": PNG,
}
FINGERPRINTS = [
    "14:6D:E9:83:C5:73:06:50:D8:EE:B9:95:2F:34:FC:64:16:A0:83:42:E6:1D:BE:A8:8A:04:96:B2:3F:CF:44:E5",
    "AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89",
]


def assert_problem(response: httpx2.Response, status: int, code: str) -> None:
    assert response.status_code == status
    assert response.headers["content-type"] == PROBLEM
    assert response.json()["code"] == code


@pytest.fixture
def web_dir(tmp_path: Path) -> Path:
    root = tmp_path / "web"
    (root / "assets").mkdir(parents=True)
    for name, content in WEB_FILES.items():
        (root / name).write_bytes(content)
    return root


def _client(settings: Settings, **overrides: object) -> TestClient:
    return TestClient(create_app(settings.model_copy(update=overrides)))


@pytest.fixture
def web(settings: Settings, web_dir: Path) -> Iterator[TestClient]:
    with _client(settings, web_dir=web_dir) as client:
        yield client


# --- the web build --------------------------------------------------------------------------


@pytest.mark.parametrize(
    "path",
    [
        "/",
        "/join/ABCDEFGHJK",
        f"/groups/{uuid.uuid7()}/backlog",
        "/groups/",
        "/assets",
        # The last segment of the resolved path counts: "/join/ABCDEFGHJK/." is /join/ABCDEFGHJK.
        "/join/ABCDEFGHJK/%2E",
    ],
)
def test_app_routes_get_the_app_shell(web: TestClient, path: str) -> None:
    response = web.get(path)

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/html")
    assert response.text == INDEX_HTML
    assert response.headers["cache-control"] == "no-cache"


def test_existing_files_are_served_as_is(web: TestClient) -> None:
    response = web.get("/assets/x.png")

    assert response.status_code == 200
    assert response.content == PNG
    assert response.headers["content-type"] == "image/png"
    assert "etag" in response.headers
    assert "last-modified" in response.headers


@pytest.mark.parametrize("name", list(WEB_FILES))
def test_every_file_of_the_web_build_is_always_revalidated(web: TestClient, name: str) -> None:
    # Flutter's file names carry no content hash: flutter_bootstrap.js loads main.dart.js,
    # canvaskit/ and assets/ by fixed names. Cached heuristically, they would outlive a release.
    response = web.get(f"/{name}")

    assert response.status_code == 200
    assert response.content == WEB_FILES[name]
    assert response.headers["cache-control"] == "no-cache"


@pytest.mark.parametrize(
    ("path", "name"),
    [
        ("/index.html/", "index.html"),
        ("/index.html/%2E", "index.html"),
        ("/flutter_bootstrap.js/", "flutter_bootstrap.js"),
        ("/assets/%2E%2E/main.dart.js", "main.dart.js"),
    ],
)
def test_other_spellings_of_a_file_path_are_revalidated_too(
    web: TestClient, path: str, name: str
) -> None:
    # The file lookup normalises the path ("%2E" is "."), so these are the files themselves.
    response = web.get(path)

    assert response.status_code == 200
    assert response.content == WEB_FILES[name]
    assert response.headers["cache-control"] == "no-cache"


@pytest.mark.parametrize(
    ("first", "second"),
    [
        ("/join/ABCDEFGHJK", "/groups/abc/backlog"),
        ("/main.dart.js", "/main.dart.js"),
        ("/assets/x.png", "/assets/x.png"),
    ],
)
def test_revalidating_gets_a_304_that_stays_no_cache(
    web: TestClient, first: str, second: str
) -> None:
    etag = web.get(first).headers["etag"]

    response = web.get(second, headers={"If-None-Match": etag})

    assert response.status_code == 304
    assert response.headers["cache-control"] == "no-cache"


@pytest.mark.parametrize(
    ("path", "length"), [("/join/ABCDEFGHJK", len(INDEX_HTML)), ("/assets/x.png", len(PNG))]
)
def test_head_is_answered_like_get_without_a_body(web: TestClient, path: str, length: int) -> None:
    response = web.head(path)

    assert response.status_code == 200
    assert response.headers["content-length"] == str(length)
    assert response.content == b""


@pytest.mark.parametrize(
    "path", ["/missing.js", "/assets/nope.png", "/join/ABCDEFGHJK/x.map", "/.well-known/x.json"]
)
def test_missing_files_with_an_extension_are_404(web: TestClient, path: str) -> None:
    assert_problem(web.get(path), 404, "not_found")


def test_files_outside_the_web_dir_are_never_served(web: TestClient, tmp_path: Path) -> None:
    (tmp_path / "secret.txt").write_text("secret", encoding="utf-8")

    response = web.get("/..%2Fsecret.txt")

    assert_problem(response, 404, "not_found")


@pytest.mark.parametrize(
    ("method", "path"),
    [
        ("POST", "/join/ABCDEFGHJK"),
        ("PUT", "/"),
        ("DELETE", "/index.html"),
        ("PATCH", "/assets/x.png"),
        ("OPTIONS", "/"),
    ],
)
def test_other_methods_outside_the_api_are_405(web: TestClient, method: str, path: str) -> None:
    response = web.request(method, path)

    assert_problem(response, 405, "method_not_allowed")
    assert response.headers["allow"] == "GET, HEAD"


def test_static_requests_are_access_logged(
    web: TestClient, caplog: pytest.LogCaptureFixture
) -> None:
    with caplog.at_level(logging.INFO, logger="friends_api.access"):
        web.get("/join/ABCDEFGHJK")

    messages = [r.getMessage() for r in caplog.records if r.name == "friends_api.access"]
    assert any(m.startswith("GET /join/ABCDEFGHJK 200 ") for m in messages)


def test_static_requests_are_not_rate_limited(settings: Settings, web_dir: Path) -> None:
    with _client(settings, web_dir=web_dir, rate_limit_enabled=True) as client:
        statuses = {client.get("/join/ABCDEFGHJK").status_code for _ in range(40)}

    assert statuses == {200}


def test_websockets_are_refused(web: TestClient) -> None:
    with pytest.raises(WebSocketDisconnect), web.websocket_connect("/ws"):
        pass  # pragma: no cover


# --- no web build ---------------------------------------------------------------------------


@pytest.mark.parametrize("path", ["/", "/join/ABCDEFGHJK", "/index.html"])
def test_without_a_web_build_other_paths_are_404(client: TestClient, path: str) -> None:
    assert_problem(client.get(path), 404, "not_found")


def test_a_web_dir_without_index_html_is_not_served(settings: Settings, web_dir: Path) -> None:
    (web_dir / "index.html").unlink()

    with _client(settings, web_dir=web_dir) as client:
        assert_problem(client.get("/flutter_bootstrap.js"), 404, "not_found")
        assert_problem(client.get("/join/ABCDEFGHJK"), 404, "not_found")


def test_without_a_web_build_other_methods_are_still_405(client: TestClient) -> None:
    assert_problem(client.post("/join/ABCDEFGHJK"), 405, "method_not_allowed")


# --- the API never answers with HTML ---------------------------------------------------------


@pytest.mark.parametrize(
    "path",
    [
        "/api/v1/nope",
        "/api/v2/health",
        "/api/v1/health/extra",
        "/api",
        "/api/",
        # Other spellings of an /api path (uvicorn passes paths on unnormalised); "%2F" and "%2E"
        # decode to "/" and ".", and httpx would normalise the literal forms before sending.
        "/%2Fapi/v1/nope",
        "/%2Fapi/v1/health",
        "/%2E/api/v1/nope",
        "/join/%2E%2E/api",
        # As sent, it is under /api: still never the app shell.
        "/api/%2E%2E/join/ABCDEFGHJK",
    ],
)
def test_unknown_api_paths_are_a_problem_404(web: TestClient, path: str) -> None:
    response = web.get(path)

    assert_problem(response, 404, "not_found")
    assert response.headers["cache-control"] == "no-store"


def test_a_double_slash_before_api_is_still_the_api(web: TestClient) -> None:
    # A client whose base URL ends in "/" sends "//api/v1/...". httpx would read "//api" as a
    # host, so the raw path is set explicitly.
    url = httpx2.URL("http://testserver").copy_with(raw_path=b"//api/v1/health")

    response = web.get(url)

    assert_problem(response, 404, "not_found")
    assert response.headers["cache-control"] == "no-store"


def test_any_method_on_an_unknown_api_path_is_404(web: TestClient) -> None:
    assert_problem(web.post("/api/v2/things", json={}), 404, "not_found")


def test_wrong_method_on_a_known_api_path_is_405(web: TestClient) -> None:
    response = web.post("/api/v1/health")

    assert_problem(response, 405, "method_not_allowed")
    assert response.headers["cache-control"] == "no-store"


def test_api_responses_are_unchanged_next_to_the_web_build(web: TestClient) -> None:
    response = web.get("/api/v1/health")

    assert response.status_code == 200
    assert response.json()["status"] == "ok"
    assert response.headers["cache-control"] == "no-store"


def test_web_routes_are_not_in_the_openapi_schema(web: TestClient) -> None:
    paths = web.get("/api/v1/openapi.json").json()["paths"]

    assert paths
    assert all(path.startswith("/api/v1/") for path in paths)


# --- /.well-known/assetlinks.json -----------------------------------------------------------


def test_assetlinks_lists_the_configured_fingerprints(settings: Settings) -> None:
    with _client(settings, android_cert_sha256=FINGERPRINTS) as client:
        response = client.get("/.well-known/assetlinks.json")
        head = client.head("/.well-known/assetlinks.json")

    assert response.status_code == 200
    assert response.headers["content-type"] == "application/json"
    assert response.json() == [
        {
            "relation": ["delegate_permission/common.handle_all_urls"],
            "target": {
                "namespace": "android_app",
                "package_name": "io.github.urdaraluca.friends",
                "sha256_cert_fingerprints": FINGERPRINTS,
            },
        }
    ]
    assert head.status_code == 200


def test_assetlinks_is_a_problem_404_without_fingerprints(client: TestClient) -> None:
    assert_problem(client.get("/.well-known/assetlinks.json"), 404, "not_found")


def test_assetlinks_only_answers_get_and_head(settings: Settings) -> None:
    with _client(settings, android_cert_sha256=FINGERPRINTS) as client:
        response = client.post("/.well-known/assetlinks.json")

    assert_problem(response, 405, "method_not_allowed")


# --- file-system edge cases -----------------------------------------------------------------


def _lookup_failing_with(error: int) -> Callable[[StaticFiles, str], tuple[str, object]]:
    original = StaticFiles.lookup_path

    def lookup_path(self: StaticFiles, path: str) -> tuple[str, object]:
        if "bad" in path:
            raise OSError(error, os.strerror(error))
        return original(self, path)

    return lookup_path


@pytest.mark.parametrize(("path", "status"), [("/bad*name", 200), ("/bad*name.js", 404)])
def test_names_the_os_cannot_look_up_are_missing_files(
    web: TestClient, monkeypatch: pytest.MonkeyPatch, path: str, status: int
) -> None:
    # e.g. "*" in a file name is an invalid argument (EINVAL) on Windows.
    monkeypatch.setattr(StaticFiles, "lookup_path", _lookup_failing_with(errno.EINVAL))

    assert web.get(path).status_code == status


def test_other_file_system_errors_are_not_hidden(
    web: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(StaticFiles, "lookup_path", _lookup_failing_with(errno.EIO))

    assert_problem(web.get("/bad.js"), 500, "internal_error")
