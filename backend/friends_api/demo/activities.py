"""About 120 demo activities across every status and category, and the members' interests."""

from dataclasses import dataclass, field
from datetime import date, timedelta
from typing import Any
from urllib.parse import quote_plus

from sqlalchemy.orm import Session

from friends_api.demo.context import DemoContext
from friends_api.features.activities import service as activities_service
from friends_api.features.activities.models import Activity, ActivityStatus
from friends_api.features.activities.schemas import ActivityCreate, Link


@dataclass(frozen=True, slots=True)
class Idea:
    title: str
    attributes: dict[str, Any] = field(default_factory=dict)
    location: str | None = None


def _movie(title: str, genre: str, year: int, rating: float, runtime: int) -> Idea:
    return Idea(
        title,
        {
            "genre": genre,
            "imdb_rating": rating,
            "imdb_url": f"https://www.imdb.com/find/?q={quote_plus(title)}",
            "year": year,
            "runtime_min": runtime,
        },
    )


def _classic(title: str, genre: str, year: int, rating: float, runtime: int, director: str) -> Idea:
    movie = _movie(title, genre, year, rating, runtime)
    return Idea(title, {**movie.attributes, "director": director})


# Category name (None = uncategorized) -> (ideas, typical cost range in EUR or None).
IDEAS: dict[str | None, tuple[list[Idea], tuple[int, int] | None]] = {
    "Movie night": (
        [
            _movie("Inception", "Sci-fi", 2010, 8.8, 148),
            _movie("Spirited Away", "Animation", 2001, 8.6, 125),
            _movie("The Grand Budapest Hotel", "Comedy", 2014, 8.1, 99),
            _movie("Parasite", "Thriller", 2019, 8.5, 132),
            _movie("Mad Max: Fury Road", "Action", 2015, 8.1, 120),
            _movie("Get Out", "Horror", 2017, 7.8, 104),
            _movie("La La Land", "Romance", 2016, 8.0, 128),
            _movie("Arrival", "Sci-fi", 2016, 7.9, 116),
            _movie("Coco", "Animation", 2017, 8.4, 105),
            _movie("Knives Out", "Thriller", 2019, 7.9, 130),
            _movie("Free Solo", "Documentary", 2018, 8.1, 100),
            _movie("The Social Network", "Drama", 2010, 7.8, 120),
            _movie("Everything Everywhere All at Once", "Action", 2022, 7.8, 139),
            _movie("Dune", "Sci-fi", 2021, 8.0, 155),
            _movie("Paddington 2", "Comedy", 2017, 7.8, 103),
            _movie("Whiplash", "Drama", 2014, 8.5, 106),
            _movie("A Quiet Place", "Horror", 2018, 7.5, 90),
            _movie("Up", "Animation", 2009, 8.3, 96),
            _movie("Amélie", "Romance", 2001, 8.3, 122),
            _movie("My Octopus Teacher", "Documentary", 2020, 8.1, 85),
        ],
        (8, 15),
    ),
    "Classics": (
        [
            _classic("Casablanca", "Romance", 1942, 8.5, 102, "Michael Curtiz"),
            _classic("12 Angry Men", "Drama", 1957, 9.0, 96, "Sidney Lumet"),
            _classic("Psycho", "Horror", 1960, 8.5, 109, "Alfred Hitchcock"),
            _classic("Some Like It Hot", "Comedy", 1959, 8.2, 121, "Billy Wilder"),
            _classic("The Godfather", "Drama", 1972, 9.2, 175, "Francis Ford Coppola"),
            _classic("Seven Samurai", "Action", 1954, 8.6, 207, "Akira Kurosawa"),
            _classic("Singin' in the Rain", "Romance", 1952, 8.3, 103, "Stanley Donen"),
            _classic("2001: A Space Odyssey", "Sci-fi", 1968, 8.3, 149, "Stanley Kubrick"),
        ],
        None,
    ),
    "Food & drinks": (
        [
            Idea("Homemade pizza night"),
            Idea("Wine tasting evening"),
            Idea("Sunday brunch at someone's place"),
            Idea("Street food festival", location="Old town square"),
            Idea("Cook a Thai curry together"),
            Idea("Cocktail workshop"),
            Idea("Farmers' market breakfast", location="Farmers' market"),
            Idea("Dumpling-making party"),
            Idea("Chocolate factory tour"),
            Idea("Baking bread workshop"),
            Idea("Vegan cooking challenge"),
        ],
        (10, 45),
    ),
    "Restaurants": (
        [
            Idea("Try the new ramen bar", {"cuisine": "Japanese"}),
            Idea("Dinner at the Italian trattoria", {"cuisine": "Italian"}),
            Idea("Tapas night", {"cuisine": "Spanish"}),
            Idea("Lebanese mezze feast", {"cuisine": "Lebanese"}),
            Idea("Burger crawl", {"cuisine": "American"}),
            Idea("Grandma-style Romanian lunch", {"cuisine": "Romanian"}),
        ],
        (20, 70),
    ),
    "Outdoors": (
        [
            Idea("Picnic by the lake", location="Lakeside park"),
            Idea("Stargazing night"),
            Idea("Kayaking on the river"),
            Idea("Sunrise at the viewpoint"),
            Idea("Botanical garden walk", location="Botanical garden"),
            Idea("Campfire and s'mores"),
            Idea("Paddleboarding"),
            Idea("Mushroom foraging walk"),
            Idea("Hot-air balloon ride"),
        ],
        None,
    ),
    "Hiking": (
        [
            Idea("Hike to the waterfall", {"difficulty": "Easy", "distance_km": 8}),
            Idea("Two-peak ridge hike", {"difficulty": "Hard", "distance_km": 18.5}),
            Idea("Forest loop trail", {"difficulty": "Easy", "distance_km": 6}),
            Idea("Canyon hike", {"difficulty": "Moderate", "distance_km": 12}),
            Idea("Via ferrata taster", {"difficulty": "Hard", "distance_km": 5}),
            Idea("Lakes circuit", {"difficulty": "Moderate", "distance_km": 14}),
        ],
        None,
    ),
    "Cycling": (
        [
            Idea("Bike ride along the river"),
            Idea("Vineyard cycling tour"),
            Idea("Night bike ride through the city"),
            Idea("Gravel ride to the monastery"),
        ],
        (0, 25),
    ),
    "Games": (
        [
            Idea("Escape room: The Lab"),
            Idea("Bowling night"),
            Idea("Karaoke night"),
            Idea("Poker night"),
            Idea("Pub quiz"),
            Idea("Laser tag"),
            Idea("Retro arcade evening"),
            Idea("Mini golf"),
            Idea("VR arcade"),
            Idea("Billiards night"),
        ],
        (8, 35),
    ),
    "Board games": (
        [
            Idea("Catan tournament", {"max_players": 4}),
            Idea("Try Wingspan", {"max_players": 5}),
            Idea("Codenames marathon", {"max_players": 8}),
            Idea("Pandemic Legacy campaign", {"max_players": 4}),
            Idea("Ticket to Ride evening", {"max_players": 5}),
            Idea("Werewolf with the whole group", {"max_players": 16}),
        ],
        None,
    ),
    "Trips": (
        [
            Idea("Weekend in Vienna", location="Vienna"),
            Idea("Road trip to the seaside"),
            Idea("Mountain cabin weekend"),
            Idea("Danube Delta boat trip", location="Danube Delta"),
            Idea("Christmas market trip"),
            Idea("Wine region weekend"),
            Idea("City break in Lisbon", location="Lisbon"),
            Idea("Castle tour"),
            Idea("Hot springs day trip"),
            Idea("Train trip to the mountains"),
            Idea("Camping by the sea"),
        ],
        (80, 600),
    ),
    "Culture": (
        [
            Idea("Modern art museum"),
            Idea("Jazz concert"),
            Idea("Stand-up comedy show"),
            Idea("Theatre premiere"),
            Idea("Photography exhibition"),
            Idea("Open-air cinema"),
            Idea("Opera night", location="National Opera"),
            Idea("Book club: pick a novel"),
            Idea("Pottery class"),
            Idea("Street art tour"),
            Idea("Classical music matinee"),
            Idea("Film festival day"),
        ],
        (10, 80),
    ),
    "Sports": (
        [
            Idea("5-a-side football"),
            Idea("Climbing gym session"),
            Idea("Tennis doubles"),
            Idea("Beach volleyball"),
            Idea("Run a 10k together"),
            Idea("Ice skating"),
            Idea("Yoga in the park"),
            Idea("Padel match"),
            Idea("Swimming morning"),
            Idea("Ski day"),
            Idea("Frisbee in the park"),
        ],
        (5, 30),
    ),
    None: (
        [
            Idea("Learn to juggle"),
            Idea("Volunteer at the animal shelter"),
            Idea("Plan a surprise party"),
            Idea("Photo walk downtown"),
            Idea("Try a dance class"),
            Idea("Game-jam weekend"),
            Idea("Paint-and-sip evening"),
            Idea("Learn basic sign language"),
            Idea("Clean-up day at the park"),
        ],
        (0, 30),
    ),
}

STATUS_WEIGHTS = {
    ActivityStatus.IDEA: 40,
    ActivityStatus.PLANNING: 20,
    ActivityStatus.SCHEDULED: 15,
    ActivityStatus.DONE: 18,
    ActivityStatus.DROPPED: 7,
}


def _body(
    ctx: DemoContext, category: str | None, idea: Idea, cost_range: tuple[int, int] | None
) -> ActivityCreate:
    rng = ctx.rng
    status = rng.choices(list(STATUS_WEIGHTS), weights=list(STATUS_WEIGHTS.values()))[0]
    cost = currency = None
    if cost_range is not None and rng.random() < 0.7:
        cost = rng.randint(*cost_range)
        currency = "RON" if rng.random() < 0.15 else None  # else the group's (EUR)
        if currency == "RON":
            cost *= 5
    due_date: date | None = None
    if rng.random() < 0.3:
        offset = rng.randint(-30, -1) if status is ActivityStatus.DONE else rng.randint(-5, 120)
        due_date = ctx.now.date() + timedelta(days=offset)
    links = []
    if idea.location and rng.random() < 0.6:
        links.append(
            Link(
                url=f"https://www.openstreetmap.org/search?query={quote_plus(idea.location)}",
                label="Map",
            )
        )
    owner = rng.choice(ctx.users)
    return ActivityCreate(
        title=idea.title,
        description=rng.choice([None, None, f"{idea.title}, because why not?"]),
        category_id=ctx.categories[category].id if category else None,
        owner_id=owner.id,
        due_date=due_date,
        estimated_cost=cost,
        currency=currency,
        cost_per_person=rng.random() < 0.8,
        location_name=idea.location,
        links=links,
        attributes=idea.attributes,
        status=status,
    )


def create_activities(db: Session, ctx: DemoContext) -> None:
    rng = ctx.rng
    for category, (ideas, cost_range) in IDEAS.items():
        for idea in ideas:
            body = _body(ctx, category, idea, cost_range)
            creator = rng.choice(ctx.users)
            activity = activities_service.create_activity(db, ctx.access(creator), body)
            if rng.random() < 0.3:
                activity.owner_id = None  # unowned: anyone may claim it
            _backdate(ctx, activity)
            ctx.activities.append(activity)
    db.flush()


def _backdate(ctx: DemoContext, activity: Activity) -> None:
    """Spread creation over the last year, and status changes after that."""
    created_at = ctx.now - timedelta(days=ctx.rng.uniform(0.5, 360))
    changed_at = created_at
    if activity.status is not ActivityStatus.IDEA:
        changed_at = created_at + (ctx.now - created_at) * ctx.rng.random()
    activity.created_at = created_at
    activity.updated_at = changed_at
    activity.status_changed_at = changed_at
    activity.completed_at = changed_at if activity.status is ActivityStatus.DONE else None


def add_interests(db: Session, ctx: DemoContext) -> None:
    """Besides the creator (interested automatically), each member likes about 40% of ideas."""
    for activity in ctx.activities:
        for user in ctx.users:
            if user.id != activity.created_by_id and ctx.rng.random() < 0.4:
                activities_service.mark_interested(db, activity, user.id)
