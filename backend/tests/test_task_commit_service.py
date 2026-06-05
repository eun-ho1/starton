import unittest
from datetime import datetime, timezone
from typing import Any

from app.schemas.reminder import ReminderResponse, ReminderType
from app.schemas.task import (
    SubtaskResponse,
    TaskResponse,
    TaskSource,
    TaskStatus,
)
from app.schemas.task_candidate import (
    CandidateReminderResponse,
    CandidateSubtaskResponse,
    TaskCandidateResponse,
    TaskCandidateStatus,
    TaskDifficulty,
    TaskEnergyRequired,
    TaskPriority,
)
from app.services.task_commit_service import TaskCommitError, TaskCommitService


USER_ID = "00000000-0000-4000-8000-000000000001"
CANDIDATE_ID = "00000000-0000-4000-8000-000000000002"
RAW_INPUT_ID = "00000000-0000-4000-8000-000000000003"
MEDIATOR_RUN_ID = "00000000-0000-4000-8000-000000000004"
TASK_ID = "00000000-0000-4000-8000-000000000005"
SUBTASK_ID_1 = "00000000-0000-4000-8000-000000000006"
SUBTASK_ID_2 = "00000000-0000-4000-8000-000000000007"
REMINDER_ID_1 = "00000000-0000-4000-8000-000000000008"


def make_candidate(
    *,
    status: TaskCandidateStatus = TaskCandidateStatus.DRAFT,
    reminders: list[CandidateReminderResponse] | None = None,
) -> TaskCandidateResponse:
    return TaskCandidateResponse(
        id=CANDIDATE_ID,
        user_id=USER_ID,
        raw_input_id=RAW_INPUT_ID,
        mediator_run_id=MEDIATOR_RUN_ID,
        title="컴퓨터비전 과제 제출 준비",
        description="요구사항을 확인하고 첫 단계만 시작한다.",
        due_at=None,
        priority=TaskPriority.MEDIUM,
        estimated_minutes=60,
        energy_required=TaskEnergyRequired.MEDIUM,
        difficulty=TaskDifficulty.MEDIUM,
        next_action="과제 파일 열기",
        recommended_today=True,
        today_reason="첫 단계만 오늘 시작 가능",
        overload_warning=None,
        confidence=0.82,
        status=status,
        model_payload={"source": TaskSource.MANUAL.value},
        subtasks=[
            CandidateSubtaskResponse(
                id=SUBTASK_ID_1,
                candidate_id=CANDIDATE_ID,
                title="과제 파일 열기",
                order_index=0,
                estimated_minutes=5,
                is_next_action=True,
                energy_required=TaskEnergyRequired.LOW,
            ),
            CandidateSubtaskResponse(
                id=SUBTASK_ID_2,
                candidate_id=CANDIDATE_ID,
                title="요구사항 체크리스트 만들기",
                order_index=1,
                estimated_minutes=10,
                is_next_action=False,
                energy_required=TaskEnergyRequired.MEDIUM,
            ),
        ],
        reminders=reminders if reminders is not None else [make_candidate_reminder()],
    )


def make_candidate_reminder(
    *,
    reminder_id: str = REMINDER_ID_1,
    remind_at: datetime | None = datetime(2026, 5, 14, 12, 0, tzinfo=timezone.utc),
) -> CandidateReminderResponse:
    return CandidateReminderResponse(
        id=reminder_id,
        candidate_id=CANDIDATE_ID,
        remind_at=remind_at,
        message="딱 5분만 과제 파일 열기",
        type=ReminderType.START,
        escalation_level=0,
    )


class FakeTaskCandidateRepository:
    def __init__(self, candidate: TaskCandidateResponse | None) -> None:
        self.candidate = candidate
        self.mark_committed_calls: list[dict[str, str]] = []

    def get(self, *, user_id: str, candidate_id: str) -> TaskCandidateResponse:
        if self.candidate is None:
            raise ValueError("not found")
        return self.candidate

    def mark_committed(self, *, user_id: str, candidate_id: str) -> TaskCandidateResponse:
        self.mark_committed_calls.append({"user_id": user_id, "candidate_id": candidate_id})
        assert self.candidate is not None
        return self.candidate.model_copy(update={"status": TaskCandidateStatus.COMMITTED})


class FakeTaskRepository:
    def __init__(
        self,
        *,
        existing_task: TaskResponse | None = None,
        fail_create_task: bool = False,
        fail_create_task_error: Exception | None = None,
    ) -> None:
        self.existing_task = existing_task
        self.fail_create_task = fail_create_task
        self.fail_create_task_error = fail_create_task_error
        self.get_by_candidate_id_calls: list[dict[str, str]] = []
        self.created_task_payloads: list[dict[str, Any]] = []
        self.created_subtask_payloads: list[dict[str, Any]] = []
        self.created_reminder_payloads: list[dict[str, Any]] = []

    def get_by_candidate_id(self, *, user_id: str, candidate_id: str) -> TaskResponse | None:
        self.get_by_candidate_id_calls.append(
            {"user_id": user_id, "candidate_id": candidate_id}
        )
        return self.existing_task

    def create_task(self, payload: dict[str, Any]) -> TaskResponse:
        if self.fail_create_task_error is not None:
            raise self.fail_create_task_error
        if self.fail_create_task:
            raise RuntimeError("task insert failed")
        self.created_task_payloads.append(payload)
        return TaskResponse(
            id=TASK_ID,
            user_id=payload["user_id"],
            candidate_id=payload["candidate_id"],
            raw_input_id=payload["raw_input_id"],
            mediator_run_id=payload["mediator_run_id"],
            title=payload["title"],
            description=payload.get("description"),
            status=payload.get("status", TaskStatus.TODO),
            priority=payload.get("priority"),
            due_at=payload.get("due_at"),
            estimated_minutes=payload.get("estimated_minutes"),
            energy_required=payload.get("energy_required"),
            difficulty=payload.get("difficulty"),
            next_action=payload.get("next_action"),
            source=payload.get("source", TaskSource.AI),
            metadata=payload.get("metadata", {}),
        )

    def create_subtasks(
        self,
        *,
        user_id: str,
        task_id: str,
        payloads: list[dict[str, Any]],
    ) -> list[SubtaskResponse]:
        self.created_subtask_payloads.extend(payloads)
        return [
            SubtaskResponse(
                id=f"00000000-0000-4000-8000-00000000010{index}",
                task_id=task_id,
                user_id=user_id,
                candidate_subtask_id=payload["candidate_subtask_id"],
                title=payload["title"],
                order_index=payload["order_index"],
                estimated_minutes=payload.get("estimated_minutes"),
                status=payload["status"],
                is_next_action=payload["is_next_action"],
                energy_required=payload.get("energy_required"),
            )
            for index, payload in enumerate(payloads)
        ]

    def create_reminders(
        self,
        *,
        user_id: str,
        task_id: str,
        payloads: list[dict[str, Any]],
    ) -> list[ReminderResponse]:
        self.created_reminder_payloads.extend(payloads)
        return [
            ReminderResponse(
                id=f"00000000-0000-4000-8000-00000000020{index}",
                user_id=user_id,
                task_id=task_id,
                candidate_reminder_id=payload["candidate_reminder_id"],
                remind_at=payload["remind_at"],
                message=payload["message"],
                type=payload["type"],
                status=payload["status"],
                escalation_level=payload["escalation_level"],
            )
            for index, payload in enumerate(payloads)
        ]


class TaskCommitServiceTest(unittest.TestCase):
    def test_commit_candidate_creates_task_selected_subtasks_and_reminders(self) -> None:
        candidate_repo = FakeTaskCandidateRepository(make_candidate())
        task_repo = FakeTaskRepository()
        service = TaskCommitService(
            task_candidate_repository=candidate_repo,
            task_repository=task_repo,
        )

        result = service.commit_candidate(
            user_id=USER_ID,
            candidate_id=CANDIDATE_ID,
            edited_fields={"title": "컴비전 과제 1차 진행", "estimated_minutes": 45},
            selected_subtask_ids=[SUBTASK_ID_2],
            selected_reminder_ids=[REMINDER_ID_1],
        )

        self.assertEqual(str(result.candidate_id), CANDIDATE_ID)
        self.assertEqual(result.task.title, "컴비전 과제 1차 진행")
        self.assertEqual(result.task.estimated_minutes, 45)
        self.assertEqual(len(result.task.subtasks), 1)
        self.assertEqual(len(result.task.reminders), 1)
        self.assertEqual(
            task_repo.created_task_payloads[0]["metadata"]["selected_subtask_ids"],
            [SUBTASK_ID_2],
        )
        self.assertEqual(
            task_repo.created_subtask_payloads[0]["candidate_subtask_id"],
            SUBTASK_ID_2,
        )
        self.assertEqual(
            task_repo.created_reminder_payloads[0]["candidate_reminder_id"],
            REMINDER_ID_1,
        )
        self.assertEqual(candidate_repo.mark_committed_calls[0]["candidate_id"], CANDIDATE_ID)

    def test_empty_reminder_selection_skips_reminders(self) -> None:
        task_repo = FakeTaskRepository()
        service = TaskCommitService(
            task_candidate_repository=FakeTaskCandidateRepository(make_candidate()),
            task_repository=task_repo,
        )

        result = service.commit_candidate(
            user_id=USER_ID,
            candidate_id=CANDIDATE_ID,
            selected_reminder_ids=[],
        )

        self.assertEqual(result.task.reminders, [])
        self.assertEqual(task_repo.created_reminder_payloads, [])

    def test_unknown_edited_field_fails(self) -> None:
        service = TaskCommitService(
            task_candidate_repository=FakeTaskCandidateRepository(make_candidate()),
            task_repository=FakeTaskRepository(),
        )

        with self.assertRaises(TaskCommitError) as context:
            service.commit_candidate(
                user_id=USER_ID,
                candidate_id=CANDIDATE_ID,
                edited_fields={"user_id": "other"},
            )

        self.assertEqual(context.exception.code, "invalid_edited_fields")

    def test_invalid_subtask_selection_fails(self) -> None:
        service = TaskCommitService(
            task_candidate_repository=FakeTaskCandidateRepository(make_candidate()),
            task_repository=FakeTaskRepository(),
        )

        with self.assertRaises(TaskCommitError) as context:
            service.commit_candidate(
                user_id=USER_ID,
                candidate_id=CANDIDATE_ID,
                selected_subtask_ids=["00000000-0000-4000-8000-000000009999"],
            )

        self.assertEqual(context.exception.code, "invalid_subtask_selection")

    def test_unscheduled_reminder_is_skipped_by_default(self) -> None:
        candidate = make_candidate(reminders=[make_candidate_reminder(remind_at=None)])
        task_repo = FakeTaskRepository()
        service = TaskCommitService(
            task_candidate_repository=FakeTaskCandidateRepository(candidate),
            task_repository=task_repo,
        )

        result = service.commit_candidate(user_id=USER_ID, candidate_id=CANDIDATE_ID)

        self.assertEqual(result.task.reminders, [])
        self.assertEqual(task_repo.created_reminder_payloads, [])

    def test_explicit_selected_reminder_without_remind_at_fails(self) -> None:
        candidate = make_candidate(reminders=[make_candidate_reminder(remind_at=None)])
        service = TaskCommitService(
            task_candidate_repository=FakeTaskCandidateRepository(candidate),
            task_repository=FakeTaskRepository(),
        )

        with self.assertRaises(TaskCommitError) as context:
            service.commit_candidate(
                user_id=USER_ID,
                candidate_id=CANDIDATE_ID,
                selected_reminder_ids=[REMINDER_ID_1],
            )

        self.assertEqual(context.exception.code, "invalid_reminder_selection")

    def test_rejected_candidate_is_not_committable(self) -> None:
        service = TaskCommitService(
            task_candidate_repository=FakeTaskCandidateRepository(
                make_candidate(status=TaskCandidateStatus.REJECTED)
            ),
            task_repository=FakeTaskRepository(),
        )

        with self.assertRaises(TaskCommitError) as context:
            service.commit_candidate(user_id=USER_ID, candidate_id=CANDIDATE_ID)

        self.assertEqual(context.exception.code, "candidate_not_committable")

    def test_existing_candidate_task_returns_existing_task_without_duplicate_insert(self) -> None:
        existing_task = TaskResponse(
            id=TASK_ID,
            user_id=USER_ID,
            candidate_id=CANDIDATE_ID,
            raw_input_id=RAW_INPUT_ID,
            mediator_run_id=MEDIATOR_RUN_ID,
            title="이미 저장됨",
            source=TaskSource.AI,
            subtasks=[
                SubtaskResponse(
                    id="00000000-0000-4000-8000-000000000101",
                    task_id=TASK_ID,
                    user_id=USER_ID,
                    candidate_subtask_id=SUBTASK_ID_1,
                    title="과제 파일 열기",
                    order_index=0,
                    estimated_minutes=5,
                    status="todo",
                    is_next_action=True,
                    energy_required="low",
                )
            ],
            reminders=[
                ReminderResponse(
                    id="00000000-0000-4000-8000-000000000201",
                    user_id=USER_ID,
                    task_id=TASK_ID,
                    candidate_reminder_id=REMINDER_ID_1,
                    remind_at=datetime(2026, 5, 14, 12, 0, tzinfo=timezone.utc),
                    message="딱 5분만 과제 파일 열기",
                    type="start",
                    status="scheduled",
                    escalation_level=0,
                )
            ],
        )
        task_repo = FakeTaskRepository(existing_task=existing_task)
        service = TaskCommitService(
            task_candidate_repository=FakeTaskCandidateRepository(
                make_candidate(status=TaskCandidateStatus.COMMITTED)
            ),
            task_repository=task_repo,
        )

        result = service.commit_candidate(
            user_id=USER_ID,
            candidate_id=CANDIDATE_ID,
            selected_subtask_ids=[SUBTASK_ID_1],
            selected_reminder_ids=[REMINDER_ID_1],
        )

        self.assertEqual(str(result.task.id), TASK_ID)
        self.assertEqual(result.task.title, "이미 저장됨")
        self.assertEqual(task_repo.created_task_payloads, [])
        self.assertEqual(task_repo.created_subtask_payloads, [])
        self.assertEqual(task_repo.created_reminder_payloads, [])

    def test_existing_partial_candidate_task_repairs_missing_children(self) -> None:
        existing_task = TaskResponse(
            id=TASK_ID,
            user_id=USER_ID,
            candidate_id=CANDIDATE_ID,
            raw_input_id=RAW_INPUT_ID,
            mediator_run_id=MEDIATOR_RUN_ID,
            title="부분 저장됨",
            source=TaskSource.AI,
        )
        task_repo = FakeTaskRepository(existing_task=existing_task)
        service = TaskCommitService(
            task_candidate_repository=FakeTaskCandidateRepository(make_candidate()),
            task_repository=task_repo,
        )

        result = service.commit_candidate(
            user_id=USER_ID,
            candidate_id=CANDIDATE_ID,
            selected_subtask_ids=[SUBTASK_ID_2],
            selected_reminder_ids=[REMINDER_ID_1],
        )

        self.assertEqual(task_repo.created_task_payloads, [])
        self.assertEqual(
            task_repo.created_subtask_payloads[0]["candidate_subtask_id"],
            SUBTASK_ID_2,
        )
        self.assertEqual(
            task_repo.created_reminder_payloads[0]["candidate_reminder_id"],
            REMINDER_ID_1,
        )
        self.assertEqual(len(result.task.subtasks), 1)
        self.assertEqual(len(result.task.reminders), 1)

    def test_task_create_failure_does_not_mark_candidate_committed(self) -> None:
        candidate_repo = FakeTaskCandidateRepository(make_candidate())
        service = TaskCommitService(
            task_candidate_repository=candidate_repo,
            task_repository=FakeTaskRepository(fail_create_task=True),
        )

        with self.assertRaises(RuntimeError):
            service.commit_candidate(user_id=USER_ID, candidate_id=CANDIDATE_ID)

        self.assertEqual(candidate_repo.mark_committed_calls, [])

    def test_missing_final_task_schema_returns_actionable_error(self) -> None:
        candidate_repo = FakeTaskCandidateRepository(make_candidate())
        service = TaskCommitService(
            task_candidate_repository=candidate_repo,
            task_repository=FakeTaskRepository(
                fail_create_task_error=RuntimeError(
                    "PGRST205: Could not find the table 'public.tasks' in the schema cache"
                )
            ),
        )

        with self.assertRaises(TaskCommitError) as context:
            service.commit_candidate(user_id=USER_ID, candidate_id=CANDIDATE_ID)

        self.assertEqual(context.exception.code, "task_storage_unavailable")
        self.assertIn("0004_final_task_schema.sql", context.exception.message)
        self.assertEqual(candidate_repo.mark_committed_calls, [])


if __name__ == "__main__":
    unittest.main()
