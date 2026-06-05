import unittest
from datetime import datetime, timedelta, timezone
from uuid import uuid4

from app.schemas.task import TaskResponse, TaskStatus
from app.services.user_task_pattern_service import (
    UserTaskPatternService,
    _build_analysis,
)


def make_task(
    *,
    title: str,
    status: TaskStatus | str = TaskStatus.TODO,
    created_at: datetime,
    completed_at: datetime | None = None,
    due_at: datetime | None = None,
    estimated_minutes: int | None = None,
    difficulty: str | None = None,
    subtask_count: int = 0,
) -> TaskResponse:
    subtasks = []
    for index in range(subtask_count):
        subtasks.append(
            {
                "id": uuid4(),
                "task_id": uuid4(),
                "user_id": uuid4(),
                "title": f"subtask-{index}",
                "order_index": index,
                "estimated_minutes": 5,
                "status": "todo",
                "is_next_action": index == 0,
                "energy_required": "low",
                "created_at": created_at,
                "updated_at": created_at,
                "completed_at": None,
            }
        )
    return TaskResponse.model_validate(
        {
            "id": uuid4(),
            "user_id": uuid4(),
            "candidate_id": None,
            "raw_input_id": None,
            "mediator_run_id": None,
            "title": title,
            "description": None,
            "status": getattr(status, "value", status),
            "priority": "medium",
            "due_at": due_at,
            "estimated_minutes": estimated_minutes,
            "energy_required": "medium",
            "difficulty": difficulty,
            "next_action": "start",
            "source": "ai",
            "metadata": {},
            "subtasks": subtasks,
            "reminders": [],
            "created_at": created_at,
            "updated_at": created_at,
            "completed_at": completed_at,
        }
    )


class FakeTaskRepository:
    def __init__(self, tasks: list[TaskResponse]) -> None:
        self.tasks = tasks
        self.calls: list[dict[str, object]] = []

    def list_for_pattern_analysis(self, *, user_id: str, limit: int = 50) -> list[TaskResponse]:
        self.calls.append({"user_id": user_id, "limit": limit})
        return self.tasks


class UserTaskPatternServiceTest(unittest.TestCase):
    def test_returns_empty_payload_when_history_is_insufficient(self) -> None:
        now = datetime.now(timezone.utc)
        tasks = [
            make_task(
                title="task-1",
                status=TaskStatus.DONE,
                created_at=now - timedelta(days=3),
                completed_at=now - timedelta(days=2),
                estimated_minutes=20,
                difficulty="low",
                subtask_count=2,
            ),
            make_task(
                title="task-2",
                status=TaskStatus.TODO,
                created_at=now - timedelta(days=1),
                estimated_minutes=30,
                difficulty="medium",
                subtask_count=2,
            ),
        ]

        analysis = _build_analysis(tasks)

        self.assertFalse(analysis.data_sufficient)
        self.assertEqual(analysis.existing_tasks, [])
        self.assertEqual(analysis.prompt_payload, {})

    def test_builds_prompt_payload_from_completion_patterns(self) -> None:
        now = datetime.now(timezone.utc)
        tasks = [
            make_task(
                title="short-done-1",
                status=TaskStatus.DONE,
                created_at=now - timedelta(days=12),
                completed_at=now - timedelta(days=11, hours=20),
                due_at=now - timedelta(days=11, hours=18),
                estimated_minutes=20,
                difficulty="low",
                subtask_count=2,
            ),
            make_task(
                title="short-done-2",
                status=TaskStatus.DONE,
                created_at=now - timedelta(days=10),
                completed_at=now - timedelta(days=9, hours=22),
                due_at=now - timedelta(days=9, hours=20),
                estimated_minutes=25,
                difficulty="low",
                subtask_count=2,
            ),
            make_task(
                title="short-done-3",
                status=TaskStatus.DONE,
                created_at=now - timedelta(days=8),
                completed_at=now - timedelta(days=7, hours=23),
                due_at=now - timedelta(days=7, hours=21),
                estimated_minutes=15,
                difficulty="medium",
                subtask_count=1,
            ),
            make_task(
                title="long-overdue-done",
                status=TaskStatus.DONE,
                created_at=now - timedelta(days=7),
                completed_at=now - timedelta(days=2),
                due_at=now - timedelta(days=4),
                estimated_minutes=120,
                difficulty="high",
                subtask_count=6,
            ),
            make_task(
                title="open-overdue",
                status=TaskStatus.TODO,
                created_at=now - timedelta(days=9),
                due_at=now - timedelta(days=1),
                estimated_minutes=90,
                difficulty="high",
                subtask_count=5,
            ),
            make_task(
                title="paused-open",
                status=TaskStatus.PAUSED,
                created_at=now - timedelta(days=15),
                due_at=now + timedelta(days=1),
                estimated_minutes=100,
                difficulty="high",
                subtask_count=5,
            ),
        ]

        analysis = _build_analysis(tasks)

        self.assertTrue(analysis.data_sufficient)
        self.assertEqual(analysis.prompt_payload["task_count_used_for_analysis"], 6)
        self.assertEqual(analysis.prompt_payload["completion_rate"], 0.667)
        self.assertEqual(analysis.prompt_payload["prefers_small_tasks"], True)
        self.assertEqual(analysis.prompt_payload["procrastination_level"], "high")
        self.assertEqual(analysis.prompt_payload["task_completion_style"], "incremental")
        self.assertEqual(analysis.existing_tasks, [])

    def test_service_reads_recent_tasks_from_repository(self) -> None:
        now = datetime.now(timezone.utc)
        repository = FakeTaskRepository(
            [
                make_task(
                    title="task-1",
                    status=TaskStatus.DONE,
                    created_at=now - timedelta(days=6),
                    completed_at=now - timedelta(days=5),
                    estimated_minutes=20,
                    difficulty="low",
                    subtask_count=2,
                ),
                make_task(
                    title="task-2",
                    status=TaskStatus.DONE,
                    created_at=now - timedelta(days=5),
                    completed_at=now - timedelta(days=4),
                    estimated_minutes=25,
                    difficulty="low",
                    subtask_count=2,
                ),
                make_task(
                    title="task-3",
                    status=TaskStatus.DONE,
                    created_at=now - timedelta(days=4),
                    completed_at=now - timedelta(days=3),
                    estimated_minutes=30,
                    difficulty="medium",
                    subtask_count=3,
                ),
                make_task(
                    title="task-4",
                    status=TaskStatus.DONE,
                    created_at=now - timedelta(days=3),
                    completed_at=now - timedelta(days=2),
                    estimated_minutes=35,
                    difficulty="medium",
                    subtask_count=3,
                ),
                make_task(
                    title="task-5",
                    status=TaskStatus.TODO,
                    created_at=now - timedelta(days=1),
                    estimated_minutes=40,
                    difficulty="medium",
                    subtask_count=3,
                ),
            ]
        )
        service = UserTaskPatternService(task_repository=repository)

        analysis = service.analyze(user_id="user-1")

        self.assertEqual(repository.calls[0]["user_id"], "user-1")
        self.assertTrue(analysis.data_sufficient)


if __name__ == "__main__":
    unittest.main()
