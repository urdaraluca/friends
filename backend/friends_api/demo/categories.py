"""Demo subcategories, some with their own custom fields (the defaults come with the group)."""

from typing import Any

from sqlalchemy.orm import Session

from friends_api.demo.context import DemoContext
from friends_api.features.categories import service as categories_service
from friends_api.features.categories.schemas import CategoryWrite, FieldDef

# (parent, name, icon, own field_defs)
SUBCATEGORIES: list[tuple[str, str, str | None, list[dict[str, Any]]]] = [
    (
        "Movie night",
        "Classics",
        "star",
        [{"key": "director", "label": "Director", "type": "text", "show_on_card": True}],
    ),
    (
        "Food & drinks",
        "Restaurants",
        None,
        [
            {"key": "cuisine", "label": "Cuisine", "type": "text", "show_on_card": True},
            {"key": "booking_url", "label": "Booking link", "type": "url"},
        ],
    ),
    (
        "Outdoors",
        "Hiking",
        None,
        [
            {
                "key": "difficulty",
                "label": "Difficulty",
                "type": "select",
                "options": ["Easy", "Moderate", "Hard"],
                "show_on_card": True,
            },
            {
                "key": "distance_km",
                "label": "Distance (km)",
                "type": "number",
                "min": 0,
                "max": 100,
            },
        ],
    ),
    ("Outdoors", "Cycling", None, []),
    (
        "Games",
        "Board games",
        None,
        [{"key": "max_players", "label": "Max players", "type": "number", "min": 1, "max": 20}],
    ),
]


def create_subcategories(db: Session, ctx: DemoContext) -> None:
    for index, (parent_name, name, icon, field_defs) in enumerate(SUBCATEGORIES):
        creator = ctx.users[index % len(ctx.users)]
        category = categories_service.create_category(
            db,
            ctx.access(creator),
            CategoryWrite(
                name=name,
                parent_id=ctx.categories[parent_name].id,
                icon=icon,
                field_defs=[FieldDef.model_validate(raw) for raw in field_defs],
            ),
        )
        ctx.categories[category.name] = category
