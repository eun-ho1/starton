from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from statistics import mean
from typing import Any, Callable

from app.repositories.task_repository import SupabaseTaskRepository
from app.schemas.task import TaskResponse, TaskStatus


_MIN_HISTORY_TASKS = 5
_MIN_COMPLETED_TASKS = 3
_LONG_COMPLETION_HOURS = 72
_STALE_OPEN_DAYS = 7
_NEAR_DEADLINE_HOURS = 24


@dataclass(frozen=True)
class UserTaskPatternAnalysis:
    data_sufficient: bool
    history_count: int
    completed_count: int
    existing_tasks: list[dict[str, Any]]
    prompt_payload: dict[str, Any]


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

    now = datetime.now(timezone.utc)
    open_tasks = [task for task in tasks if not _is_completed(task)]
    completion_hours = [
        _hours_between(task.created_at, task.completed_at)
        for task in completed_tasks
        if task.created_at is not None and task.completed_at is not None
    ]
    avg_completion_hours = round(mean(completion_hours), 1) if completion_hours else None

    deadline_completed_tasks = [
        task for task in completed_tasks if task.due_at is not None and task.completed_at is not None
    ]
    near_deadline_ratio = _safe_ratio(
        sum(
            1
            for task in deadline_completed_tasks
            if 0 <= _hours_between(task.completed_at, task.due_at) <= _NEAR_DEADLINE_HOURS
        ),
        len(deadline_completed_tasks),
    )
    overdue_completion_ratio = _safe_ratio(
        sum(1 for task in deadline_completed_tasks if task.completed_at > task.due_at),
        len(deadline_completed_tasks),
    )

    overdue_open_ratio = _safe_ratio(
        sum(1 for task in open_tasks if task.due_at is not None and task.due_at < now),
        len(open_tasks),
    )
    stale_open_ratio = _safe_ratio(
        sum(
            1
            for task in open_tasks
            if task.created_at is not None and task.created_at < now - timedelta(days=_STALE_OPEN_DAYS)
        ),
        len(open_tasks),
    )
    paused_ratio = _safe_ratio(
        sum(1 for task in open_tasks if str(task.status) == TaskStatus.PAUSED.value),
        len(open_tasks),
    )

    short_completion_rate = _completion_rate_for(
        tasks,
        lambda task: _estimated_minutes(task) is not None and _estimated_minutes(task) <= 30,
    )
    long_completion_rate = _completion_rate_for(
        tasks,
        lambda task: _estimated_minutes(task) is not None and _estimated_minutes(task) >= 90,
    )
    small_subtask_completion_rate = _completion_rate_for(
        tasks,
        lambda task: len(task.subtasks) <= 3,
    )
    large_subtask_completion_rate = _completion_rate_for(
        tasks,
        lambda task: len(task.subtasks) >= 5,
    )

    difficulty_completion_rates = {
        level: _completion_rate_for(tasks, lambda task, level=level: str(task.difficulty or "") == level)
        for level in ("low", "medium", "high")
    }

    completion_rate = _safe_ratio(completed_count, history_count)
    bias_labels = _build_bias_labels(
        avg_completion_hours=avg_completion_hours,
        completion_rate=completion_rate,
        near_deadline_ratio=near_deadline_ratio,
        overdue_completion_ratio=overdue_completion_ratio,
        overdue_open_ratio=overdue_open_ratio,
        stale_open_ratio=stale_open_ratio,
        paused_ratio=paused_ratio,
        short_completion_rate=short_completion_rate,
        long_completion_rate=long_completion_rate,
        small_subtask_completion_rate=small_subtask_completion_rate,
        large_subtask_completion_rate=large_subtask_completion_rate,
        difficulty_completion_rates=difficulty_completion_rates,
    )

    analysis_summary = _build_analysis_summary(
        history_count=history_count,
        completed_count=completed_count,
        completion_rate=completion_rate,
        avg_completion_hours=avg_completion_hours,
        near_deadline_ratio=near_deadline_ratio,
        overdue_completion_ratio=overdue_completion_ratio,
        overdue_open_ratio=overdue_open_ratio,
        stale_open_ratio=stale_open_ratio,
        paused_ratio=paused_ratio,
        short_completion_rate=short_completion_rate,
        long_completion_rate=long_completion_rate,
        small_subtask_completion_rate=small_subtask_completion_rate,
        large_subtask_completion_rate=large_subtask_completion_rate,
        difficulty_completion_rates=difficulty_completion_rates,
    )

    prompt_payload = {
        "data_sufficient": True,
        "analysis_summary": analysis_summary,
        "planning_biases": bias_labels,
        "metrics": {
            "history_count": history_count,
            "completed_count": completed_count,
            "completion_rate": completion_rate,
            "avg_completion_hours": avg_completion_hours,
            "near_deadline_completion_ratio": near_deadline_ratio,
            "overdue_completion_ratio": overdue_completion_ratio,
            "overdue_open_ratio": overdue_open_ratio,
            "stale_open_ratio": stale_open_ratio,
            "paused_open_ratio": paused_ratio,
            "short_task_completion_rate": short_completion_rate,
            "long_task_completion_rate": long_completion_rate,
            "small_subtask_completion_rate": small_subtask_completion_rate,
            "large_subtask_completion_rate": large_subtask_completion_rate,
            "difficulty_completion_rates": difficulty_completion_rates,
        },
    }

    return UserTaskPatternAnalysis(
        data_sufficient=True,
        history_count=history_count,
        completed_count=completed_count,
        existing_tasks=_build_existing_tasks(open_tasks),
        prompt_payload=prompt_payload,
    )


def _build_existing_tasks(tasks: list[TaskResponse]) -> list[dict[str, Any]]:
    summary = []
    for task in tasks[:8]:
        summary.append(
            {
                "title": task.title,
                "status": str(task.status),
                "due_at": _iso(task.due_at),
                "estimated_minutes": _estimated_minutes(task),
                "difficulty": _string_value(task.difficulty),
                "subtask_count": len(task.subtasks),
                "next_action": task.next_action,
            }
        )
    return summary


def _build_bias_labels(
    *,
    avg_completion_hours: float | None,
    completion_rate: float,
    near_deadline_ratio: float,
    overdue_completion_ratio: float,
    overdue_open_ratio: float,
    stale_open_ratio: float,
    paused_ratio: float,
    short_completion_rate: float,
    long_completion_rate: float,
    small_subtask_completion_rate: float,
    large_subtask_completion_rate: float,
    difficulty_completion_rates: dict[str, float],
) -> list[str]:
    labels: list[str] = []
    if avg_completion_hours is not None and avg_completion_hours >= _LONG_COMPLETION_HOURS:
        labels.append("slow_finisher")
    if near_deadline_ratio >= 0.5:
        labels.append("deadline_driven")
    if max(overdue_completion_ratio, overdue_open_ratio, stale_open_ratio, paused_ratio) >= 0.35:
        labels.append("delay_risk")
    if completion_rate >= 0.75:
        labels.append("high_completion")
    elif completion_rate <= 0.45:
        labels.append("low_completion")
    if short_completion_rate >= long_completion_rate + 0.2:
        labels.append("short_tasks_work_better")
    if small_subtask_completion_rate >= large_subtask_completion_rate + 0.2:
        labels.append("smaller_breakdowns_work_better")
    low_rate = difficulty_completion_rates.get("low", 0.0)
    high_rate = difficulty_completion_rates.get("high", 0.0)
    if low_rate >= high_rate + 0.2:
        labels.append("high_difficulty_dropoff")
    return labels


def _build_analysis_summary(
    *,
    history_count: int,
    completed_count: int,
    completion_rate: float,
    avg_completion_hours: float | None,
    near_deadline_ratio: float,
    overdue_completion_ratio: float,
    overdue_open_ratio: float,
    stale_open_ratio: float,
    paused_ratio: float,
    short_completion_rate: float,
    long_completion_rate: float,
    small_subtask_completion_rate: float,
    large_subtask_completion_rate: float,
    difficulty_completion_rates: dict[str, float],
) -> str:
    completion_text = _percent_text(completion_rate)
    avg_completion_text = (
        f"평균 완료까지 약 {avg_completion_hours:.1f}시간이 걸립니다."
        if avg_completion_hours is not None
        else "완료 시간 데이터는 제한적입니다."
    )
    delay_text = (
        "마감 직전이나 마감 이후에 끝나는 경향이 보여서 초반에는 아주 가벼운 준비 작업을 두고, 핵심 실행 단계를 여러 짧은 덩어리로 분산하는 편이 좋습니다."
        if max(near_deadline_ratio, overdue_completion_ratio, overdue_open_ratio, stale_open_ratio, paused_ratio) >= 0.35
        else "마감 압박 신호는 크지 않으므로 일반적인 순서로 진행해도 됩니다."
    )
    size_text = (
        "짧은 task와 작은 subtask 분해에서 완료율이 더 높습니다."
        if short_completion_rate >= long_completion_rate + 0.2
        or small_subtask_completion_rate >= large_subtask_completion_rate + 0.2
        else "task 크기에 따른 완료율 차이는 크지 않습니다."
    )
    difficulty_text = _difficulty_summary(difficulty_completion_rates)
    return (
        f"최근 {history_count}개의 task 중 {completed_count}개를 완료했고 전체 완료율은 {completion_text}입니다. "
        f"{avg_completion_text} {delay_text} {size_text} {difficulty_text} "
        "새 subtask는 사용자가 바로 시작하기 쉬운 크기로 나누고, 부담이 큰 작업은 짧은 준비 단계부터 시작하도록 추천하세요."
    )


def _difficulty_summary(difficulty_completion_rates: dict[str, float]) -> str:
    valid_rates = {
        key: value for key, value in difficulty_completion_rates.items() if value > 0
    }
    if not valid_rates:
        return "난이도별 차이는 뚜렷하지 않습니다."
    best_level = max(valid_rates, key=valid_rates.get)
    worst_level = min(valid_rates, key=valid_rates.get)
    if best_level == worst_level:
        return "난이도별 완료율 차이는 크지 않습니다."
    if valid_rates[best_level] - valid_rates[worst_level] < 0.15:
        return "난이도별 완료율 차이는 크지 않습니다."
    return (
        f"{best_level} 난이도 task의 완료율이 더 높고 {worst_level} 난이도 task에서 이탈이 더 많습니다."
    )


def _completion_rate_for(
    tasks: list[TaskResponse],
    predicate: Callable[[TaskResponse], bool],
) -> float:
    matched = [task for task in tasks if predicate(task)]
    if not matched:
        return 0.0
    return _safe_ratio(sum(1 for task in matched if _is_completed(task)), len(matched))


def _safe_ratio(numerator: int, denominator: int) -> float:
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


def _iso(value: datetime | None) -> str | None:
    if value is None:
        return None
    return value.isoformat()


def _string_value(value: Any) -> str | None:
    if value is None:
        return None
    return str(value)


def _percent_text(value: float) -> str:
    return f"{round(value * 100)}%"
