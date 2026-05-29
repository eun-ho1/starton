import unittest
from datetime import datetime, timezone
from typing import Any

from app.repositories.task_repository import SupabaseTaskRepository


USER_ID = "00000000-0000-4000-8000-000000000001"
TASK_ID = "00000000-0000-4000-8000-000000000002"


TASK_ROW = {
    "id": TASK_ID,
    "user_id": USER_ID,
    "profile_id": None,
    "candidate_id": None,
    "raw_input_id": None,
    "mediator_run_id": None,
    "title": "Submit report",
    "description": None,
    "status": "done",
    "priority": None,
    "due_at": None,
    "estimated_minutes": 30,
    "energy_required": None,
    "difficulty": "medium",
    "next_action": None,
    "source": "ai",
    "metadata": {},
    "created_at": None,
    "updated_at": None,
    "completed_at": "2026-05-27T12:00:00+00:00",
}


SUBTASK_ROW = {
    "id": "00000000-0000-4000-8000-000000000003",
    "task_id": TASK_ID,
    "user_id": USER_ID,
    "candidate_subtask_id": None,
    "title": "Open file",
    "order_index": 0,
    "estimated_minutes": 5,
    "status": "done",
    "is_next_action": True,
    "energy_required": None,
    "created_at": None,
    "updated_at": None,
    "completed_at": "2026-05-27T12:00:00+00:00",
}


class FakeResponse:
    def __init__(self, data: list[dict[str, Any]]) -> None:
        self.data = data


class FakeQuery:
    def __init__(self, client: "FakeClient", table_name: str) -> None:
        self.client = client
        self.table_name = table_name
        self.operation: str | None = None
        self.payload: dict[str, Any] | None = None
        self.filters: list[tuple[str, Any]] = []
        self.in_filters: list[tuple[str, list[Any]]] = []

    def select(self, columns: str) -> "FakeQuery":
        self.operation = "select"
        return self

    def update(self, payload: dict[str, Any]) -> "FakeQuery":
        self.operation = "update"
        self.payload = payload
        return self

    def eq(self, column: str, value: Any) -> "FakeQuery":
        self.filters.append((column, value))
        return self

    def in_(self, column: str, values: list[Any]) -> "FakeQuery":
        self.in_filters.append((column, values))
        return self

    def limit(self, count: int) -> "FakeQuery":
        return self

    def order(self, column: str) -> "FakeQuery":
        return self

    def execute(self) -> FakeResponse:
        self.client.calls.append(
            {
                "table": self.table_name,
                "operation": self.operation,
                "payload": self.payload,
                "filters": self.filters,
                "in_filters": self.in_filters,
            }
        )
        if self.table_name == "tasks" and self.operation == "update":
            return FakeResponse([{"id": TASK_ID}])
        if self.table_name == "subtasks" and self.operation == "update":
            return FakeResponse([])
        if self.table_name == "tasks" and self.operation == "select":
            return FakeResponse([TASK_ROW])
        if self.table_name == "subtasks" and self.operation == "select":
            return FakeResponse([SUBTASK_ROW])
        if self.table_name == "reminders" and self.operation == "select":
            return FakeResponse([])
        return FakeResponse([])


class FakeClient:
    def __init__(self) -> None:
        self.calls: list[dict[str, Any]] = []

    def table(self, table_name: str) -> FakeQuery:
        return FakeQuery(self, table_name)


class TaskRepositoryTest(unittest.TestCase):
    def test_mark_completed_updates_parent_task_and_open_subtasks(self) -> None:
        client = FakeClient()
        repository = SupabaseTaskRepository(client)
        completed_at = datetime(2026, 5, 27, 12, 0, tzinfo=timezone.utc)

        result = repository.mark_completed(
            user_id=USER_ID,
            task_id=TASK_ID,
            completed_at=completed_at,
        )

        task_update = next(
            call for call in client.calls
            if call["table"] == "tasks" and call["operation"] == "update"
        )
        subtask_update = next(
            call for call in client.calls
            if call["table"] == "subtasks" and call["operation"] == "update"
        )

        self.assertEqual(task_update["payload"]["status"], "done")
        self.assertEqual(task_update["payload"]["completed_at"], completed_at.isoformat())
        self.assertEqual(subtask_update["payload"]["status"], "done")
        self.assertEqual(
            subtask_update["in_filters"],
            [("status", ["todo", "doing", "skipped"])],
        )
        self.assertEqual(str(result.id), TASK_ID)
        self.assertEqual(result.subtasks[0].status, "done")


if __name__ == "__main__":
    unittest.main()
