from fastapi import APIRouter

from friends_api.features.health.router import router as health_router

API_PREFIX = "/api/v1"

api_router = APIRouter(prefix=API_PREFIX)
api_router.include_router(health_router)
