"""Backlog filter and sort semantics (contract section 8.7).

``list_activities`` and the wheel (``WheelFilters``, contract section 10) share these, so the
wheel builds an :class:`ActivityFilters` from its request and reuses :func:`filter_activities`
instead of re-implementing any rule.
"""

import uuid
from collections.abc import Collection
from dataclasses import dataclass
from datetime import date
from typing import Any

from sqlalchemy import ColumnElement, Select, and_, exists, false, func, or_, select

from friends_api.features.activities.models import (
    MAX_ESTIMATED_COST,
    Activity,
    ActivityInterest,
    ActivityStatus,
)
from friends_api.features.activities.schemas import ActivitySort, SortOrder
from friends_api.features.categories.models import Category
from friends_api.features.groups.models import Group

DEFAULT_STATUSES: tuple[ActivityStatus, ...] = (
    ActivityStatus.IDEA,
    ActivityStatus.PLANNING,
    ActivityStatus.SCHEDULED,
)
"""``list_activities`` hides the archive (done, dropped) unless asked. The wheel has its own
default (idea, planning)."""


@dataclass(frozen=True, slots=True, kw_only=True)
class ActivityFilters:
    """Which activities of a group match. Unknown IDs simply match nothing."""

    statuses: Collection[ActivityStatus] = DEFAULT_STATUSES
    category_id: uuid.UUID | None = None
    include_subcategories: bool = True
    """With ``category_id``: also the activities in its subcategories."""
    owner_id: uuid.UUID | None = None
    interested_by: uuid.UUID | None = None
    cost_max: int | None = None
    """``estimated_cost <= cost_max`` in the group's currency (the raw number, per person or
    not)."""
    include_unpriced: bool = True
    """With ``cost_max``: also activities without a cost, or with another currency."""
    due_before: date | None = None
    """``due_date <= due_before`` (inclusive); activities without a due date are excluded."""
    q: str | None = None
    """Case-insensitive substring of the title."""


def filter_conditions(group: Group, filters: ActivityFilters) -> list[ColumnElement[bool]]:
    conditions: list[ColumnElement[bool]] = [Activity.group_id == group.id]
    statuses = list(dict.fromkeys(filters.statuses))
    conditions.append(Activity.status.in_(statuses) if statuses else false())
    if filters.category_id is not None:
        in_category = Activity.category_id == filters.category_id
        if filters.include_subcategories:
            subcategories = select(Category.id).where(
                Category.group_id == group.id, Category.parent_id == filters.category_id
            )
            in_category = or_(in_category, Activity.category_id.in_(subcategories))
        conditions.append(in_category)
    if filters.owner_id is not None:
        conditions.append(Activity.owner_id == filters.owner_id)
    if filters.interested_by is not None:
        conditions.append(
            exists().where(
                ActivityInterest.activity_id == Activity.id,
                ActivityInterest.user_id == filters.interested_by,
            )
        )
    if filters.cost_max is not None:
        # Costs never exceed MAX_ESTIMATED_COST; clamping keeps huge inputs bindable.
        priced = and_(
            Activity.estimated_cost <= min(filters.cost_max, MAX_ESTIMATED_COST),
            Activity.currency == group.currency,
        )
        if filters.include_unpriced:
            conditions.append(
                or_(
                    priced,
                    Activity.estimated_cost.is_(None),
                    Activity.currency != group.currency,
                )
            )
        else:
            conditions.append(priced)
    if filters.due_before is not None:
        conditions.append(Activity.due_date <= filters.due_before)  # NULL never matches
    if filters.q is not None:
        # LIKE with % and _ escaped; SQLite's LIKE is case-insensitive (ASCII).
        conditions.append(Activity.title.contains(filters.q, autoescape=True))
    return conditions


def filter_activities(group: Group, filters: ActivityFilters) -> Select[tuple[Activity]]:
    """``SELECT`` of the group's activities that match ``filters`` (unordered)."""
    return select(Activity).where(*filter_conditions(group, filters))


def interest_count_expression() -> ColumnElement[int]:
    return (
        select(func.count())
        .where(ActivityInterest.activity_id == Activity.id)
        .correlate(Activity)
        .scalar_subquery()
    )


def sort_clauses(
    sort: ActivitySort = ActivitySort.CREATED_AT, order: SortOrder = SortOrder.DESC
) -> list[Any]:
    """``ORDER BY`` for a sort: due date and cost put nulls last in both orders, titles sort
    case-insensitively (the column is NOCASE), and ties are broken by ``id`` descending so paging
    is stable."""
    key: Any
    match sort:
        case ActivitySort.CREATED_AT:
            key = Activity.created_at
        case ActivitySort.DUE_DATE:
            key = Activity.due_date
        case ActivitySort.TITLE:
            key = Activity.title
        case ActivitySort.INTEREST_COUNT:
            key = interest_count_expression()
        case ActivitySort.ESTIMATED_COST:
            key = Activity.estimated_cost
    ordered = key.asc() if order is SortOrder.ASC else key.desc()
    if sort in (ActivitySort.DUE_DATE, ActivitySort.ESTIMATED_COST):
        ordered = ordered.nulls_last()
    return [ordered, Activity.id.desc()]
