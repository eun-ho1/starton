import unittest
from datetime import datetime, timezone
from typing import Any

from app.repositories.base import QuestRecord
from app.repositories.completed_quest_repository import SupabaseCompletedQuestRepository


USER_ID = "00000000-0000-4000-8000-000000000001"
PROFILE_ID = "00000000-0000-4000-8000-000000000002"
QUEST_ID = "00000000-0000-4000-8000-000000000003"
TASK_ID = "00000000-0000-4000-8000-000000000004"
COMPLETED_ID = "00000000-0000-4000-8000-000000000005"


class FakeResponse:
    def __init__(self, data: list[dict[str, Any]]) -> None:
        self.data = data


class FakeTable:
    def __init__(self, client: "FakeClient", table_name: str) -> None:
        self.client = client
        self.table_name = table_name
        self.payload: dict[str, Any] | None = None

    def insert(self, payload: dict[str, Any]) -> "FakeTable":
        self.payload = payload
        self.client.insert_calls.append(
            {
                "table": self.table_name,
                "payload": payload,
            }
        )
        return self

    def execute(self) -> FakeResponse:
        assert self.payload is not None
        return FakeResponse([{"id": COMPLETED_ID, **self.payload}])


class FakeClient:
    def __init__(self) -> None:
        self.insert_calls: list[dict[str, Any]] = []

    def table(self, table_name: str) -> FakeTable:
        return FakeTable(self, table_name)


class CompletedQuestRepositoryTest(unittest.TestCase):
    def test_create_completed_task_stores_task_id_without_quest_fk(self) -> None:
        client = FakeClient()
        repository = SupabaseCompletedQuestRepository(client)

        _, completed = repository.create_completed_task(
            user_id=USER_ID,
            task=QuestRecord(
                id=TASK_ID,
                profile_id=PROFILE_ID,
                title="Submit report",
                exp=50,
                difficulty="normal",
                category="work",
                elapsed_seconds=1800,
                default_duration_seconds=1800,
            ),
            earned_exp=50,
            completed_at=datetime(2026, 5, 27, 12, 0, tzinfo=timezone.utc),
            elapsed_seconds=1800,
            proof_image_path="/proofs/task.png",
        )

        self.assertEqual(client.insert_calls[0]["table"], "completed_quests")
        payload = client.insert_calls[0]["payload"]
        self.assertIsNone(payload["quest_id"])
        self.assertEqual(payload["task_id"], TASK_ID)
        self.assertEqual(payload["client_quest_id"], TASK_ID)
        self.assertEqual(completed.questId, TASK_ID)

    def test_create_completed_quest_stores_quest_fk_without_task_id(self) -> None:
        client = FakeClient()
        repository = SupabaseCompletedQuestRepository(client)

        _, completed = repository.create_completed_quest(
            user_id=USER_ID,
            quest=QuestRecord(
                id=QUEST_ID,
                profile_id=PROFILE_ID,
                title="Manual quest",
                exp=30,
                difficulty="easy",
                category="life",
                elapsed_seconds=900,
                default_duration_seconds=1500,
            ),
            earned_exp=30,
            completed_at=datetime(2026, 5, 27, 12, 0, tzinfo=timezone.utc),
            elapsed_seconds=900,
            proof_image_path=None,
        )

        payload = client.insert_calls[0]["payload"]
        self.assertEqual(payload["quest_id"], QUEST_ID)
        self.assertNotIn("task_id", payload)
        self.assertEqual(payload["client_quest_id"], QUEST_ID)
        self.assertEqual(completed.questId, QUEST_ID)


if __name__ == "__main__":
    unittest.main()
