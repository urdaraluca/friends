from collections import Counter
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from friends_api import cli
from friends_api.core.config import AppEnv, Settings
from friends_api.core.db import create_db_engine
from friends_api.core.security import Passwords
from friends_api.demo import runner
from friends_api.demo.context import DEMO_EMAILS, DEMO_PASSWORD, DemoContext
from friends_api.features.activities.models import Activity, ActivityInterest, ActivityStatus
from friends_api.features.auth.models import User
from friends_api.features.auth.service import AuthContext
from friends_api.features.categories.models import Category
from friends_api.features.categories.service import CategoryIndex
from friends_api.features.groups.models import Group, Membership, Role
from friends_api.main import create_app
from tests.conftest import FAST_ARGON2


def test_seed_demo_creates_users_a_group_and_about_120_activities(
    settings: Settings, db_session: Session, capsys: pytest.CaptureFixture[str]
) -> None:
    assert cli.main(["seed-demo"], settings) == 0

    out = capsys.readouterr().out
    assert DEMO_PASSWORD in out
    assert all(email in out for email in DEMO_EMAILS)
    emails = db_session.scalars(select(User.email).order_by(User.email)).all()
    assert emails == list(DEMO_EMAILS)
    group = db_session.scalars(select(Group)).one()
    roles = db_session.scalars(select(Membership.role).where(Membership.group_id == group.id))
    assert sorted(roles) == sorted([Role.OWNER, Role.ADMIN, Role.MEMBER])

    categories = db_session.scalars(select(Category)).all()
    assert len(categories) == 12  # 7 defaults and 5 subcategories
    activities = db_session.scalars(select(Activity)).all()
    assert 100 <= len(activities) <= 140
    assert set(Counter(a.status for a in activities)) == set(ActivityStatus)
    index = CategoryIndex(categories)
    used = {a.category_id for a in activities}
    top_level_used = {(index.parent_of(c) or c).name for c in categories if c.id in used}
    assert top_level_used == {c.name for c in categories if c.parent_id is None}
    assert None in used  # some are uncategorized
    assert {c.name for c in categories if c.id in used} > {"Classics", "Hiking"}
    movies = [a for a in activities if a.attributes.get("imdb_rating") is not None]
    assert len(movies) >= 20
    assert any(a.owner_id is None for a in activities)
    assert any(a.estimated_cost is not None and a.currency == "RON" for a in activities)
    assert all(
        (a.completed_at is not None) == (a.status is ActivityStatus.DONE) for a in activities
    )
    interests = db_session.scalar(select(func.count()).select_from(ActivityInterest)) or 0
    assert interests > len(activities)  # creators plus other members

    with TestClient(create_app(settings)) as client:
        login = client.post(
            "/api/v1/auth/login", json={"email": DEMO_EMAILS[2], "password": DEMO_PASSWORD}
        )
        headers = {"Authorization": f"Bearer {login.json()['tokens']['access_token']}"}
        page = client.get(f"/api/v1/groups/{group.id}/activities", headers=headers)
    assert page.status_code == 200
    assert len(page.json()["items"]) == 50
    assert page.json()["next_cursor"] is not None


def test_seed_demo_refuses_to_run_twice(
    settings: Settings, capsys: pytest.CaptureFixture[str]
) -> None:
    assert cli.main(["seed-demo"], settings) == 0

    assert cli.main(["seed-demo"], settings) == 1
    assert "already exist" in capsys.readouterr().err


def test_seed_demo_refuses_in_prod(settings: Settings, db_session: Session) -> None:
    prod = Settings(
        _env_file=None,
        app_env=AppEnv.PROD,
        database_url=settings.database_url,
        jwt_secret="p" * 48,
        public_app_url="https://friends.example.com",
        **FAST_ARGON2,
    )

    assert cli.main(["seed-demo"], prod) == 2

    assert db_session.scalar(select(func.count()).select_from(User)) == 0


def _seed(tmp_path: Path, template: Path, name: str) -> list[tuple[Any, ...]]:
    path = tmp_path / name
    path.write_bytes(template.read_bytes())
    settings = Settings(_env_file=None, app_env=AppEnv.TEST, **FAST_ARGON2)
    engine = create_db_engine(f"sqlite:///{path.as_posix()}")
    auth = AuthContext(settings=settings, passwords=Passwords(settings))
    with Session(engine) as db:
        ctx = runner.seed_demo(db, auth, now=datetime(2026, 10, 1, tzinfo=UTC), seed=7)
        rows = [
            (a.title, a.status, a.due_date, a.estimated_cost, a.currency, a.created_at)
            for a in ctx.activities
        ]
        db.commit()
    engine.dispose()
    return rows


def test_seed_demo_is_deterministic(tmp_path: Path, migrated_template: Path) -> None:
    assert _seed(tmp_path, migrated_template, "a.db") == _seed(tmp_path, migrated_template, "b.db")


def test_later_features_add_steps(settings: Settings, monkeypatch: pytest.MonkeyPatch) -> None:
    seen: list[DemoContext] = []
    monkeypatch.setattr(runner, "STEPS", [*runner.STEPS, lambda db, ctx: seen.append(ctx)])

    assert cli.main(["seed-demo"], settings) == 0

    (ctx,) = seen
    assert [user.email for user in ctx.users] == list(DEMO_EMAILS)
    assert "Movie night" in ctx.categories
    assert "Hiking" in ctx.categories
    assert len(ctx.activities) >= 100
    assert ctx.access(ctx.users[1]).membership.role is Role.ADMIN
