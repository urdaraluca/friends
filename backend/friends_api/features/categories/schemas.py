import math
import uuid
from datetime import datetime
from enum import StrEnum
from typing import Annotated

from pydantic import BaseModel, Field, StringConstraints, ValidationInfo, field_validator
from pydantic_core import PydanticCustomError

from friends_api.core.schemas import Color, RequestModel
from friends_api.features.users.schemas import UserPublic

MAX_OWN_FIELD_DEFS = 12
MAX_POSITION = 1_000_000
"""Contract section 1.9; also keeps positions far from SQLite's 64-bit integer limit."""
RATING_MIN, RATING_MAX = 0.0, 10.0
YEAR_MIN, YEAR_MAX = 1800, 2200


class FieldType(StrEnum):
    TEXT = "text"
    LONG_TEXT = "long_text"
    NUMBER = "number"
    RATING = "rating"
    URL = "url"
    SELECT = "select"
    YEAR = "year"


FieldKey = Annotated[str, StringConstraints(pattern=r"^[a-z][a-z0-9_]{0,29}$")]
FieldLabel = Annotated[str, StringConstraints(min_length=1, max_length=40)]
OptionLabel = Annotated[str, StringConstraints(min_length=1, max_length=40)]
CategoryName = Annotated[str, StringConstraints(min_length=1, max_length=40)]
IconKey = Annotated[str, StringConstraints(max_length=40)]


class FieldDef(RequestModel):
    """A custom field of a category (contract section 6.1). The list order is the display order.

    Shape rules are checked here, so errors point at e.g. ``field_defs.2.options``. Rules that
    need other categories (key conflicts, type changes) are checked by the service.
    """

    key: FieldKey
    label: FieldLabel
    type: FieldType
    options: list[OptionLabel] | None = Field(
        default=None, min_length=1, max_length=30, validate_default=True
    )
    """Select only (required there): unique case-insensitively. Null for other types."""
    min: float | None = None
    """Number and rating only. A rating's bounds lie within 0..10 (default 0 and 10)."""
    max: float | None = None
    """Number and rating only; ``min < max`` when both are set."""
    show_on_card: bool = False

    @field_validator("options")
    @classmethod
    def _options_only_for_select(
        cls, value: list[str] | None, info: ValidationInfo
    ) -> list[str] | None:
        kind = info.data.get("type")
        if kind is None:  # the type itself is invalid and reported on its own
            return value
        if kind is not FieldType.SELECT:
            if value is not None:
                raise ValueError("only select fields have options")
            return value
        if value is None:
            raise PydanticCustomError("missing", "A select field needs options.")
        folded = [option.casefold() for option in value]
        if len(set(folded)) != len(folded):
            raise ValueError("options must be unique (case-insensitive)")
        return value

    @field_validator("min", "max")
    @classmethod
    def _bounds(cls, value: float | None, info: ValidationInfo) -> float | None:
        kind = info.data.get("type")
        if value is None or kind is None:
            return value
        if kind not in (FieldType.NUMBER, FieldType.RATING):
            raise ValueError("only number and rating fields have min and max")
        if not math.isfinite(value):
            raise ValueError("must be a finite number")
        if kind is FieldType.RATING and not RATING_MIN <= value <= RATING_MAX:
            raise ValueError("a rating's bounds must lie within 0..10")
        if info.field_name == "min" and kind is FieldType.RATING and value >= RATING_MAX:
            raise ValueError("min must be less than max")
        if info.field_name == "max":
            low = info.data.get("min")
            if low is None and kind is FieldType.RATING:
                low = RATING_MIN
            if low is not None and low >= value:
                raise ValueError("min must be less than max")
        return value


class Category(BaseModel):
    id: uuid.UUID
    group_id: uuid.UUID
    parent_id: uuid.UUID | None
    name: str
    color: str | None
    """Own color; null on a subcategory means it inherits the parent's."""
    effective_color: str | None
    """Own color, else the parent's."""
    icon: str | None
    position: int
    field_defs: list[FieldDef]
    """Own definitions."""
    effective_field_defs: list[FieldDef]
    """The parent's definitions followed by the own ones (== field_defs for top-level)."""
    created_by: UserPublic | None
    can_edit: bool
    can_delete: bool
    created_at: datetime
    updated_at: datetime


class CategoryNode(Category):
    subcategories: list[Category]


class CategoryWrite(RequestModel):
    name: CategoryName
    parent_id: uuid.UUID | None = None
    color: Color | None = Field(default=None, validate_default=True)
    """Required for a top-level category (``parent_id`` null)."""
    icon: IconKey | None = None
    position: int | None = Field(default=None, ge=0, le=MAX_POSITION)
    """0..1,000,000. Null: append at the end among siblings on create (capped at the maximum),
    keep the current one on update."""
    field_defs: list[FieldDef] = Field(default_factory=list, max_length=MAX_OWN_FIELD_DEFS)

    @field_validator("color")
    @classmethod
    def _top_level_needs_color(cls, value: str | None, info: ValidationInfo) -> str | None:
        if value is None and "parent_id" in info.data and info.data["parent_id"] is None:
            raise PydanticCustomError("missing", "A top-level category needs a color.")
        return value


class CategoryOrder(RequestModel):
    parent_id: uuid.UUID | None = None
    """Whose subcategories to order; null for the top-level categories."""
    category_ids: list[uuid.UUID] = Field(max_length=100)
    """Every one of them, exactly once, in the new order (a group has at most 100)."""
