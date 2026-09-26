"""Demo polls with votes: "Which movie?" for a movie night, and a few on other activities.

Carla (the plain member) leaves the movie poll unanswered, so her backlog shows a "Vote" badge.
"""

from datetime import timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from friends_api.demo.context import DemoContext
from friends_api.features.activities import service as activities_service
from friends_api.features.activities.models import Activity, ActivityStatus
from friends_api.features.activities.schemas import ActivityCreate
from friends_api.features.activities.service import ActivityAccess
from friends_api.features.auth.models import User
from friends_api.features.polls import service as polls_service
from friends_api.features.polls.models import Poll, PollOption
from friends_api.features.polls.schemas import PollCreate, PollOptionCreate

_ACTIVE = (ActivityStatus.IDEA, ActivityStatus.PLANNING)


def _pick(ctx: DemoContext, category: str) -> Activity:
    """An idea or planned activity of the category (else any of it)."""
    in_category = [a for a in ctx.activities if a.category_id == ctx.categories[category].id]
    active = [a for a in in_category if a.status in _ACTIVE]
    return (active or in_category or ctx.activities)[0]


def _movie_night(db: Session, ctx: DemoContext, host: User) -> Activity:
    activity = activities_service.create_activity(
        db,
        ctx.access(host),
        ActivityCreate(
            title="Friday movie night",
            description="At Ana's place. Bring blankets.",
            category_id=ctx.categories["Movie night"].id,
            status=ActivityStatus.PLANNING,
            location_name="Ana's place",
        ),
    )
    created_at = ctx.now - timedelta(days=3)
    activity.created_at = activity.updated_at = activity.status_changed_at = created_at
    ctx.activities.append(activity)
    return activity


def _poll(
    db: Session,
    ctx: DemoContext,
    activity: Activity,
    creator: User,
    body: PollCreate,
    *,
    days_ago: float,
) -> tuple[Poll, list[PollOption]]:
    access = ActivityAccess(activity=activity, membership=ctx.memberships[creator.id])
    poll = polls_service.create_poll(db, access, body, now=ctx.now - timedelta(days=days_ago))
    options = db.scalars(
        select(PollOption).where(PollOption.poll_id == poll.id).order_by(PollOption.position)
    ).all()
    return poll, list(options)


def _vote(
    db: Session,
    ctx: DemoContext,
    poll: Poll,
    user: User,
    options: list[PollOption],
    *,
    days_ago: float,
) -> None:
    polls_service.replace_votes(
        db,
        poll,
        user.id,
        [option.id for option in options],
        now=ctx.now - timedelta(days=days_ago),
    )


def create_polls(db: Session, ctx: DemoContext) -> None:
    ana, bogdan, carla = ctx.users

    # "Which movie?": single choice, closes in two days; Carla hasn't voted yet.
    movie_night = _movie_night(db, ctx, ana)
    movie_category = ctx.categories["Movie night"].id
    movies = [a for a in ctx.activities if a.category_id == movie_category and a is not movie_night]
    picks = list(dict.fromkeys([a for a in movies if a.status in _ACTIVE] + movies))[:4]
    which_movie, options = _poll(
        db,
        ctx,
        movie_night,
        ana,
        PollCreate(
            question="Which movie?",
            closes_at=ctx.now + timedelta(days=2),
            options=[
                PollOptionCreate(label=movie.title, url=movie.attributes.get("imdb_url"))
                for movie in picks
            ],
        ),
        days_ago=2,
    )
    options.append(
        polls_service.insert_option(
            db,
            which_movie,
            bogdan.id,
            PollOptionCreate(label="Anything but horror"),
            now=ctx.now - timedelta(days=1.8),
        )
    )
    _vote(db, ctx, which_movie, ana, [options[0]], days_ago=1.9)
    _vote(db, ctx, which_movie, bogdan, [options[-1]], days_ago=1.7)

    # "Snacks?": multiple choice, everyone voted.
    snacks, options = _poll(
        db,
        ctx,
        movie_night,
        carla,
        PollCreate(
            question="Snacks?",
            allow_multiple=True,
            options=[
                PollOptionCreate(label="Popcorn"),
                PollOptionCreate(label="Nachos"),
                PollOptionCreate(label="Ice cream"),
            ],
        ),
        days_ago=1.5,
    )
    popcorn, nachos, ice_cream = options
    _vote(db, ctx, snacks, ana, [popcorn, nachos], days_ago=1.4)
    _vote(db, ctx, snacks, bogdan, [popcorn], days_ago=1.2)
    _vote(db, ctx, snacks, carla, [popcorn, ice_cream], days_ago=1.1)

    # "When should we go?": multiple choice without a closing time, on a trip.
    first_saturday = ctx.now.date() + timedelta(days=(5 - ctx.now.weekday()) % 7 + 14)
    weekends = [first_saturday + timedelta(weeks=week) for week in range(3)]
    when, options = _poll(
        db,
        ctx,
        _pick(ctx, "Trips"),
        bogdan,
        PollCreate(
            question="When should we go?",
            allow_multiple=True,
            options=[PollOptionCreate(label=f"Weekend of {day:%d %B}") for day in weekends],
        ),
        days_ago=6,
    )
    _vote(db, ctx, when, ana, options[:2], days_ago=5.5)
    _vote(db, ctx, when, bogdan, options[1:2], days_ago=5)
    _vote(db, ctx, when, carla, options[1:], days_ago=4)

    # "Which evening?": single choice, closed by the owner once everyone had voted.
    evening, options = _poll(
        db,
        ctx,
        _pick(ctx, "Restaurants"),
        carla,
        PollCreate(
            question="Which evening?",
            options=[PollOptionCreate(label="Friday"), PollOptionCreate(label="Saturday")],
        ),
        days_ago=10,
    )
    friday, saturday = options
    _vote(db, ctx, evening, ana, [friday], days_ago=9.5)
    _vote(db, ctx, evening, bogdan, [friday], days_ago=9)
    _vote(db, ctx, evening, carla, [saturday], days_ago=8.5)
    polls_service.close(db, evening, actor_id=ana.id, now=ctx.now - timedelta(days=8))
