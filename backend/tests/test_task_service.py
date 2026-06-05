import unittest
from datetime import datetime, timezone
from typing import Any

from app.repositories.base import ProfileState, QuestRecord, StatsState
from app.schemas.quest import CompletedQuestRecordSchema
from app.schemas.task import TaskResponse, TaskStatus
from app.schemas.task_candidate import TaskDifficulty
from app.services.task_service import TaskService, TaskServiceError


USER_ID = "00000000-0000-4000-8000-000000000001"
PROFILE_ID = "00000000-0000-4000-8000-000000000002"
TASK_ID = "00000000-0000-4000-8000-000000000003"


def make_task() -> TaskResponse:
    return TaskResponse(
        id=TASK_ID,
        user_id=USER_ID,
        candidate_id=None,
        raw_input_id=None,
        mediator_run_id=None,
        title="컴퓨터비전 과제 제출",
        description=None,
        status=TaskStatus.TODO,
        priority=None,
        due_at=None,
        estimated_minutes=45,
        energy_required=None,
        difficulty=TaskDifficulty.MEDIUM,
        next_action=None,
        metadata={"category": "study", "exp": 80},
        subtasks=[],
        reminders=[],
        completed_at=None,
    )


class FakeTaskRepository:
    def __init__(
        self,
        task: TaskResponse,
        *,
        list_error: Exception | None = None,
    ) -> None:
        self.task = task
        self.list_error = list_error
        self.list_active_calls: list[dict[str, Any]] = []
        self.mark_completed_calls: list[dict[str, Any]] = []

    def list_active(self, *, user_id: str) -> list[TaskResponse]:
        self.list_active_calls.append({"user_id": user_id})
        if self.list_error is not None:
            raise self.list_error
        return [self.task]

    def get(self, *, user_id: str, task_id: str) -> TaskResponse:
        return self.task

    def mark_completed(
        self,
        *,
        user_id: str,
        task_id: str,
        completed_at: datetime,
    ) -> TaskResponse:
        self.mark_completed_calls.append(
            {
                "user_id": user_id,
                "task_id": task_id,
                "completed_at": completed_at,
            }
        )
        return self.task.model_copy(
            update={"status": TaskStatus.DONE, "completed_at": completed_at}
        )


class FakeRawInputRepository:
    pass


class FakeCompletedQuestRepository:
    def __init__(self) -> None:
        self.completed_task_calls: list[dict[str, Any]] = []
        self.completed_quest_calls: list[dict[str, Any]] = []
        self.recent_activity_calls: list[dict[str, Any]] = []

    def create_completed_quest(self, **kwargs: Any) -> tuple[str, CompletedQuestRecordSchema]:
        self.completed_quest_calls.append(kwargs)
        raise AssertionError("task completion must not use quest completion storage")

    def create_completed_task(self, **kwargs: Any) -> tuple[str, CompletedQuestRecordSchema]:
        self.completed_task_calls.append(kwargs)
        task = kwargs["task"]
        return (
            "completed-task-id",
            CompletedQuestRecordSchema(
                questId=task.id,
                title=task.title,
                difficulty=task.difficulty,
                category=task.category,
                earnedExp=kwargs["earned_exp"],
                completedAt=kwargs["completed_at"],
                elapsedSeconds=kwargs["elapsed_seconds"],
                proofImagePath=kwargs.get("proof_image_path"),
            ),
        )

    def create_recent_activity(self, **kwargs: Any) -> None:
        self.recent_activity_calls.append(kwargs)


class FakeProfileRepository:
    def __init__(self) -> None:
        self.update_calls: list[dict[str, Any]] = []

    def get_profile_state(self, user_id: str) -> ProfileState:
        return ProfileState(
            profile_id=PROFILE_ID,
            user_name="Tester",
            user_role="Beginner",
            level=0,
            current_exp=0,
            max_exp=500,
            credits=0,
            daily_reset_key="2026-05-27",
            weekly_reset_key="2026-W22",
            monthly_reset_key="2026-05",
        )

    def update_profile_progress(self, user_id: str, **kwargs: Any) -> None:
        self.update_calls.append({"user_id": user_id, **kwargs})


class FakeStatsRepository:
    def __init__(self) -> None:
        self.update_calls: list[dict[str, Any]] = []

    def get_stats_state(self, user_id: str) -> StatsState:
        return StatsState(
            stats_id="stats-id",
            completed_quest_count=0,
            earned_exp=0,
            daily_reward_count=0,
            daily_reward_target=3,
            weekly_reward_count=0,
            weekly_reward_target=7,
            monthly_reward_count=0,
            monthly_reward_target=30,
            weekly_completed_count=0,
            weekly_completion_rate=0,
            previous_weekly_completion_rate=0,
            weekly_rate_delta=0,
            diligence_stat=0,
            order_stat=0,
            intelligence_stat=0,
            health_stat=0,
            weekly_activity_counts=[0, 0, 0, 0, 0, 0, 0],
            weekly_activity_bars=[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        )

    def update_stats_after_completion(self, user_id: str, **kwargs: Any) -> None:
        self.update_calls.append({"user_id": user_id, **kwargs})


class TaskServiceTest(unittest.TestCase):
    def test_list_active_tasks_returns_repository_tasks(self) -> None:
        task_repository = FakeTaskRepository(make_task())
        service = TaskService(
            task_repository=task_repository,
            raw_input_repository=FakeRawInputRepository(),
            completed_quest_repository=FakeCompletedQuestRepository(),
            profile_repository=FakeProfileRepository(),
            stats_repository=FakeStatsRepository(),
        )

        result = service.list_active_tasks(user_id=USER_ID)

        self.assertEqual(result, [task_repository.task])
        self.assertEqual(task_repository.list_active_calls, [{"user_id": USER_ID}])

    def test_list_active_tasks_maps_repository_error(self) -> None:
        service = TaskService(
            task_repository=FakeTaskRepository(
                make_task(),
                list_error=RuntimeError("database unavailable"),
            ),
            raw_input_repository=FakeRawInputRepository(),
            completed_quest_repository=FakeCompletedQuestRepository(),
            profile_repository=FakeProfileRepository(),
            stats_repository=FakeStatsRepository(),
        )

        with self.assertRaises(TaskServiceError) as context:
            service.list_active_tasks(user_id=USER_ID)

        self.assertEqual(context.exception.code, "task_list_failed")
        self.assertEqual(
            context.exception.message,
            "Failed to load tasks for the current user.",
        )

    def test_complete_task_uses_task_completion_record_and_marks_task_done(self) -> None:
        task_repository = FakeTaskRepository(make_task())
        completed_repository = FakeCompletedQuestRepository()
        service = TaskService(
            task_repository=task_repository,
            raw_input_repository=FakeRawInputRepository(),
            completed_quest_repository=completed_repository,
            profile_repository=FakeProfileRepository(),
            stats_repository=FakeStatsRepository(),
        )

        result = service.complete_task(
            user_id=USER_ID,
            task_id=TASK_ID,
            elapsed_seconds=1200,
            proof_image_path="/proofs/task.png",
        )

        self.assertEqual(result.questId, TASK_ID)
        self.assertEqual(completed_repository.completed_quest_calls, [])
        self.assertEqual(len(completed_repository.completed_task_calls), 1)
        completed_task_call = completed_repository.completed_task_calls[0]
        self.assertIsInstance(completed_task_call["task"], QuestRecord)
        self.assertEqual(completed_task_call["task"].id, TASK_ID)
        self.assertEqual(completed_task_call["task"].category, "study")
        self.assertEqual(completed_task_call["earned_exp"], 80)
        self.assertEqual(task_repository.mark_completed_calls[0]["task_id"], TASK_ID)


if __name__ == "__main__":
    unittest.main()
