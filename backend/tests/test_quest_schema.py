import unittest
from datetime import datetime, timezone

from app.schemas.quest import QuestCreateRequest, QuestItemResponse, QuestUpdateRequest


class QuestDueAtAliasTest(unittest.TestCase):
    def test_due_at_models_accept_internal_due_at_field_name(self) -> None:
        due_at = datetime(2026, 6, 12, tzinfo=timezone.utc)

        item = QuestItemResponse(
            id="quest-1",
            title="Submit report",
            exp=50,
            difficulty="normal",
            category="work",
            elapsedSeconds=0,
            defaultDurationSeconds=2700,
            dueAt=due_at,
        )
        create_request = QuestCreateRequest(
            title="Submit report",
            exp=50,
            difficulty="normal",
            category="work",
            defaultDurationSeconds=2700,
            dueAt=due_at,
        )
        update_request = QuestUpdateRequest(
            title="Submit report",
            exp=50,
            difficulty="normal",
            category="work",
            elapsedSeconds=0,
            defaultDurationSeconds=2700,
            dueAt=due_at,
        )

        self.assertEqual(item.dueAt, due_at)
        self.assertEqual(create_request.dueAt, due_at)
        self.assertEqual(update_request.dueAt, due_at)
        self.assertEqual(item.model_dump(by_alias=True)["due_at"], due_at)
        self.assertEqual(create_request.model_dump(by_alias=True)["due_at"], due_at)
        self.assertEqual(update_request.model_dump(by_alias=True)["due_at"], due_at)

    def test_due_at_models_still_accept_json_alias(self) -> None:
        due_at = datetime(2026, 6, 12, tzinfo=timezone.utc)

        item = QuestItemResponse(
            id="quest-1",
            title="Submit report",
            exp=50,
            difficulty="normal",
            category="work",
            elapsedSeconds=0,
            defaultDurationSeconds=2700,
            due_at=due_at,
        )

        self.assertEqual(item.dueAt, due_at)
        self.assertEqual(item.model_dump(by_alias=True)["due_at"], due_at)


if __name__ == "__main__":
    unittest.main()
