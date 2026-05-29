from fastapi import APIRouter

from app.api.routes.auth import router as auth_router
from app.api.routes.ai import router as ai_router
from app.api.routes.debug import router as debug_router
from app.api.routes.dungeons import router as dungeons_router
from app.api.routes.health import router as health_router
from app.api.routes.integrations_notion import router as integrations_notion_router
from app.api.routes.leaderboard import router as leaderboard_router
from app.api.routes.profile import router as profile_router
from app.api.routes.quests import router as quests_router
from app.api.routes.stats import router as stats_router
from app.api.routes.task_candidates import router as task_candidates_router
from app.api.routes.task_intake import router as task_intake_router
from app.api.routes.tasks import router as tasks_router

router = APIRouter()
router.include_router(auth_router, tags=["auth"])
router.include_router(health_router, tags=["health"])
router.include_router(debug_router, tags=["debug"])
router.include_router(ai_router, prefix="/ai", tags=["ai", "quests"])
router.include_router(dungeons_router, tags=["dungeons"])
router.include_router(task_intake_router, prefix="/task-intake", tags=["task-intake"])
router.include_router(tasks_router, prefix="/tasks", tags=["tasks"])
router.include_router(
    task_candidates_router,
    prefix="/task-candidates",
    tags=["task-candidates"],
)
router.include_router(quests_router, prefix="/quests", tags=["quests"])
router.include_router(profile_router, tags=["profile"])
router.include_router(stats_router, tags=["stats"])
router.include_router(leaderboard_router, tags=["leaderboard"])
router.include_router(
    integrations_notion_router,
    tags=["integrations", "notion"],
)
