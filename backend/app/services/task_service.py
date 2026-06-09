from dataclasses import dataclass
from inspect import Parameter, signature
from datetime import datetime
from typing import Any

from app.repositories.base import CompletedQuestRepository, ProfileRepository, QuestRecord, StatsRepository
from app.repositories.raw_input_repository import SupabaseRawInputRepository
from app.repositories.task_repository import SupabaseTaskRepository
from app.schemas.quest import CompletedQuestRecordSchema
from app.schemas.task import TaskResponse, TaskStatus
from app.services.progression_service import (
    apply_category_stats,
    apply_exp,
    build_weekly_bars,
    calculate_weekly_completion_rate,
    date_key,
    month_key,
    normalize_progress,
    normalized_weekly_counts,
    remove_exp,
    role_for_level,
    service_timezone,
    subtract_category_stats,
    week_key,
)


@dataclass(frozen=True)
class TaskServiceError(Exception):
    code: str
    message: str

    def __str__(self) -> str:
        return self.message


class TaskService:
    def __init__(
        self,
        *,
        task_repository: SupabaseTaskRepository,
        raw_input_repository: SupabaseRawInputRepository,
        completed_quest_repository: CompletedQuestRepository,
        profile_repository: ProfileRepository,
        stats_repository: StatsRepository,
    ) -> None:
        self._task_repository = task_repository
        self._raw_input_repository = raw_input_repository
        self._completed_quest_repository = completed_quest_repository
        self._profile_repository = profile_repository
        self._stats_repository = stats_repository

    def list_active_tasks(self, *, user_id: str) -> list[TaskResponse]:
        try:
            tasks = self._task_repository.list_active(user_id=user_id)
            return [
                self._with_raw_input_metadata(user_id=user_id, task=task)
                for task in tasks
            ]
        except Exception as error:
            raise TaskServiceError(
                "task_list_failed",
                "Failed to load tasks for the current user.",
            ) from error

    def update_task_progress(
        self,
        *,
        user_id: str,
        task_id: str,
        elapsed_seconds: int,
    ) -> TaskResponse:
        try:
            task = self._task_repository.update_progress(
                user_id=user_id,
                task_id=task_id,
                elapsed_seconds=elapsed_seconds,
            )
            return self._with_raw_input_metadata(user_id=user_id, task=task)
        except ValueError as error:
            raise TaskServiceError(
                "task_not_found",
                "Task was not found.",
            ) from error
        except Exception as error:
            raise TaskServiceError(
                "task_progress_update_failed",
                "Failed to update task progress.",
            ) from error

    def _with_raw_input_metadata(
        self,
        *,
        user_id: str,
        task: TaskResponse,
    ) -> TaskResponse:
        task_metadata = _expanded_task_metadata(dict(task.metadata))
        if task.raw_input_id is not None:
            try:
                raw_input = self._raw_input_repository.get(
                    user_id=user_id,
                    raw_input_id=str(task.raw_input_id),
                )
                existing_client_metadata = task_metadata.get("client_metadata")
                if isinstance(existing_client_metadata, dict):
                    existing_client_metadata.update(raw_input.client_metadata)
                else:
                    task_metadata["client_metadata"] = dict(raw_input.client_metadata)
                for key, value in raw_input.client_metadata.items():
                    task_metadata.setdefault(key, value)
            except Exception:
                pass
        return task.model_copy(update={"metadata": task_metadata})

    def complete_task(
        self,
        *,
        user_id: str,
        task_id: str,
        elapsed_seconds: int = 0,
        proof_image_path: str | None = None,
    ) -> CompletedQuestRecordSchema:
        try:
            task = self._task_repository.get(user_id=user_id, task_id=task_id)
        except ValueError as error:
            raise TaskServiceError(
                "task_not_found",
                "Task was not found.",
            ) from error
        except Exception as error:
            raise TaskServiceError(
                "task_complete_failed",
                "Failed to load the task for completion.",
            ) from error

        task = self._with_raw_input_metadata(user_id=user_id, task=task)

        if str(task.status) == TaskStatus.DONE.value or task.completed_at is not None:
            raise TaskServiceError(
                "task_already_completed",
                "This task has already been completed.",
            )

        try:
            profile = self._profile_repository.get_profile_state(user_id)
            stats = self._stats_repository.get_stats_state(user_id)
        except ValueError as error:
            raise TaskServiceError(
                "task_dependency_not_found",
                str(error),
            ) from error
        except Exception as error:
            raise TaskServiceError(
                "task_complete_failed",
                "Failed to load profile or stats required for completion.",
            ) from error

        task_metadata = dict(task.metadata)

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

        quest_difficulty = _quest_difficulty_from_task(task.difficulty)
        category = _task_category(task_metadata)
        earned_exp = _task_exp(task.difficulty, task_metadata)
        recorded_elapsed_seconds = _task_elapsed_seconds(
            elapsed_seconds=elapsed_seconds,
            stored_elapsed_seconds=task.elapsed_seconds,
            metadata=task_metadata,
        )
        quest_record = QuestRecord(
            id=str(task.id),
            profile_id=profile.profile_id,
            title=task.title,
            exp=earned_exp,
            difficulty=quest_difficulty,
            category=category,
            elapsed_seconds=recorded_elapsed_seconds,
            default_duration_seconds=_task_default_duration_seconds(
                task.estimated_minutes,
                task_metadata,
            ),
        )

        next_level, next_current_exp, next_max_exp = apply_exp(
            level=profile.level,
            current_exp=profile.current_exp,
            max_exp=profile.max_exp,
            gained_exp=earned_exp,
        )

        weekly_counts = normalized_weekly_counts(stats.weekly_activity_counts)
        weekday_index = completed_at.weekday()
        weekly_counts[weekday_index] += 1
        weekly_bars = build_weekly_bars(weekly_counts)

        weekly_completed_count = stats.weekly_completed_count + 1
        weekly_completion_rate = calculate_weekly_completion_rate(
            weekly_completed_count,
            stats.weekly_reward_target,
        )
        weekly_rate_delta = weekly_completion_rate - stats.previous_weekly_completion_rate
        diligence_stat, order_stat, intelligence_stat, health_stat = apply_category_stats(
            diligence_stat=stats.diligence_stat,
            order_stat=stats.order_stat,
            intelligence_stat=stats.intelligence_stat,
            health_stat=stats.health_stat,
            category=category,
            difficulty=quest_difficulty,
        )

        try:
            completed_quest_id, completed_record = self._completed_quest_repository.create_completed_task(
                user_id=user_id,
                task=quest_record,
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
                subtitle=f"Completed: {task.title}",
                exp=earned_exp,
            )
            self._stats_repository.update_stats_after_completion(
                user_id,
                completed_quest_count=stats.completed_quest_count + 1,
                earned_exp=stats.earned_exp + earned_exp,
                daily_reward_count=min(stats.daily_reward_target, stats.daily_reward_count + 1),
                weekly_reward_count=min(stats.weekly_reward_target, stats.weekly_reward_count + 1),
                monthly_reward_count=min(stats.monthly_reward_target, stats.monthly_reward_count + 1),
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
            self._mark_task_completed(
                user_id=user_id,
                task_id=task_id,
                completed_at=completed_at,
                elapsed_seconds=recorded_elapsed_seconds,
            )
            return completed_record
        except ValueError as error:
            raise TaskServiceError(
                "task_complete_failed",
                str(error),
            ) from error
        except Exception as error:
            raise TaskServiceError(
                "task_complete_failed",
                "Failed to complete the task and update related records.",
            ) from error

    def delete_task(self, *, user_id: str, task_id: str) -> None:
        try:
            self._task_repository.delete_task(user_id=user_id, task_id=task_id)
        except ValueError as error:
            raise TaskServiceError(
                "task_not_found",
                "Task was not found.",
            ) from error
        except Exception as error:
            raise TaskServiceError(
                "task_delete_failed",
                "Failed to delete the task.",
            ) from error

    def undo_complete_task(
        self,
        *,
        user_id: str,
        task_id: str,
    ) -> TaskResponse:
        try:
            completed = self._completed_quest_repository.get_latest_completed_record(
                user_id,
                task_id=task_id,
            )
        except ValueError as error:
            raise TaskServiceError(
                "completed_task_not_found",
                str(error),
            ) from error
        except Exception as error:
            raise TaskServiceError(
                "task_undo_complete_failed",
                "Failed to load the completed task record.",
            ) from error

        earned_exp = max(0, int(completed.get("earned_exp") or 0))
        elapsed_seconds = max(0, int(completed.get("elapsed_seconds") or 0))
        category = str(completed.get("category") or "work")
        difficulty = str(completed.get("difficulty") or "normal")

        try:
            profile = self._profile_repository.get_profile_state(user_id)
            stats = self._stats_repository.get_stats_state(user_id)
        except ValueError as error:
            raise TaskServiceError(
                "task_dependency_not_found",
                str(error),
            ) from error
        except Exception as error:
            raise TaskServiceError(
                "task_undo_complete_failed",
                "Failed to load profile or stats required for undo.",
            ) from error

        now = datetime.now(service_timezone())
        today_key_value = date_key(now)
        week_key_value = week_key(now)
        month_key_value = month_key(now)
        profile, stats = normalize_progress(
            profile,
            stats,
            today_key_value,
            week_key_value,
            month_key_value,
        )
        completed_at = _parse_completed_at(completed.get("completed_at"), fallback=now)

        next_level, next_current_exp, next_max_exp = remove_exp(
            level=profile.level,
            current_exp=profile.current_exp,
            max_exp=profile.max_exp,
            lost_exp=earned_exp,
        )

        same_day = date_key(completed_at) == today_key_value
        same_week = week_key(completed_at) == week_key_value
        same_month = month_key(completed_at) == month_key_value

        weekly_counts = normalized_weekly_counts(stats.weekly_activity_counts)
        if same_week:
            weekday_index = completed_at.weekday()
            weekly_counts[weekday_index] = max(0, weekly_counts[weekday_index] - 1)
        weekly_bars = build_weekly_bars(weekly_counts)

        weekly_completed_count = (
            max(0, stats.weekly_completed_count - 1)
            if same_week
            else stats.weekly_completed_count
        )
        weekly_completion_rate = calculate_weekly_completion_rate(
            weekly_completed_count,
            stats.weekly_reward_target,
        )
        weekly_rate_delta = weekly_completion_rate - stats.previous_weekly_completion_rate
        diligence_stat, order_stat, intelligence_stat, health_stat = (
            subtract_category_stats(
                diligence_stat=stats.diligence_stat,
                order_stat=stats.order_stat,
                intelligence_stat=stats.intelligence_stat,
                health_stat=stats.health_stat,
                category=category,
                difficulty=difficulty,
            )
        )

        try:
            restored_task = self._task_repository.restore_completed(
                user_id=user_id,
                task_id=task_id,
                elapsed_seconds=elapsed_seconds,
            )
            completed_id = str(completed["id"])
            self._completed_quest_repository.delete_recent_activity_for_completed_quest(
                user_id,
                completed_id,
            )
            self._completed_quest_repository.delete_completed_record(
                user_id,
                completed_id,
            )
            self._stats_repository.update_stats_after_completion(
                user_id,
                completed_quest_count=max(0, stats.completed_quest_count - 1),
                earned_exp=max(0, stats.earned_exp - earned_exp),
                daily_reward_count=(
                    max(0, stats.daily_reward_count - 1)
                    if same_day
                    else stats.daily_reward_count
                ),
                weekly_reward_count=(
                    max(0, stats.weekly_reward_count - 1)
                    if same_week
                    else stats.weekly_reward_count
                ),
                monthly_reward_count=(
                    max(0, stats.monthly_reward_count - 1)
                    if same_month
                    else stats.monthly_reward_count
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
            return self._with_raw_input_metadata(user_id=user_id, task=restored_task)
        except ValueError as error:
            raise TaskServiceError(
                "task_undo_complete_failed",
                str(error),
            ) from error
        except Exception as error:
            raise TaskServiceError(
                "task_undo_complete_failed",
                "Failed to undo task completion and update related records.",
            ) from error

    def _mark_task_completed(
        self,
        *,
        user_id: str,
        task_id: str,
        completed_at: datetime,
        elapsed_seconds: int,
    ) -> None:
        mark_completed = self._task_repository.mark_completed
        try:
            parameters = signature(mark_completed).parameters
        except (TypeError, ValueError):
            parameters = {}

        accepts_elapsed_seconds = (
            "elapsed_seconds" in parameters
            or any(
                parameter.kind == Parameter.VAR_KEYWORD
                for parameter in parameters.values()
            )
        )
        if accepts_elapsed_seconds:
            mark_completed(
                user_id=user_id,
                task_id=task_id,
                completed_at=completed_at,
                elapsed_seconds=elapsed_seconds,
            )
            return

        mark_completed(
            user_id=user_id,
            task_id=task_id,
            completed_at=completed_at,
        )


def _quest_difficulty_from_task(difficulty: str | None) -> str:
    return {
        "low": "easy",
        "easy": "easy",
        "medium": "normal",
        "normal": "normal",
        "high": "hard",
        "hard": "hard",
    }.get((difficulty or "").strip().lower(), "normal")


def _task_exp(difficulty: str | None, metadata: dict[str, Any]) -> int:
    metadata_exp = _metadata_int(metadata, "exp")
    if metadata_exp is not None and metadata_exp >= 0:
        return metadata_exp
    return {
        "low": 30,
        "easy": 30,
        "medium": 50,
        "normal": 50,
        "high": 100,
        "hard": 100,
    }.get((difficulty or "").strip().lower(), 50)


def _task_category(metadata: dict[str, Any]) -> str:
    value = str(_metadata_value(metadata, "category") or "").strip().lower()
    if value in {"work", "life", "study", "home"}:
        return value
    return "work"


def _task_elapsed_seconds(
    *,
    elapsed_seconds: int,
    stored_elapsed_seconds: int,
    metadata: dict[str, Any],
) -> int:
    candidates = [
        elapsed_seconds,
        stored_elapsed_seconds,
        _metadata_int(metadata, "elapsed_seconds") or 0,
        _metadata_int(metadata, "elapsedSeconds") or 0,
    ]
    return max(0, max(candidates))


def _task_default_duration_seconds(
    estimated_minutes: int | None,
    metadata: dict[str, Any],
) -> int:
    if isinstance(estimated_minutes, int) and estimated_minutes > 0:
        return estimated_minutes * 60
    metadata_duration = _metadata_int(metadata, "default_duration_seconds")
    if metadata_duration is not None and metadata_duration > 0:
        return metadata_duration
    metadata_duration = _metadata_int(metadata, "defaultDurationSeconds")
    if metadata_duration is not None and metadata_duration > 0:
        return metadata_duration
    return 0


def _expanded_task_metadata(metadata: dict[str, Any]) -> dict[str, Any]:
    expanded = dict(metadata)
    for key in ("client_metadata", "edited_fields"):
        nested = expanded.get(key)
        if isinstance(nested, dict):
            for nested_key, nested_value in nested.items():
                expanded.setdefault(nested_key, nested_value)
    return expanded


def _metadata_value(metadata: dict[str, Any], key: str) -> Any:
    if key in metadata:
        return metadata.get(key)
    for object_key in ("client_metadata", "edited_fields"):
        nested = metadata.get(object_key)
        if isinstance(nested, dict) and key in nested:
            return nested.get(key)
    return None


def _metadata_int(metadata: dict[str, Any], key: str) -> int | None:
    value = _metadata_value(metadata, key)
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    if isinstance(value, str):
        try:
            return int(value.strip())
        except ValueError:
            return None
    return None

def _parse_completed_at(value: object, *, fallback: datetime) -> datetime:
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return fallback
    else:
        return fallback

    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=service_timezone())
    return parsed.astimezone(service_timezone())

