"""The default categories seeded into a new group (contract section 6.5).

Kept apart from the categories service so ``groups.service.create_group`` can seed them without
an import cycle (the categories service depends on the groups service).
"""

import uuid
from typing import Any, Final

from sqlalchemy.orm import Session

from friends_api.features.categories.models import Category
from friends_api.features.group_log.service import log_event

MOVIE_NIGHT_FIELD_DEFS: Final[list[dict[str, Any]]] = [
    {
        "key": "genre",
        "label": "Genre",
        "type": "select",
        "options": [
            "Action",
            "Comedy",
            "Drama",
            "Horror",
            "Sci-fi",
            "Animation",
            "Documentary",
            "Thriller",
            "Romance",
            "Other",
        ],
        "min": None,
        "max": None,
        "show_on_card": False,
    },
    {
        "key": "imdb_rating",
        "label": "IMDb rating",
        "type": "rating",
        "options": None,
        "min": 0,
        "max": 10,
        "show_on_card": True,
    },
    {
        "key": "imdb_url",
        "label": "IMDb link",
        "type": "url",
        "options": None,
        "min": None,
        "max": None,
        "show_on_card": False,
    },
    {
        "key": "year",
        "label": "Year",
        "type": "year",
        "options": None,
        "min": None,
        "max": None,
        "show_on_card": False,
    },
    {
        "key": "runtime_min",
        "label": "Runtime (min)",
        "type": "number",
        "options": None,
        "min": 1,
        "max": 600,
        "show_on_card": False,
    },
]
"""Verbatim from the contract."""

DEFAULT_CATEGORIES: Final[list[tuple[str, str, str, list[dict[str, Any]]]]] = [
    # (name, color, icon, field_defs); the list index is the position.
    ("Movie night", "#7E57C2", "movie", MOVIE_NIGHT_FIELD_DEFS),
    ("Food & drinks", "#EF6C00", "food", []),
    ("Outdoors", "#2E7D32", "outdoors", []),
    ("Games", "#1565C0", "games", []),
    ("Trips", "#00838F", "trips", []),
    ("Culture", "#AD1457", "culture", []),
    ("Sports", "#C62828", "sports", []),
]


def seed_default_categories(
    db: Session, group_id: uuid.UUID, created_by_id: uuid.UUID | None
) -> list[Category]:
    """Adds the 7 top-level defaults, each logged as ``category.created`` by ``created_by_id``
    like any other category (contract sections 1.7, 3.2). Flushes; the caller commits."""
    categories = [
        Category(
            group_id=group_id,
            parent_id=None,
            name=name,
            color=color,
            icon=icon,
            position=position,
            field_defs=[dict(field_def) for field_def in field_defs],
            created_by_id=created_by_id,
        )
        for position, (name, color, icon, field_defs) in enumerate(DEFAULT_CATEGORIES)
    ]
    db.add_all(categories)
    db.flush()
    for category in categories:
        log_event(
            db,
            group_id=group_id,
            actor_id=created_by_id,
            action="category.created",
            subject_type="category",
            subject_id=category.id,
            data={"name": category.name},
        )
    db.flush()
    return categories
