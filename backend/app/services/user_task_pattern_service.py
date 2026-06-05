from dataclasses import dataclass
from datetime import datetime
from statistics import mean
from typing import Callable

from app.repositories.task_repository import SupabaseTaskRepository
from app.schemas.task import TaskResponse, TaskStatus


_MIN_HISTORY_TASKS = 5
_MIN_COMPLETED_TASKS = 3
_NEAR_DEADLINE_HOURS = 24


@dataclass(frozen=True)
class UserTaskPatternAnalysis:
    data_sufficient: bool
    history_count: int
    completed_count: int
    existing_tasks: list[dict[str, object]]
    prompt_payload: dict[str, object]


class UserTaskPatternService:
    def __init__(self, *, task_repository: SupabaseTaskRepository) -> None:
        self._task_repository = task_repository

    def analyze(self, *, user_id: str) -> UserTaskPatternAnalysis:
        tasks = self._task_repository.list_for_pattern_analysis(
            user_id=user_id,
            limit=50,
        )
        return _build_analysis(tasks)


def _build_analysis(tasks: list[TaskResponse]) -> UserTaskPatternAnalysis:
    history_count = len(tasks)
    completed_tasks = [task for task in tasks if _is_completed(task)]
    completed_count = len(completed_tasks)

    if history_count < _MIN_HISTORY_TASKS or completed_count < _MIN_COMPLETED_TASKS:
        return UserTaskPatternAnalysis(
            data_sufficient=False,
            history_count=history_count,
            completed_count=completed_count,
            existing_tasks=[],
            prompt_payload={},
        )

    completion_rate = _ratio(completed_count, history_count)
    avg_completion_hours = _avg_completion_hours(completed_tasks)
    avg_delay_days = _avg_delay_days(completed_tasks)
    short_task_completion_rate = _completion_rate_for(
        tasks,
        lambda task: _estimated_minutes(task) is not None and _estimated_minutes(task) <= 30,
    )
    long_task_completion_rate = _completion_rate_for(
        tasks,
        lambda task: _estimated_minutes(task) is not None and _estimated_minutes(task) >= 90,
    )
    small_subtask_completion_rate = _completion_rate_for(
        tasks,
        lambda task: 0 < len(task.subtasks) <= 3,
    )
    large_subtask_completion_rate = _completion_rate_for(
        tasks,
        lambda task: len(task.subtasks) >= 5,
    )
    high_difficulty_completion_rate = _completion_rate_for(
        tasks,
        lambda task: str(task.difficulty or "").lower() == "high",
    )
    low_medium_completion_rate = _completion_rate_for(
        tasks,
        lambda task: str(task.difficulty or "").lower() in {"low", "medium"},
    )

    prefers_small_tasks = (
        short_task_completion_rate >= long_task_completion_rate + 0.15
        or small_subtask_completion_rate >= large_subtask_completion_rate + 0.15
    )
    procrastination_level = _procrastination_level(
        completed_tasks=completed_tasks,
        avg_delay_days=avg_delay_days,
    )
    task_completion_style = _task_completion_style(
        prefers_small_tasks=prefers_small_tasks,
        procrastination_level=procrastination_level,
    )
    difficulty_dropoff = (
        high_difficulty_completion_rate + 0.15 < low_medium_completion_rate
    )

    prompt_payload: dict[str, object] = {
        "task_count_used_for_analysis": history_count,
        "completion_rate": completion_rate,
        "avg_delay_days": avg_delay_days,
        "avg_completion_hours": avg_completion_hours,
        "prefers_small_tasks": prefers_small_tasks,
        "procrastination_level": procrastination_level,
        "task_completion_style": task_completion_style,
        "difficulty_dropoff": difficulty_dropoff,
    }

    return UserTaskPatternAnalysis(
        data_sufficient=True,
        history_count=history_count,
        completed_count=completed_count,
        existing_tasks=[],
        prompt_payload=prompt_payload,
    )


def _avg_completion_hours(tasks: list[TaskResponse]) -> float:
    values = [
        round((task.completed_at - task.created_at).total_seconds() / 3600, 2)
        for task in tasks
        if task.created_at is not None and task.completed_at is not None
    ]
    if not values:
        return 0.0
    return round(mean(values), 1)


def _avg_delay_days(tasks: list[TaskResponse]) -> float:
    values = [
        max(
            0.0,
            round((task.completed_at - task.due_at).total_seconds() / 86400, 2),
        )
        for task in tasks
        if task.completed_at is not None and task.due_at is not None
    ]
    if not values:
        return 0.0
    return round(mean(values), 1)


def _completion_rate_for(
    tasks: list[TaskResponse],
    predicate: Callable[[TaskResponse], bool],
) -> float:
    matched = [task for task in tasks if predicate(task)]
    if not matched:
        return 0.0
    return _ratio(sum(1 for task in matched if _is_completed(task)), len(matched))


def _procrastination_level(
    *,
    completed_tasks: list[TaskResponse],
    avg_delay_days: float,
) -> str:
    deadline_tasks = [
        task for task in completed_tasks if task.completed_at is not None and task.due_at is not None
    ]
    near_deadline_ratio = _ratio(
        sum(
            1
            for task in deadline_tasks
            if 0 <= _hours_between(task.completed_at, task.due_at) <= _NEAR_DEADLINE_HOURS
        ),
        len(deadline_tasks),
    )
    if avg_delay_days >= 2.0 or near_deadline_ratio >= 0.6:
        return "high"
    if avg_delay_days >= 0.5 or near_deadline_ratio >= 0.3:
        return "medium"
    return "low"


def _task_completion_style(
    *,
    prefers_small_tasks: bool,
    procrastination_level: str,
) -> str:
    if prefers_small_tasks:
        return "incremental"
    if procrastination_level == "high":
        return "burst"
    return "balanced"


def _ratio(numerator: int, denominator: int) -> float:
    if denominator <= 0:
        return 0.0
    return round(numerator / denominator, 3)


def _hours_between(start: datetime, end: datetime) -> float:
    return round((end - start).total_seconds() / 3600, 2)


def _estimated_minutes(task: TaskResponse) -> int | None:
    if isinstance(task.estimated_minutes, int) and task.estimated_minutes >= 0:
        return task.estimated_minutes
    return None


def _is_completed(task: TaskResponse) -> bool:
    return str(task.status) == TaskStatus.DONE.value or task.completed_at is not None
