from fastapi import APIRouter

from friends_api.features.auth.router import router as auth_router
from friends_api.features.health.router import router as health_router
from friends_api.features.users.router import router as users_router

API_PREFIX = "/api/v1"

api_router = APIRouter(prefix=API_PREFIX)
api_router.include_router(health_router)
api_router.include_router(auth_router)
api_router.include_router(users_router)
