from fastapi import Depends

from app.core.auth import AuthenticatedUser, get_current_user
from app.core.crypto import get_secret_cipher
from app.core.supabase import get_supabase_client
from app.repositories.base import CompletedQuestRepository, LeaderboardRepository, ProfileRepository, QuestRepository, StatsRepository
from app.repositories.completed_quest_repository import SupabaseCompletedQuestRepository
from app.repositories.dungeon_repository import SupabaseDungeonRepository
from app.repositories.leaderboard_repository import SupabaseLeaderboardRepository
from app.repositories.mediator_run_repository import SupabaseMediatorRunRepository
from app.repositories.notion_connection_repository import NotionConnectionRepository
from app.repositories.profile_repository import SupabaseProfileRepository
from app.repositories.quest_generation_log_repository import QuestGenerationLogRepository
from app.repositories.quest_repository import SupabaseQuestRepository
from app.repositories.raw_input_repository import SupabaseRawInputRepository
from app.repositories.stats_repository import SupabaseStatsRepository
from app.repositories.task_candidate_repository import SupabaseTaskCandidateRepository
from app.repositories.task_repository import SupabaseTaskRepository
from app.repositories.today_context_repository import SupabaseTodayContextRepository
from app.repositories.user_bootstrap_repository import SupabaseUserBootstrapRepository
from app.providers.gemini_provider import GeminiProvider
from app.providers.gemini_ocr_quest_generation import GeminiOCRQuestGenerationProvider
from app.providers.notion_client import NotionClient
from app.services.ai_quest_service import AIQuestService
from app.services.notion_backend_service import NotionBackendService
from app.services.dungeon_service import DungeonService
from app.services.intake_service import IntakeService
from app.services.leaderboard_service import LeaderboardService
from app.services.mediator_service import MediatorService
from app.services.profile_service import ProfileService
from app.services.quest_service import QuestService
from app.services.stats_service import StatsService
from app.services.task_candidate_review_service import TaskCandidateReviewService
from app.services.task_commit_service import TaskCommitService
from app.services.task_service import TaskService
from app.services.today_planning_service import TodayPlanningService
from app.services.user_task_pattern_service import UserTaskPatternService

def get_current_user_id(
    current_user: AuthenticatedUser = Depends(get_current_user),
) -> str:
    get_user_bootstrap_repository().ensure_user_records(
        current_user.id,
        email=current_user.email,
    )
    return current_user.id


def get_user_bootstrap_repository() -> SupabaseUserBootstrapRepository:
    return SupabaseUserBootstrapRepository(get_supabase_client())


def get_quest_repository() -> QuestRepository:
    return SupabaseQuestRepository(get_supabase_client())


def get_raw_input_repository() -> SupabaseRawInputRepository:
    return SupabaseRawInputRepository(get_supabase_client())


def get_mediator_run_repository() -> SupabaseMediatorRunRepository:
    return SupabaseMediatorRunRepository(get_supabase_client())


def get_task_candidate_repository() -> SupabaseTaskCandidateRepository:
    return SupabaseTaskCandidateRepository(get_supabase_client())


def get_task_repository() -> SupabaseTaskRepository:
    return SupabaseTaskRepository(get_supabase_client())


def get_today_context_repository() -> SupabaseTodayContextRepository:
    return SupabaseTodayContextRepository(get_supabase_client())


def get_completed_quest_repository() -> CompletedQuestRepository:
    return SupabaseCompletedQuestRepository(get_supabase_client())


def get_profile_repository() -> ProfileRepository:
    return SupabaseProfileRepository(get_supabase_client())


def get_stats_repository() -> StatsRepository:
    return SupabaseStatsRepository(get_supabase_client())


def get_leaderboard_repository() -> LeaderboardRepository:
    return SupabaseLeaderboardRepository(get_supabase_client())


def get_quest_service() -> QuestService:
    return QuestService(
        get_quest_repository(),
        get_completed_quest_repository(),
        get_profile_repository(),
        get_stats_repository(),
    )


def get_profile_service() -> ProfileService:
    return ProfileService(get_profile_repository())


def get_stats_service() -> StatsService:
    return StatsService(get_stats_repository())


def get_leaderboard_service() -> LeaderboardService:
    return LeaderboardService(get_leaderboard_repository())


def get_today_planning_service() -> TodayPlanningService:
    return TodayPlanningService(get_today_context_repository())


def get_user_task_pattern_service() -> UserTaskPatternService:
    return UserTaskPatternService(task_repository=get_task_repository())


def get_gemini_provider() -> GeminiProvider:
    return GeminiProvider()


def get_mediator_service() -> MediatorService:
    return MediatorService(
        raw_input_repository=get_raw_input_repository(),
        mediator_run_repository=get_mediator_run_repository(),
        task_candidate_repository=get_task_candidate_repository(),
        gemini_provider=get_gemini_provider(),
        today_planning_service=get_today_planning_service(),
        user_task_pattern_service=get_user_task_pattern_service(),
    )


def get_intake_service() -> IntakeService:
    return IntakeService(
        raw_input_repository=get_raw_input_repository(),
        mediator_service=get_mediator_service(),
    )


def get_task_commit_service() -> TaskCommitService:
    return TaskCommitService(
        task_candidate_repository=get_task_candidate_repository(),
        task_repository=get_task_repository(),
    )


def get_task_service() -> TaskService:
    return TaskService(
        task_repository=get_task_repository(),
        raw_input_repository=get_raw_input_repository(),
        completed_quest_repository=get_completed_quest_repository(),
        profile_repository=get_profile_repository(),
        stats_repository=get_stats_repository(),
    )


def get_task_candidate_review_service() -> TaskCandidateReviewService:
    return TaskCandidateReviewService(
        task_candidate_repository=get_task_candidate_repository(),
    )


def get_dungeon_service() -> DungeonService:
    return DungeonService(SupabaseDungeonRepository(get_supabase_client()))


def get_quest_generation_log_repository() -> QuestGenerationLogRepository:
    return QuestGenerationLogRepository(get_supabase_client())


def get_ai_quest_service() -> AIQuestService:
    return AIQuestService(
        GeminiOCRQuestGenerationProvider(),
        get_quest_generation_log_repository(),
    )


def get_notion_connection_repository() -> NotionConnectionRepository:
    return NotionConnectionRepository(get_supabase_client())


def get_notion_backend_service() -> NotionBackendService:
    return NotionBackendService(
        notion_client=NotionClient(),
        notion_connection_repository=get_notion_connection_repository(),
        profile_repository=SupabaseProfileRepository(get_supabase_client()),
        quest_repository=SupabaseQuestRepository(get_supabase_client()),
        secret_cipher=get_secret_cipher(),
    )
