from fastapi import APIRouter

from friends_api.features.activities.router import router as activities_router
from friends_api.features.auth.router import router as auth_router
from friends_api.features.categories.router import router as categories_router
from friends_api.features.groups.router import router as groups_router
from friends_api.features.health.router import router as health_router
from friends_api.features.invites.router import router as invites_router
from friends_api.features.users.router import router as users_router
from friends_api.features.wheel.router import router as wheel_router

API_PREFIX = "/api/v1"

api_router = APIRouter(prefix=API_PREFIX)
api_router.include_router(health_router)
api_router.include_router(auth_router)
api_router.include_router(users_router)
api_router.include_router(groups_router)
api_router.include_router(invites_router)
api_router.include_router(categories_router)
api_router.include_router(activities_router)
api_router.include_router(wheel_router)
