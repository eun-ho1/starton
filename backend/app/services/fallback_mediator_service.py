from datetime import datetime
from typing import Any

from app.schemas.mediator import ADHDReasoning, MediatorOutput, MediatorSubtask
from app.schemas.task_candidate import (
    TaskDifficulty,
    TaskEnergyRequired,
    TaskPriority,
)


class FallbackMediatorService:
    def create_output(
        self,
        *,
        raw_text: str,
        user_context: dict[str, Any] | None = None,
        today_context: dict[str, Any] | None = None,
        client_metadata: dict[str, Any] | None = None,
        user_patterns: dict[str, Any] | None = None,
    ) -> MediatorOutput:
        title = _build_title(raw_text)
        metadata = client_metadata or {}
        patterns = user_patterns or {}
        difficulty = _difficulty_value(metadata.get("difficulty"))
        energy_required = _energy_value(
            (user_context or {}).get("energy_now"),
            difficulty=difficulty,
        )
        estimated_minutes = _estimated_minutes(metadata)
        due_at = _parse_due_at(metadata.get("due_date"))
        small_steps = (
            "small_steps" in str(metadata.get("subtask_generation_prompt") or "").lower()
            or bool(patterns.get("prefers_small_tasks"))
            or str(patterns.get("procrastination_level") or "").lower() == "high"
            or str(patterns.get("task_completion_style") or "").lower() == "incremental"
        )

        subtasks = _build_subtasks(
            title=title,
            estimated_minutes=estimated_minutes,
            small_steps=small_steps,
            energy_required=energy_required,
        )
        next_action = subtasks[0].title

        overload_warning = None
        available_minutes = (user_context or {}).get("available_minutes_today")
        if isinstance(available_minutes, int) and isinstance(estimated_minutes, int):
            if estimated_minutes > available_minutes:
                overload_warning = (
                    "오늘 한 번에 끝내기보다 가장 작은 시작 단계부터 진행하는 쪽을 추천합니다."
                )

        return MediatorOutput(
            task_title=title,
            description=_description_for(title, small_steps=small_steps),
            due_at=due_at,
            priority=_priority_value(due_at=due_at),
            estimated_minutes=estimated_minutes,
            difficulty=difficulty,
            energy_required=energy_required,
            next_action=next_action,
            subtasks=subtasks,
            recommended_today=[item.title for item in subtasks[:2]],
            reminders=[],
            overload_warning=overload_warning,
            clarification_questions=[],
            adhd_reasoning=ADHDReasoning(
                detected_risks=_detected_risks(
                    estimated_minutes=estimated_minutes,
                    due_at=due_at,
                    energy_required=energy_required,
                ),
                intervention_used=[
                    "created_five_minute_next_action",
                    "split_into_subtasks",
                    "fallback_planning_strategy",
                ],
                explanation_for_user=(
                    "AI 응답이 일시적으로 불안정해서 기본 계획 전략으로 바로 시작 가능한 작은 단계부터 제안했습니다."
                ),
            ),
            confidence=0.55,
        )


def _build_title(raw_text: str) -> str:
    lines = [line.strip() for line in raw_text.splitlines() if line.strip()]
    if not lines:
        return "새 작업 정리"
    return lines[0][:200].strip() or "새 작업 정리"


def _description_for(title: str, *, small_steps: bool) -> str:
    if small_steps:
        return f"{title} 작업을 바로 시작 가능한 작은 단계 중심으로 나눴습니다."
    return f"{title} 작업을 준비와 실행 순서로 정리했습니다."


def _build_subtasks(
    *,
    title: str,
    estimated_minutes: int | None,
    small_steps: bool,
    energy_required: TaskEnergyRequired,
) -> list[MediatorSubtask]:
    titles = _cleanup_titles(title, small_steps=small_steps) or _generic_titles(
        title,
        small_steps=small_steps,
    )
    minutes = _step_minutes(estimated_minutes, count=len(titles), small_steps=small_steps)
    return [
        MediatorSubtask(
            title=subtask_title[:200],
            estimated_minutes=minutes[index],
            is_next_action=index == 0,
            energy_required=TaskEnergyRequired.LOW if index == 0 else energy_required,
        )
        for index, subtask_title in enumerate(titles)
    ]


def _cleanup_titles(title: str, *, small_steps: bool) -> list[str] | None:
    normalized = title.lower()
    if "청소" not in title and "clean" not in normalized:
        return None
    if small_steps:
        return [
            "정리할 구역 확인",
            "책상 정리",
            "바닥 정리",
            "쓰레기 처리",
            "최종 점검",
        ]
    return [
        "정리할 구역 확인",
        "큰 물건 정리",
        "바닥과 표면 정리",
        "쓰레기 처리",
        "최종 점검",
    ]


def _generic_titles(title: str, *, small_steps: bool) -> list[str]:
    if small_steps:
        return [
            f"{title} 관련 자료 열기",
            f"{title} 해야 할 일 한 줄로 적기",
            f"{title} 첫 단계 10분만 진행하기",
            f"{title} 진행한 내용 짧게 정리하기",
        ]
    return [
        f"{title} 준비물이나 자료 확인",
        f"{title} 핵심 단계 정리",
        f"{title} 첫 실행 단계 진행",
        f"{title} 결과 확인",
    ]


def _step_minutes(
    estimated_minutes: int | None,
    *,
    count: int,
    small_steps: bool,
) -> list[int | None]:
    if estimated_minutes is None or estimated_minutes <= 0:
        if small_steps:
            return [5, 10, 10, 5, 5][:count]
        return [5, 10, 15, 5, 5][:count]
    if small_steps:
        base = [5, 10, 10, 5, 5]
    else:
        base = [5, 10, max(10, estimated_minutes // 3), 5, 5]
    return [base[index] if index < len(base) else 5 for index in range(count)]


def _priority_value(*, due_at: datetime | None) -> TaskPriority:
    if due_at is not None:
        return TaskPriority.HIGH
    return TaskPriority.MEDIUM


def _difficulty_value(value: Any) -> TaskDifficulty:
    normalized = str(value or "").strip().lower()
    if normalized in {"low", "easy", "낮음"}:
        return TaskDifficulty.LOW
    if normalized in {"high", "hard", "높음"}:
        return TaskDifficulty.HIGH
    return TaskDifficulty.MEDIUM


def _energy_value(value: Any, *, difficulty: TaskDifficulty) -> TaskEnergyRequired:
    normalized = str(value or "").strip().lower()
    if normalized in {"low", "낮음"}:
        return TaskEnergyRequired.LOW
    if normalized in {"high", "높음"}:
        return TaskEnergyRequired.HIGH
    if difficulty == TaskDifficulty.HIGH:
        return TaskEnergyRequired.HIGH
    return TaskEnergyRequired.MEDIUM


def _estimated_minutes(metadata: dict[str, Any]) -> int | None:
    duration_seconds = metadata.get("default_duration_seconds")
    if isinstance(duration_seconds, bool):
        return None
    if isinstance(duration_seconds, (int, float)) and duration_seconds > 0:
        return max(5, int(duration_seconds // 60))
    return None


def _parse_due_at(value: Any) -> datetime | None:
    if not isinstance(value, str):
        return None
    cleaned = value.strip()
    if not cleaned:
        return None
    try:
        return datetime.fromisoformat(cleaned.replace("Z", "+00:00"))
    except ValueError:
        return None


def _detected_risks(
    *,
    estimated_minutes: int | None,
    due_at: datetime | None,
    energy_required: TaskEnergyRequired,
) -> list[str]:
    risks: list[str] = []
    if due_at is None:
        risks.append("unclear_due_date")
    if isinstance(estimated_minutes, int) and estimated_minutes >= 90:
        risks.append("large_task")
    if energy_required == TaskEnergyRequired.HIGH:
        risks.append("high_energy_task")
    return risks
