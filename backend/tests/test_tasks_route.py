import unittest

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api.routes import tasks as tasks_route
from app.schemas.task import TaskResponse, TaskStatus
from app.services.task_service import TaskServiceError


USER_ID = "00000000-0000-4000-8000-000000000001"
TASK_ID = "00000000-0000-4000-8000-000000000002"


def make_task_response() -> TaskResponse:
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
        difficulty=None,
        next_action="과제 파일 열기",
        metadata={"category": "study"},
        subtasks=[],
        reminders=[],
        completed_at=None,
    )


class FakeTaskService:
    def __init__(
        self,
        *,
        tasks: list[TaskResponse] | None = None,
        error: Exception | None = None,
    ) -> None:
        self.tasks = tasks or [make_task_response()]
        self.error = error
        self.list_calls: list[dict[str, str]] = []

    def list_active_tasks(self, *, user_id: str) -> list[TaskResponse]:
        self.list_calls.append({"user_id": user_id})
        if self.error is not None:
            raise self.error
        return self.tasks


class TasksRouteTest(unittest.TestCase):
    def make_client(
        self,
        service: FakeTaskService,
        *,
        override_user: bool = True,
    ) -> TestClient:
        app = FastAPI()
        app.include_router(tasks_route.router, prefix="/api/v1/tasks")
        if override_user:
            app.dependency_overrides[tasks_route.get_current_user_id] = lambda: USER_ID
        app.dependency_overrides[tasks_route.get_task_service] = lambda: service
        return TestClient(app)

    def test_list_tasks_returns_active_task_envelope(self) -> None:
        service = FakeTaskService()
        client = self.make_client(service)

        response = client.get("/api/v1/tasks")

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["success"], True)
        self.assertIsNone(payload["error"])
        self.assertEqual(len(payload["data"]), 1)
        self.assertEqual(payload["data"][0]["id"], TASK_ID)
        self.assertEqual(payload["data"][0]["status"], "todo")
        self.assertEqual(service.list_calls, [{"user_id": USER_ID}])

    def test_list_tasks_maps_service_error_to_500(self) -> None:
        service = FakeTaskService(
            error=TaskServiceError(
                "task_list_failed",
                "Failed to load tasks for the current user.",
            )
        )
        client = self.make_client(service)

        response = client.get("/api/v1/tasks")

        self.assertEqual(response.status_code, 500)
        detail = response.json()["detail"]
        self.assertEqual(detail["code"], "task_list_failed")
        self.assertEqual(
            detail["message"],
            "Failed to load tasks for the current user.",
        )

    def test_list_tasks_requires_authorization(self) -> None:
        service = FakeTaskService()
        client = self.make_client(service, override_user=False)

        response = client.get("/api/v1/tasks")

        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json()["detail"]["code"], "missing_authorization")
        self.assertEqual(service.list_calls, [])


if __name__ == "__main__":
    unittest.main()
