import unittest
from typing import Any

from app.providers.gemini_provider import GeminiMediatorResult
from app.repositories.mediator_run_repository import MediatorRunRecord
from app.repositories.raw_input_repository import RawTaskInputRecord
from app.repositories.today_context_repository import TodayContextCounts
from app.schemas.mediator import ADHDReasoning, MediatorOutput, MediatorSubtask
from app.schemas.task import TaskSource
from app.schemas.task_candidate import (
    TaskCandidateResponse,
    TaskCandidateStatus,
    TaskDifficulty,
    TaskEnergyRequired,
    TaskPriority,
)
from app.schemas.task_intake import RawTaskInputStatus
from app.services.mediator_service import MediatorService
from app.services.today_planning_service import (
    TASK_COUNT_LIMIT_WARNING,
    TodayContext,
    TodayPlanningService,
)
from app.services.user_task_pattern_service import UserTaskPatternAnalysis


USER_ID = "00000000-0000-4000-8000-000000000001"
PROFILE_ID = "00000000-0000-4000-8000-000000000002"
RAW_INPUT_ID = "00000000-0000-4000-8000-000000000003"
CANDIDATE_ID = "00000000-0000-4000-8000-000000000004"
MEDIATOR_RUN_ID = "00000000-0000-4000-8000-000000000005"


def enum_value(value: object) -> object:
    return getattr(value, "value", value)


def make_raw_input_record(
    *,
    client_metadata: dict[str, Any] | None = None,
) -> RawTaskInputRecord:
    return RawTaskInputRecord(
        id=RAW_INPUT_ID,
        user_id=USER_ID,
        profile_id=PROFILE_ID,
        raw_text="컴비전 과제 해야 함",
        source=TaskSource.MANUAL.value,
        status=RawTaskInputStatus.RECEIVED.value,
        client_timezone="Asia/Seoul",
        client_metadata=client_metadata or {},
        error_message=None,
        created_at=None,
        updated_at=None,
    )


def make_today_context() -> TodayContext:
    return TodayContext(
        timezone="Asia/Seoul",
        today_date="2026-05-11",
        day_start="2026-05-11T00:00:00+09:00",
        day_end="2026-05-12T00:00:00+09:00",
        today_task_count=1,
        today_estimated_minutes=30,
        today_reminder_count=1,
    )


def make_mediator_run_record(
    *,
    user_id: str = USER_ID,
    raw_input_id: str = RAW_INPUT_ID,
    model_name: str = "fake-gemini",
    input_context: dict[str, Any] | None = None,
    profile_id: str | None = PROFILE_ID,
    prompt_version_id: str | None = None,
    status: str = "started",
    error_message: str | None = None,
) -> MediatorRunRecord:
    return MediatorRunRecord(
        id=MEDIATOR_RUN_ID,
        user_id=user_id,
        profile_id=profile_id,
        raw_input_id=raw_input_id,
        prompt_version_id=prompt_version_id,
        model_name=model_name,
        input_context=input_context or {},
        raw_model_output=None,
        parsed_output=None,
        status=status,
        error_message=error_message,
        started_at=None,
        completed_at=None,
        created_at=None,
        updated_at=None,
    )


def make_mediator_output() -> MediatorOutput:
    return MediatorOutput(
        task_title="컴퓨터비전 과제 제출 준비",
        description="과제 요구사항을 확인하고 첫 단계만 시작한다.",
        due_at=None,
        priority=TaskPriority.MEDIUM,
        estimated_minutes=60,
        difficulty=TaskDifficulty.MEDIUM,
        energy_required=TaskEnergyRequired.MEDIUM,
        next_action="과제 파일 열기",
        subtasks=[
            MediatorSubtask(
                title="과제 파일 열기",
                estimated_minutes=5,
                is_next_action=True,
                energy_required=TaskEnergyRequired.LOW,
            )
        ],
        recommended_today=["첫 단계만 오늘 시작 가능"],
        reminders=[],
        overload_warning=None,
        clarification_questions=[],
        adhd_reasoning=ADHDReasoning(
            detected_risks=[],
            intervention_used=["small_next_action"],
            explanation_for_user="작게 시작할 수 있도록 첫 행동을 잡았다.",
        ),
        confidence=0.82,
    )


def make_candidate_response(output: MediatorOutput) -> TaskCandidateResponse:
    return TaskCandidateResponse(
        id=CANDIDATE_ID,
        user_id=USER_ID,
        raw_input_id=RAW_INPUT_ID,
        mediator_run_id=MEDIATOR_RUN_ID,
        title=output.task_title,
        description=output.description,
        due_at=output.due_at,
        priority=output.priority,
        estimated_minutes=output.estimated_minutes,
        energy_required=output.energy_required,
        difficulty=output.difficulty,
        next_action=output.next_action,
        recommended_today=bool(output.recommended_today),
        today_reason="\n".join(output.recommended_today)
        if output.recommended_today
        else None,
        overload_warning=output.overload_warning,
        confidence=output.confidence,
        status=TaskCandidateStatus.DRAFT,
        model_payload=output.model_dump(mode="json"),
        subtasks=[
            {
                "id": f"00000000-0000-4000-8000-{index + 100:012d}",
                "candidate_id": CANDIDATE_ID,
                "title": subtask.title,
                "order_index": index,
                "estimated_minutes": subtask.estimated_minutes,
                "is_next_action": subtask.is_next_action,
                "energy_required": subtask.energy_required,
            }
            for index, subtask in enumerate(output.subtasks)
        ],
        reminders=[],
    )


class FakeRawInputRepository:
    def __init__(
        self,
        events: list[str],
        *,
        record: RawTaskInputRecord | None = None,
    ) -> None:
        self.events = events
        self.record = record or make_raw_input_record()
        self.get_calls: list[dict[str, object]] = []
        self.status_updates: list[dict[str, object]] = []

    def get(self, *, user_id: str, raw_input_id: str) -> RawTaskInputRecord:
        self.events.append("raw.get")
        self.get_calls.append({"user_id": user_id, "raw_input_id": raw_input_id})
        return self.record

    def update_status(
        self,
        *,
        user_id: str,
        raw_input_id: str,
        status: RawTaskInputStatus | str,
        error_message: str | None = None,
    ) -> RawTaskInputRecord:
        status_value = str(enum_value(status))
        self.events.append(f"raw.status:{status_value}")
        self.status_updates.append(
            {
                "user_id": user_id,
                "raw_input_id": raw_input_id,
                "status": status_value,
                "error_message": error_message,
            }
        )
        return self.record


class FakeMediatorRunRepository:
    def __init__(self, events: list[str]) -> None:
        self.events = events
        self.start_calls: list[dict[str, object]] = []
        self.succeeded_calls: list[dict[str, object]] = []
        self.failed_calls: list[dict[str, object]] = []

    def start(
        self,
        *,
        user_id: str,
        raw_input_id: str,
        model_name: str,
        input_context: dict[str, Any],
        profile_id: str | None = None,
        prompt_version_id: str | None = None,
    ) -> MediatorRunRecord:
        self.events.append("run.start")
        self.start_calls.append(
            {
                "user_id": user_id,
                "raw_input_id": raw_input_id,
                "model_name": model_name,
                "input_context": input_context,
                "profile_id": profile_id,
                "prompt_version_id": prompt_version_id,
            }
        )
        return make_mediator_run_record(
            user_id=user_id,
            raw_input_id=raw_input_id,
            model_name=model_name,
            input_context=input_context,
            profile_id=profile_id,
            prompt_version_id=prompt_version_id,
        )

    def mark_succeeded(
        self,
        *,
        user_id: str,
        run_id: str,
        raw_model_output: dict[str, Any],
        parsed_output: dict[str, Any],
    ) -> MediatorRunRecord:
        self.events.append("run.succeeded")
        self.succeeded_calls.append(
            {
                "user_id": user_id,
                "run_id": run_id,
                "raw_model_output": raw_model_output,
                "parsed_output": parsed_output,
            }
        )
        return make_mediator_run_record(
            user_id=user_id,
            raw_input_id=RAW_INPUT_ID,
            model_name="fake-gemini",
            input_context={},
            status="succeeded",
        )

    def mark_failed(
        self,
        *,
        user_id: str,
        run_id: str,
        error_message: str,
        raw_model_output: dict[str, Any] | None = None,
        parsed_output: dict[str, Any] | None = None,
    ) -> MediatorRunRecord:
        self.events.append("run.failed")
        self.failed_calls.append(
            {
                "user_id": user_id,
                "run_id": run_id,
                "error_message": error_message,
                "raw_model_output": raw_model_output,
                "parsed_output": parsed_output,
            }
        )
        return make_mediator_run_record(
            user_id=user_id,
            raw_input_id=RAW_INPUT_ID,
            model_name="fake-gemini",
            input_context={},
            status="failed",
            error_message=error_message,
        )


class FakeTaskCandidateRepository:
    def __init__(self, events: list[str]) -> None:
        self.events = events
        self.create_calls: list[dict[str, object]] = []

    def create_from_mediator_output(
        self,
        *,
        user_id: str,
        raw_input_id: str,
        mediator_run_id: str | None,
        output: MediatorOutput,
        profile_id: str | None = None,
    ) -> TaskCandidateResponse:
        self.events.append("candidate.create")
        self.create_calls.append(
            {
                "user_id": user_id,
                "raw_input_id": raw_input_id,
                "mediator_run_id": mediator_run_id,
                "output": output,
                "profile_id": profile_id,
            }
        )
        return make_candidate_response(output)


class FakeGeminiProvider:
    _model_name = "fake-gemini"

    def __init__(self, events: list[str], *, error: Exception | None = None) -> None:
        self.events = events
        self.error = error
        self.result_output: MediatorOutput | None = None
        self.calls: list[dict[str, object]] = []

    def generate_mediator_result(
        self,
        *,
        raw_text: str,
        source: str,
        user_context: dict[str, Any] | None = None,
        today_context: dict[str, Any] | None = None,
        existing_tasks: list[dict[str, Any]] | None = None,
        user_patterns: dict[str, Any] | None = None,
    ) -> GeminiMediatorResult:
        self.events.append("gemini.generate")
        self.calls.append(
            {
                "raw_text": raw_text,
                "source": source,
                "user_context": user_context,
                "today_context": today_context,
                "existing_tasks": existing_tasks,
                "user_patterns": user_patterns,
            }
        )
        if self.error is not None:
            raise self.error
        output = self.result_output or make_mediator_output()
        return GeminiMediatorResult(
            output=output,
            raw_text='{"task_title":"컴퓨터비전 과제 제출 준비"}',
            parsed=output.model_dump(mode="json"),
            rendered_prompt="rendered prompt",
            model_name="fake-gemini",
            prompt_version="test-v1",
        )


class FakeTodayPlanningService:
    def __init__(self, events: list[str]) -> None:
        self.events = events
        self.context = make_today_context()
        self.get_calls: list[dict[str, object]] = []
        self.guard_calls: list[dict[str, object]] = []

    def get_today_context(self, *, user_id: str, timezone: str) -> TodayContext:
        self.events.append("today.get")
        self.get_calls.append({"user_id": user_id, "timezone": timezone})
        return self.context

    def apply_capacity_guard(
        self,
        *,
        output: MediatorOutput,
        today_context: TodayContext,
    ) -> MediatorOutput:
        self.events.append("today.guard")
        self.guard_calls.append({"output": output, "today_context": today_context})
        return output.model_copy(
            update={
                "recommended_today": ["guarded today reason"],
                "overload_warning": "guarded by capacity",
            }
        )


class FakeTodayContextRepository:
    def __init__(self, counts: TodayContextCounts) -> None:
        self.counts = counts
        self.calls: list[dict[str, object]] = []

    def get_today_context_counts(
        self,
        *,
        user_id: str,
        day_start: object,
        day_end: object,
    ) -> TodayContextCounts:
        self.calls.append(
            {
                "user_id": user_id,
                "day_start": day_start,
                "day_end": day_end,
            }
        )
        return self.counts


class FakeUserTaskPatternService:
    def __init__(
        self,
        events: list[str],
        *,
        error: Exception | None = None,
        analysis: UserTaskPatternAnalysis | None = None,
    ) -> None:
        self.events = events
        self.error = error
        self.analysis = analysis or UserTaskPatternAnalysis(
            data_sufficient=True,
            history_count=8,
            completed_count=6,
            existing_tasks=[],
            prompt_payload={
                "task_count_used_for_analysis": 8,
                "completion_rate": 0.75,
                "avg_delay_days": 2.1,
                "avg_completion_hours": 18.0,
                "prefers_small_tasks": True,
                "procrastination_level": "high",
                "task_completion_style": "incremental",
                "difficulty_dropoff": False,
            },
        )
        self.calls: list[dict[str, object]] = []

    def analyze(self, *, user_id: str) -> UserTaskPatternAnalysis:
        self.events.append("patterns.analyze")
        self.calls.append({"user_id": user_id})
        if self.error is not None:
            raise self.error
        return self.analysis


class FakeFallbackMediatorService:
    def __init__(self, events: list[str]) -> None:
        self.events = events
        self.calls: list[dict[str, object]] = []

    def create_output(
        self,
        *,
        raw_text: str,
        user_context: dict[str, object] | None = None,
        today_context: dict[str, object] | None = None,
        client_metadata: dict[str, object] | None = None,
        user_patterns: dict[str, object] | None = None,
    ) -> MediatorOutput:
        self.events.append("fallback.generate")
        self.calls.append(
            {
                "raw_text": raw_text,
                "user_context": user_context,
                "today_context": today_context,
                "client_metadata": client_metadata,
                "user_patterns": user_patterns,
            }
        )
        return make_mediator_output().model_copy(
            update={
                "task_title": "fallback candidate",
                "description": "fallback description",
            }
        )


class MediatorServiceTest(unittest.TestCase):
    def make_service(
        self,
        *,
        gemini_error: Exception | None = None,
    ) -> tuple[
        MediatorService,
        list[str],
        FakeRawInputRepository,
        FakeMediatorRunRepository,
        FakeTaskCandidateRepository,
        FakeGeminiProvider,
        FakeTodayPlanningService,
        FakeFallbackMediatorService,
        FakeUserTaskPatternService,
    ]:
        events: list[str] = []
        raw_input_repository = FakeRawInputRepository(events)
        mediator_run_repository = FakeMediatorRunRepository(events)
        task_candidate_repository = FakeTaskCandidateRepository(events)
        gemini_provider = FakeGeminiProvider(events, error=gemini_error)
        today_planning_service = FakeTodayPlanningService(events)
        fallback_mediator_service = FakeFallbackMediatorService(events)
        user_task_pattern_service = FakeUserTaskPatternService(events)
        service = MediatorService(
            raw_input_repository=raw_input_repository,
            mediator_run_repository=mediator_run_repository,
            task_candidate_repository=task_candidate_repository,
            gemini_provider=gemini_provider,
            today_planning_service=today_planning_service,
            fallback_mediator_service=fallback_mediator_service,
            user_task_pattern_service=user_task_pattern_service,
        )
        return (
            service,
            events,
            raw_input_repository,
            mediator_run_repository,
            task_candidate_repository,
            gemini_provider,
            today_planning_service,
            fallback_mediator_service,
            user_task_pattern_service,
        )

    def test_create_candidate_records_successful_mvp1_flow(self) -> None:
        (
            service,
            events,
            raw_input_repository,
            mediator_run_repository,
            task_candidate_repository,
            gemini_provider,
            today_planning_service,
            _fallback_mediator_service,
            user_task_pattern_service,
        ) = self.make_service()

        candidate = service.create_candidate(
            user_id=USER_ID,
            raw_input_id=RAW_INPUT_ID,
            client_timezone=None,
            user_context={"energy_now": "medium"},
            profile_id=None,
        )

        self.assertEqual(
            events,
            [
                "raw.get",
                "raw.status:processing",
                "today.get",
                "patterns.analyze",
                "run.start",
                "gemini.generate",
                "today.guard",
                "candidate.create",
                "run.succeeded",
                "raw.status:candidate_ready",
            ],
        )
        self.assertEqual(str(candidate.id), CANDIDATE_ID)
        self.assertEqual(candidate.title, "컴퓨터비전 과제 제출 준비")
        self.assertEqual(candidate.overload_warning, "guarded by capacity")

        self.assertEqual(today_planning_service.get_calls[0]["timezone"], "Asia/Seoul")
        start_call = mediator_run_repository.start_calls[0]
        self.assertEqual(start_call["model_name"], "fake-gemini")
        self.assertEqual(start_call["profile_id"], PROFILE_ID)
        self.assertEqual(start_call["input_context"]["raw_text"], "컴비전 과제 해야 함")
        self.assertEqual(start_call["input_context"].get("existing_tasks"), None)
        self.assertEqual(
            start_call["input_context"]["user_patterns"]["prefers_small_tasks"],
            True,
        )

        gemini_call = gemini_provider.calls[0]
        self.assertEqual(gemini_call["raw_text"], "컴비전 과제 해야 함")
        self.assertEqual(gemini_call["source"], TaskSource.MANUAL.value)
        self.assertEqual(gemini_call["existing_tasks"], [])
        self.assertEqual(
            gemini_call["user_patterns"]["procrastination_level"],
            "high",
        )
        self.assertEqual(user_task_pattern_service.calls[0]["user_id"], USER_ID)

        create_call = task_candidate_repository.create_calls[0]
        self.assertEqual(create_call["mediator_run_id"], MEDIATOR_RUN_ID)
        self.assertEqual(create_call["profile_id"], PROFILE_ID)
        self.assertEqual(
            create_call["output"].overload_warning,
            "guarded by capacity",
        )

        succeeded_call = mediator_run_repository.succeeded_calls[0]
        self.assertEqual(
            succeeded_call["raw_model_output"]["model_name"],
            "fake-gemini",
        )
        self.assertEqual(
            succeeded_call["parsed_output"]["overload_warning"],
            "guarded by capacity",
        )

        self.assertEqual(
            [update["status"] for update in raw_input_repository.status_updates],
            ["processing", "candidate_ready"],
        )

    def test_create_candidate_applies_real_capacity_guard_to_saved_candidate(
        self,
    ) -> None:
        events: list[str] = []
        raw_input_repository = FakeRawInputRepository(events)
        mediator_run_repository = FakeMediatorRunRepository(events)
        task_candidate_repository = FakeTaskCandidateRepository(events)
        gemini_provider = FakeGeminiProvider(events)
        today_context_repository = FakeTodayContextRepository(
            TodayContextCounts(
                today_task_count=3,
                today_estimated_minutes=30,
                today_reminder_count=1,
            )
        )
        service = MediatorService(
            raw_input_repository=raw_input_repository,
            mediator_run_repository=mediator_run_repository,
            task_candidate_repository=task_candidate_repository,
            gemini_provider=gemini_provider,
            today_planning_service=TodayPlanningService(today_context_repository),
            fallback_mediator_service=FakeFallbackMediatorService(events),
            user_task_pattern_service=FakeUserTaskPatternService(events),
        )

        candidate = service.create_candidate(
            user_id=USER_ID,
            raw_input_id=RAW_INPUT_ID,
            client_timezone="Asia/Seoul",
            user_context={"energy_now": "medium"},
        )

        self.assertEqual(len(today_context_repository.calls), 1)
        self.assertEqual(today_context_repository.calls[0]["user_id"], USER_ID)

        create_call = task_candidate_repository.create_calls[0]
        guarded_output = create_call["output"]
        self.assertEqual(guarded_output.recommended_today, [])
        self.assertEqual(guarded_output.overload_warning, TASK_COUNT_LIMIT_WARNING)

        self.assertFalse(candidate.recommended_today)
        self.assertIsNone(candidate.today_reason)
        self.assertEqual(candidate.overload_warning, TASK_COUNT_LIMIT_WARNING)

        succeeded_call = mediator_run_repository.succeeded_calls[0]
        self.assertEqual(succeeded_call["parsed_output"]["recommended_today"], [])
        self.assertEqual(
            succeeded_call["parsed_output"]["overload_warning"],
            TASK_COUNT_LIMIT_WARNING,
        )

    def test_create_candidate_applies_equal_time_allocation_from_client_metadata(self) -> None:
        (
            service,
            _events,
            raw_input_repository,
            mediator_run_repository,
            task_candidate_repository,
            gemini_provider,
            _today_planning_service,
            _fallback_mediator_service,
            _user_task_pattern_service,
        ) = self.make_service()
        raw_input_repository.record = make_raw_input_record(
            client_metadata={
                "default_duration_seconds": 3600,
                "subtask_generation_prompt": (
                    "subtask_prompt_mode=focus_routine\n"
                    "time_allocation=equal"
                ),
            }
        )
        gemini_provider.result_output = make_mediator_output().model_copy(
            update={
                "estimated_minutes": 60,
                "subtasks": [
                    MediatorSubtask(
                        title="자료 열기",
                        estimated_minutes=5,
                        is_next_action=True,
                        energy_required=TaskEnergyRequired.LOW,
                    ),
                    MediatorSubtask(
                        title="핵심 내용 정리",
                        estimated_minutes=30,
                        is_next_action=False,
                        energy_required=TaskEnergyRequired.MEDIUM,
                    ),
                    MediatorSubtask(
                        title="초안 작성",
                        estimated_minutes=25,
                        is_next_action=False,
                        energy_required=TaskEnergyRequired.MEDIUM,
                    ),
                ],
            }
        )

        candidate = service.create_candidate(
            user_id=USER_ID,
            raw_input_id=RAW_INPUT_ID,
            client_timezone="Asia/Seoul",
            user_context={"energy_now": "medium"},
        )

        start_call = mediator_run_repository.start_calls[0]
        self.assertEqual(start_call["input_context"]["time_allocation"], "equal")

        create_call = task_candidate_repository.create_calls[0]
        self.assertEqual(
            [subtask.estimated_minutes for subtask in create_call["output"].subtasks],
            [5, 28, 27],
        )
        self.assertEqual(create_call["output"].estimated_minutes, 60)
        self.assertEqual(
            [subtask.estimated_minutes for subtask in candidate.subtasks],
            [5, 28, 27],
        )

    def test_create_candidate_marks_failed_when_gemini_fails(self) -> None:
        (
            service,
            events,
            raw_input_repository,
            mediator_run_repository,
            task_candidate_repository,
            _gemini_provider,
            _today_planning_service,
            _fallback_mediator_service,
            _user_task_pattern_service,
        ) = self.make_service(gemini_error=RuntimeError("schema mismatch"))

        with self.assertRaisesRegex(RuntimeError, "schema mismatch"):
            service.create_candidate(user_id=USER_ID, raw_input_id=RAW_INPUT_ID)

        self.assertEqual(
            events,
            [
                "raw.get",
                "raw.status:processing",
                "today.get",
                "patterns.analyze",
                "run.start",
                "gemini.generate",
                "run.failed",
                "raw.status:failed",
            ],
        )
        self.assertEqual(task_candidate_repository.create_calls, [])
        self.assertEqual(mediator_run_repository.succeeded_calls, [])
        self.assertEqual(
            mediator_run_repository.failed_calls[0]["error_message"],
            "schema mismatch",
        )
        self.assertEqual(raw_input_repository.status_updates[-1]["status"], "failed")
        self.assertEqual(
            raw_input_repository.status_updates[-1]["error_message"],
            "schema mismatch",
        )

    def test_create_candidate_falls_back_when_pattern_analysis_fails(self) -> None:
        events: list[str] = []
        raw_input_repository = FakeRawInputRepository(events)
        mediator_run_repository = FakeMediatorRunRepository(events)
        task_candidate_repository = FakeTaskCandidateRepository(events)
        gemini_provider = FakeGeminiProvider(events)
        today_planning_service = FakeTodayPlanningService(events)
        user_task_pattern_service = FakeUserTaskPatternService(
            events,
            error=RuntimeError("pattern lookup unavailable"),
        )
        service = MediatorService(
            raw_input_repository=raw_input_repository,
            mediator_run_repository=mediator_run_repository,
            task_candidate_repository=task_candidate_repository,
            gemini_provider=gemini_provider,
            today_planning_service=today_planning_service,
            fallback_mediator_service=FakeFallbackMediatorService(events),
            user_task_pattern_service=user_task_pattern_service,
        )

        service.create_candidate(user_id=USER_ID, raw_input_id=RAW_INPUT_ID)

        self.assertIn("patterns.analyze", events)
        start_call = mediator_run_repository.start_calls[0]
        self.assertEqual(start_call["input_context"].get("existing_tasks"), None)
        self.assertEqual(start_call["input_context"]["user_patterns"], {})

        gemini_call = gemini_provider.calls[0]
        self.assertEqual(gemini_call["existing_tasks"], [])
        self.assertEqual(gemini_call["user_patterns"], {})

    def test_create_candidate_uses_fallback_when_gemini_is_temporarily_unavailable(self) -> None:
        (
            service,
            events,
            raw_input_repository,
            mediator_run_repository,
            task_candidate_repository,
            _gemini_provider,
            today_planning_service,
            fallback_mediator_service,
            _user_task_pattern_service,
        ) = self.make_service(
            gemini_error=RuntimeError(
                "google.genai.errors.ServerError: 503 UNAVAILABLE: This model is currently experiencing high demand. Please try again later."
            )
        )

        candidate = service.create_candidate(
            user_id=USER_ID,
            raw_input_id=RAW_INPUT_ID,
            client_timezone="Asia/Seoul",
            user_context={"energy_now": "medium"},
        )

        self.assertEqual(
            events,
            [
                "raw.get",
                "raw.status:processing",
                "today.get",
                "patterns.analyze",
                "run.start",
                "gemini.generate",
                "fallback.generate",
                "today.guard",
                "candidate.create",
                "run.succeeded",
                "raw.status:candidate_ready",
            ],
        )
        self.assertEqual(candidate.title, "fallback candidate")
        self.assertEqual(today_planning_service.get_calls[0]["timezone"], "Asia/Seoul")
        self.assertEqual(len(fallback_mediator_service.calls), 1)
        self.assertEqual(
            task_candidate_repository.create_calls[0]["output"].task_title,
            "fallback candidate",
        )
        self.assertTrue(
            mediator_run_repository.succeeded_calls[0]["raw_model_output"]["fallback_used"]
        )
        self.assertEqual(
            [update["status"] for update in raw_input_repository.status_updates],
            ["processing", "candidate_ready"],
        )


if __name__ == "__main__":
    unittest.main()
