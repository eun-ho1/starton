from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from app.schemas.dungeon import DungeonClearResponse, DungeonStatusResponse
from app.schemas.leaderboard import LeaderboardResponse
from app.schemas.profile import ProfileResponse
from app.schemas.quest import CompletedQuestRecordSchema, QuestItemResponse
from app.schemas.stats import StatsSummaryResponse


@dataclass
class QuestRecord:
    id: str
    profile_id: str
    title: str
    exp: int
    difficulty: str
    category: str
    elapsed_seconds: int
    default_duration_seconds: int
    due_at: datetime | None = None


@dataclass
class ProfileState:
    profile_id: str
    user_name: str
    user_role: str
    level: int
    current_exp: int
    max_exp: int
    credits: int
    daily_reset_key: str
    weekly_reset_key: str
    monthly_reset_key: str


@dataclass
class StatsState:
    stats_id: str
    completed_quest_count: int
    earned_exp: int
    daily_reward_count: int
    daily_reward_target: int
    weekly_reward_count: int
    weekly_reward_target: int
    monthly_reward_count: int
    monthly_reward_target: int
    weekly_completed_count: int
    weekly_completion_rate: int
    previous_weekly_completion_rate: int
    weekly_rate_delta: int
    diligence_stat: int
    order_stat: int
    intelligence_stat: int
    health_stat: int
    weekly_activity_counts: list[int]
    weekly_activity_bars: list[float]


class QuestRepository(ABC):
    @abstractmethod
    def list_quests(self, user_id: str) -> list[QuestItemResponse]:
        raise NotImplementedError

    @abstractmethod
    def create_quest(
        self,
        user_id: str,
        quest: QuestItemResponse,
    ) -> QuestItemResponse:
        raise NotImplementedError

    @abstractmethod
    def update_quest(
        self,
        user_id: str,
        quest_id: str,
        quest: QuestItemResponse,
    ) -> QuestItemResponse:
        raise NotImplementedError

    @abstractmethod
    def delete_quest(self, user_id: str, quest_id: str) -> None:
        raise NotImplementedError

    @abstractmethod
    def get_active_quest(self, user_id: str, quest_id: str) -> QuestRecord:
        raise NotImplementedError

    @abstractmethod
    def mark_completed(self, user_id: str, quest_id: str) -> None:
        raise NotImplementedError

    @abstractmethod
    def restore_completed(
        self,
        user_id: str,
        quest_id: str,
        *,
        elapsed_seconds: int,
    ) -> QuestItemResponse:
        raise NotImplementedError


class CompletedQuestRepository(ABC):
    @abstractmethod
    def create_completed_quest(
        self,
        user_id: str,
        quest: QuestRecord,
        earned_exp: int,
        completed_at: datetime,
        elapsed_seconds: int,
        proof_image_path: str | None = None,
    ) -> tuple[str, CompletedQuestRecordSchema]:
        raise NotImplementedError

    @abstractmethod
    def create_completed_task(
        self,
        user_id: str,
        task: QuestRecord,
        earned_exp: int,
        completed_at: datetime,
        elapsed_seconds: int,
        proof_image_path: str | None = None,
    ) -> tuple[str, CompletedQuestRecordSchema]:
        raise NotImplementedError

    @abstractmethod
    def create_recent_activity(
        self,
        user_id: str,
        profile_id: str,
        completed_quest_id: str,
        activity_date: datetime,
        subtitle: str,
        exp: int,
    ) -> None:
        raise NotImplementedError

    @abstractmethod
    def get_latest_completed_record(
        self,
        user_id: str,
        *,
        quest_id: str | None = None,
        task_id: str | None = None,
    ) -> dict[str, Any]:
        raise NotImplementedError

    @abstractmethod
    def delete_completed_record(
        self,
        user_id: str,
        completed_quest_id: str,
    ) -> None:
        raise NotImplementedError

    @abstractmethod
    def delete_recent_activity_for_completed_quest(
        self,
        user_id: str,
        completed_quest_id: str,
    ) -> None:
        raise NotImplementedError


class ProfileRepository(ABC):
    @abstractmethod
    def get_profile_summary(self, user_id: str) -> ProfileResponse:
        raise NotImplementedError

    @abstractmethod
    def get_profile_state(self, user_id: str) -> ProfileState:
        raise NotImplementedError

    @abstractmethod
    def update_profile_progress(
        self,
        user_id: str,
        *,
        level: int,
        current_exp: int,
        max_exp: int,
        user_role: str,
        credits: int,
        daily_reset_key: str,
        weekly_reset_key: str,
        monthly_reset_key: str,
    ) -> None:
        raise NotImplementedError

    @abstractmethod
    def update_profile(
        self,
        user_id: str,
        *,
        user_name: str | None = None,
        user_role: str | None = None,
    ) -> ProfileResponse:
        raise NotImplementedError


class StatsRepository(ABC):
    @abstractmethod
    def get_stats_summary(self, user_id: str) -> StatsSummaryResponse:
        raise NotImplementedError

    @abstractmethod
    def get_stats_state(self, user_id: str) -> StatsState:
        raise NotImplementedError

    @abstractmethod
    def update_stats_after_completion(
        self,
        user_id: str,
        *,
        completed_quest_count: int,
        earned_exp: int,
        daily_reward_count: int,
        weekly_reward_count: int,
        monthly_reward_count: int,
        weekly_completed_count: int,
        weekly_completion_rate: int,
        previous_weekly_completion_rate: int,
        weekly_rate_delta: int,
        diligence_stat: int,
        order_stat: int,
        intelligence_stat: int,
        health_stat: int,
        weekly_activity_counts: list[int],
        weekly_activity_bars: list[float],
    ) -> None:
        raise NotImplementedError

    @abstractmethod
    def calculate_stats_summary(self, user_id: str) -> StatsSummaryResponse:
        raise NotImplementedError


class LeaderboardRepository(ABC):
    @abstractmethod
    def get_leaderboard(
        self,
        current_user_id: str,
        *,
        limit: int = 50,
    ) -> LeaderboardResponse:
        raise NotImplementedError


class DungeonRepository(ABC):
    @abstractmethod
    def list_dungeons(self, user_id: str) -> list[DungeonStatusResponse]:
        raise NotImplementedError

    @abstractmethod
    def clear_dungeon(
        self,
        user_id: str,
        dungeon_id: str,
    ) -> DungeonClearResponse:
        raise NotImplementedError
