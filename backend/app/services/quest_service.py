from datetime import datetime

from app.repositories.base import (
    CompletedQuestRepository,
    ProfileRepository,
    QuestRepository,
    StatsRepository,
)
from app.schemas.quest import CompletedQuestRecordSchema, QuestItemResponse
from app.services.progression_service import (
    apply_category_stats,
    apply_exp,
    build_weekly_bars,
    calculate_weekly_completion_rate,
    date_key,
    month_key,
    normalize_progress,
    normalized_weekly_counts,
    role_for_level,
    service_timezone,
    week_key,
)


class QuestServiceError(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


class QuestNotFoundError(QuestServiceError):
    pass


class QuestOperationError(QuestServiceError):
    pass


class QuestService:
    def __init__(
        self,
        quest_repository: QuestRepository,
        completed_quest_repository: CompletedQuestRepository,
        profile_repository: ProfileRepository,
        stats_repository: StatsRepository,
    ) -> None:
        self._quest_repository = quest_repository
        self._completed_quest_repository = completed_quest_repository
        self._profile_repository = profile_repository
        self._stats_repository = stats_repository

    def list_quests(self, user_id: str) -> list[QuestItemResponse]:
        try:
            return self._quest_repository.list_quests(user_id)
        except Exception as exc:
            raise QuestOperationError(
                "quest_list_failed",
                "Failed to load quests for the current user.",
            ) from exc

    def create_quest(self, user_id: str, quest: QuestItemResponse) -> QuestItemResponse:
        try:
            return self._quest_repository.create_quest(user_id, quest)
        except ValueError as exc:
            raise QuestOperationError(
                "quest_create_failed",
                str(exc),
            ) from exc
        except Exception as exc:
            raise QuestOperationError(
                "quest_create_failed",
                "Failed to create the quest.",
            ) from exc

    def update_quest(
        self,
        user_id: str,
        quest_id: str,
        quest: QuestItemResponse,
    ) -> QuestItemResponse:
        try:
            return self._quest_repository.update_quest(user_id, quest_id, quest)
        except ValueError as exc:
            raise QuestNotFoundError(
                "quest_not_found",
                str(exc),
            ) from exc
        except Exception as exc:
            raise QuestOperationError(
                "quest_update_failed",
                "Failed to update the quest.",
            ) from exc

    def delete_quest(self, user_id: str, quest_id: str) -> None:
        try:
            self._quest_repository.delete_quest(user_id, quest_id)
        except ValueError as exc:
            raise QuestNotFoundError(
                "quest_not_found",
                str(exc),
            ) from exc
        except Exception as exc:
            raise QuestOperationError(
                "quest_delete_failed",
                "Failed to delete the quest.",
            ) from exc

    def complete_quest(
        self,
        user_id: str,
        quest_id: str,
        *,
        elapsed_seconds: int | None = None,
        proof_image_path: str | None = None,
    ) -> CompletedQuestRecordSchema:
        try:
            quest = self._quest_repository.get_active_quest(user_id, quest_id)
        except ValueError as exc:
            raise QuestNotFoundError(
                "quest_not_found",
                str(exc),
            ) from exc
        except Exception as exc:
            raise QuestOperationError(
                "quest_complete_failed",
                "Failed to load the quest for completion.",
            ) from exc

        try:
            profile = self._profile_repository.get_profile_state(user_id)
            stats = self._stats_repository.get_stats_state(user_id)
        except ValueError as exc:
            raise QuestOperationError(
                "quest_dependency_not_found",
                str(exc),
            ) from exc
        except Exception as exc:
            raise QuestOperationError(
                "quest_complete_failed",
                "Failed to load profile or stats required for completion.",
            ) from exc

        completed_at = datetime.now(service_timezone())
        today_key_value = date_key(completed_at)
        week_key_value = week_key(completed_at)
        month_key_value = month_key(completed_at)
        profile, stats = normalize_progress(
            profile,
            stats,
            today_key_value,
            week_key_value,
            month_key_value,
        )
        recorded_elapsed_seconds = elapsed_seconds if elapsed_seconds is not None else quest.elapsed_seconds
        earned_exp = quest.exp

        next_level, next_current_exp, next_max_exp = apply_exp(
            level=profile.level,
            current_exp=profile.current_exp,
            max_exp=profile.max_exp,
            gained_exp=earned_exp,
        )

        weekly_counts = normalized_weekly_counts(stats.weekly_activity_counts)
        weekday_index = completed_at.weekday()  # Monday=0
        weekly_counts[weekday_index] += 1
        weekly_bars = build_weekly_bars(weekly_counts)

        weekly_completed_count = stats.weekly_completed_count + 1
        weekly_completion_rate = calculate_weekly_completion_rate(
            weekly_completed_count,
            stats.weekly_reward_target,
        )
        weekly_rate_delta = (
            weekly_completion_rate - stats.previous_weekly_completion_rate
        )
        diligence_stat, order_stat, intelligence_stat, health_stat = (
            apply_category_stats(
                diligence_stat=stats.diligence_stat,
                order_stat=stats.order_stat,
                intelligence_stat=stats.intelligence_stat,
                health_stat=stats.health_stat,
                category=quest.category,
                difficulty=quest.difficulty,
            )
        )

        try:
            completed_quest_id, completed_record = self._completed_quest_repository.create_completed_quest(
                user_id=user_id,
                quest=quest,
                earned_exp=earned_exp,
                completed_at=completed_at,
                elapsed_seconds=recorded_elapsed_seconds,
                proof_image_path=proof_image_path,
            )
            self._completed_quest_repository.create_recent_activity(
                user_id=user_id,
                profile_id=profile.profile_id,
                completed_quest_id=completed_quest_id,
                activity_date=completed_at,
                subtitle=f"Completed: {quest.title}",
                exp=earned_exp,
            )
            self._stats_repository.update_stats_after_completion(
                user_id,
                completed_quest_count=stats.completed_quest_count + 1,
                earned_exp=stats.earned_exp + earned_exp,
                daily_reward_count=min(
                    stats.daily_reward_target,
                    stats.daily_reward_count + 1,
                ),
                weekly_reward_count=min(
                    stats.weekly_reward_target,
                    stats.weekly_reward_count + 1,
                ),
                monthly_reward_count=min(
                    stats.monthly_reward_target,
                    stats.monthly_reward_count + 1,
                ),
                weekly_completed_count=weekly_completed_count,
                weekly_completion_rate=weekly_completion_rate,
                previous_weekly_completion_rate=stats.previous_weekly_completion_rate,
                weekly_rate_delta=weekly_rate_delta,
                diligence_stat=diligence_stat,
                order_stat=order_stat,
                intelligence_stat=intelligence_stat,
                health_stat=health_stat,
                weekly_activity_counts=weekly_counts,
                weekly_activity_bars=weekly_bars,
            )
            self._profile_repository.update_profile_progress(
                user_id,
                level=next_level,
                current_exp=next_current_exp,
                max_exp=next_max_exp,
                user_role=role_for_level(next_level),
                credits=profile.credits,
                daily_reset_key=profile.daily_reset_key,
                weekly_reset_key=profile.weekly_reset_key,
                monthly_reset_key=profile.monthly_reset_key,
            )
            self._quest_repository.mark_completed(user_id, quest_id)
            return completed_record
        except ValueError as exc:
            raise QuestOperationError(
                "quest_complete_failed",
                str(exc),
            ) from exc
        except Exception as exc:
            raise QuestOperationError(
                "quest_complete_failed",
                "Failed to complete the quest and update related records.",
            ) from exc
