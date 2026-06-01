import unittest
from datetime import datetime, timezone
from types import SimpleNamespace

from app.repositories.quest_repository import NotionQuestUpsertSummary, SupabaseQuestRepository
from app.providers.notion_client import NotionClientError
from app.schemas.notion import NotionSyncRequest
from app.services.notion_backend_service import NotionBackendService
from app.schemas.quest import QuestCategory, QuestDifficulty
from app.schemas.quest_generation import QuestCandidateResponse
from app.services.notion_parser import parse_notion_page_to_quest, parse_notion_pages_to_quests
from app.services.notion_sync_service import IntegrationException


class _FakeResponse:
    def __init__(self, data=None) -> None:
        self.data = data


class _FakeTable:
    def __init__(self, name: str) -> None:
        self.name = name
        self.rows: list[dict] = []
        self.upsert_calls: list[dict] = []
        self.update_calls: list[dict] = []
        self._pending_upsert_payload: dict | None = None
        self._pending_update_payload: dict | None = None
        self._pending_upsert_conflict: str | None = None
        self._selected_columns: str | None = None
        self._filters: dict[str, object] = {}
        self._limit: int | None = None
        self.fail_on_external_identity_queries = False
        self.fail_on_external_identity_upsert = False

    def select(self, columns: str):
        self._selected_columns = columns
        return self

    def eq(self, column: str, value: object):
        self._filters[column] = value
        return self

    def limit(self, value: int):
        self._limit = value
        return self

    def order(self, column: str, *, desc: bool = False):
        return self

    def update(self, payload):
        self.update_calls.append({"payload": payload})
        self._pending_update_payload = dict(payload)
        return self

    def upsert(self, payload, *, on_conflict: str):
        self.upsert_calls.append({"payload": payload, "on_conflict": on_conflict})
        self._pending_upsert_payload = dict(payload)
        self._pending_upsert_conflict = on_conflict
        return self

    def execute(self):
        if (
            self.fail_on_external_identity_queries
            and (
                "external_source" in self._filters
                or "external_id" in self._filters
            )
        ):
            self._selected_columns = None
            self._filters = {}
            self._limit = None
            raise RuntimeError("column quests.external_source does not exist")

        if self._pending_update_payload is not None:
            payload = self._pending_update_payload
            if (
                self.fail_on_external_identity_upsert
                and (
                    "external_source" in payload
                    or "external_id" in payload
                    or "external_updated_at" in payload
                )
            ):
                self._pending_update_payload = None
                self._selected_columns = None
                self._filters = {}
                self._limit = None
                raise RuntimeError(
                    "column quests.external_source does not exist",
                )
            matched_rows = [
                row
                for row in self.rows
                if all(row.get(column) == value for column, value in self._filters.items())
            ]
            for row in matched_rows:
                row.update(payload)
            self._pending_update_payload = None
            self._selected_columns = None
            self._filters = {}
            self._limit = None
            return _FakeResponse(data=matched_rows)

        if self._pending_upsert_payload is not None:
            payload = self._pending_upsert_payload
            if (
                self.fail_on_external_identity_upsert
                and (
                    self._pending_upsert_conflict == "user_id,external_source,external_id"
                    or "external_source" in payload
                    or "external_id" in payload
                    or "external_updated_at" in payload
                )
            ):
                self._pending_upsert_payload = None
                self._pending_upsert_conflict = None
                raise RuntimeError(
                    "column quests.external_source does not exist",
                )
            conflict_columns = [
                column.strip()
                for column in (self._pending_upsert_conflict or "").split(",")
                if column.strip()
            ]
            matched_row = None
            for row in self.rows:
                if all(row.get(column) == payload.get(column) for column in conflict_columns):
                    matched_row = row
                    break
            if matched_row is not None:
                matched_row.update(payload)
            else:
                self.rows.append(dict(payload))
            self._pending_upsert_payload = None
            self._pending_upsert_conflict = None
            return _FakeResponse(data=[])

        rows = [
            row for row in self.rows
            if all(row.get(column) == value for column, value in self._filters.items())
        ]
        if self._limit is not None:
            rows = rows[: self._limit]
        selected_rows = [_select_columns(row, self._selected_columns) for row in rows]
        self._selected_columns = None
        self._filters = {}
        self._limit = None
        return _FakeResponse(data=selected_rows)


class _FakeSupabaseClient:
    def __init__(self) -> None:
        self.tables: dict[str, _FakeTable] = {}

    def table(self, name: str) -> _FakeTable:
        if name not in self.tables:
            self.tables[name] = _FakeTable(name)
        return self.tables[name]


def _select_columns(row: dict, columns: str | None) -> dict:
    if not columns:
        return dict(row)
    selected = {}
    for column in columns.split(","):
        key = column.strip()
        if key:
            selected[key] = row.get(key)
    return selected


class _StatusOnlyConnectionRepository:
    def __init__(self, connection):
        self.connection = connection
        self.disconnect_calls: list[str] = []

    def find_connection_by_user_id(self, user_id: str):
        return self.connection

    def disconnect_by_user_id(self, user_id: str) -> None:
        self.disconnect_calls.append(user_id)


class _MutableStatusConnectionRepository(_StatusOnlyConnectionRepository):
    def disconnect_by_user_id(self, user_id: str) -> None:
        super().disconnect_by_user_id(user_id)
        if self.connection is None:
            return
        self.connection["access_token_encrypted"] = None
        self.connection["refresh_token_encrypted"] = None
        self.connection["disconnected_at"] = self.connection.get(
            "disconnected_at",
            "2026-05-18T01:02:03+00:00",
        )
        self.connection["sync_status"] = "disconnected"
        self.connection["last_error_message"] = None


class _UnusedProfileRepository:
    def get_profile_state(self, user_id: str):
        raise AssertionError("Profile lookup was not expected in this test.")


class _FallbackProfileRepository:
    def __init__(self, profile_id: str) -> None:
        self.profile_id = profile_id
        self.requests: list[str] = []

    def get_profile_state(self, user_id: str):
        self.requests.append(user_id)
        return SimpleNamespace(profile_id=self.profile_id)


class _UnusedQuestRepository:
    pass


class _UnusedCipher:
    pass


def _make_notion_candidate(*, external_id: str | None) -> QuestCandidateResponse:
    return QuestCandidateResponse(
        title="Notion quest",
        difficulty=QuestDifficulty.NORMAL,
        category=QuestCategory.WORK,
        exp=50,
        defaultDurationSeconds=2700,
        due_at=None,
        reason="Generated from Notion sync.",
        external_source="notion",
        external_id=external_id,
        external_url="https://www.notion.so/page-1",
        external_updated_at=datetime(
            2026,
            5,
            18,
            1,
            2,
            3,
            tzinfo=timezone.utc,
        ),
    )


class NotionParserTest(unittest.TestCase):
    def test_parse_notion_page_includes_external_metadata(self) -> None:
        quests = parse_notion_pages_to_quests(
            [
                {
                    "id": "page-123",
                    "url": "https://www.notion.so/page-123",
                    "last_edited_time": "2026-05-18T01:02:03.000Z",
                    "properties": {
                        "Name": {
                            "type": "title",
                            "title": [{"plain_text": "Prepare weekly report"}],
                        },
                    },
                },
            ]
        )

        self.assertEqual(len(quests), 1)
        self.assertEqual(quests[0].external_source, "notion")
        self.assertEqual(quests[0].external_id, "page-123")
        self.assertEqual(quests[0].external_url, "https://www.notion.so/page-123")
        self.assertEqual(
            quests[0].external_updated_at,
            datetime(2026, 5, 18, 1, 2, 3, tzinfo=timezone.utc),
        )

    def test_parse_notion_page_reads_due_date_property(self) -> None:
        quest = parse_notion_page_to_quest(
            {
                "id": "page-123",
                "properties": {
                    "Name": {
                        "type": "title",
                        "title": [{"plain_text": "Prepare weekly report"}],
                    },
                    "Date": {
                        "type": "date",
                        "date": {"start": "2026-06-02"},
                    },
                },
            }
        )

        self.assertEqual(
            quest.due_at,
            datetime(2026, 6, 2, 12, 0, tzinfo=timezone.utc),
        )

    def test_parse_notion_page_without_title_uses_safe_fallback(self) -> None:
        quest = parse_notion_page_to_quest(
            {
                "id": "page-untitled-1",
                "url": "https://www.notion.so/page-untitled-1",
                "last_edited_time": "2026-05-18T01:02:03.000Z",
                "properties": {
                    "Notes": {
                        "type": "rich_text",
                        "rich_text": [{"plain_text": "No title here"}],
                    },
                },
            }
        )

        self.assertEqual(quest.external_id, "page-untitled-1")
        self.assertEqual(quest.title, "Untitled Notion page (page-unt)")
        self.assertIn("Title property was missing or empty.", quest.reason or "")

    def test_parse_notion_page_with_missing_properties_uses_defaults(self) -> None:
        quest = parse_notion_page_to_quest(
            {
                "id": "page-defaults-1",
                "url": "https://www.notion.so/page-defaults-1",
                "properties": {
                    "Name": {
                        "type": "title",
                        "title": [{"plain_text": "Prepare weekly report"}],
                    },
                },
            }
        )

        self.assertEqual(quest.difficulty, QuestDifficulty.NORMAL)
        self.assertEqual(quest.category, QuestCategory.WORK)
        self.assertEqual(quest.exp, 50)
        self.assertEqual(quest.defaultDurationSeconds, 45 * 60)
        self.assertIn("Defaulted missing or unknown difficulty to normal.", quest.reason or "")
        self.assertIn(
            "Defaulted missing or unknown category from the title.",
            quest.reason or "",
        )
        self.assertIn("Defaulted missing or invalid EXP from difficulty.", quest.reason or "")
        self.assertIn(
            "Defaulted missing or invalid duration from difficulty.",
            quest.reason or "",
        )

    def test_parse_notion_page_parses_last_edited_time_as_utc_datetime(self) -> None:
        quest = parse_notion_page_to_quest(
            {
                "id": "page-time-1",
                "url": "https://www.notion.so/page-time-1",
                "last_edited_time": "2026-05-18T10:02:03+09:00",
                "properties": {
                    "Name": {
                        "type": "title",
                        "title": [{"plain_text": "Review parser output"}],
                    },
                },
            }
        )

        self.assertEqual(
            quest.external_updated_at,
            datetime(2026, 5, 18, 1, 2, 3, tzinfo=timezone.utc),
        )

    def test_parse_notion_page_marks_malformed_item_reason_without_crashing(self) -> None:
        quest = parse_notion_page_to_quest(
            {
                "id": "   ",
                "properties": {
                    "Title": {
                        "type": "title",
                        "title": [],
                    },
                    "Weird Difficulty": {
                        "type": "status",
                        "status": {"name": "unexpected"},
                    },
                },
                "last_edited_time": "not-a-timestamp",
            }
        )

        self.assertIsNone(quest.external_id)
        self.assertEqual(quest.title, "Untitled Notion page")
        self.assertIn("Notion page is missing a stable page ID.", quest.reason or "")
        self.assertIn("last_edited_time could not be parsed.", quest.reason or "")
        self.assertIn("Notion page URL was missing.", quest.reason or "")


class NotionQuestRepositoryTest(unittest.TestCase):
    def test_upsert_notion_quests_same_external_id_twice_keeps_single_row(self) -> None:
        client = _FakeSupabaseClient()
        repository = SupabaseQuestRepository(client)

        summary_first = repository.upsert_notion_quests(
            user_id="user-1",
            profile_id="profile-1",
            source_reference="data-source-1",
            pages=[],
            quests=[_make_notion_candidate(external_id="page-1")],
        )
        summary_second = repository.upsert_notion_quests(
            user_id="user-1",
            profile_id="profile-1",
            source_reference="data-source-1",
            pages=[],
            quests=[_make_notion_candidate(external_id="page-1")],
        )

        notion_rows = [
            row
            for row in client.table("quests").rows
            if row.get("user_id") == "user-1"
            and row.get("external_source") == "notion"
            and row.get("external_id") == "page-1"
        ]
        self.assertEqual(len(notion_rows), 1)
        self.assertEqual(summary_first.imported_count, 1)
        self.assertEqual(summary_second.updated_count, 1)
        self.assertEqual(summary_second.stale_count, 0)

    def test_upsert_notion_quests_persists_due_at(self) -> None:
        client = _FakeSupabaseClient()
        repository = SupabaseQuestRepository(client)
        due_at = datetime(2026, 6, 2, 12, 0, tzinfo=timezone.utc)

        repository.upsert_notion_quests(
            user_id="user-1",
            profile_id="profile-1",
            source_reference="data-source-1",
            pages=[],
            quests=[
                _make_notion_candidate(external_id="page-1").model_copy(
                    update={"due_at": due_at},
                ),
            ],
        )

        notion_row = client.table("quests").rows[0]
        self.assertEqual(notion_row["due_at"], due_at.isoformat())

    def test_upsert_notion_quests_updates_legacy_client_quest_id_row(self) -> None:
        client = _FakeSupabaseClient()
        client.table("quests").rows.append(
            {
                "id": "legacy-row-1",
                "user_id": "user-1",
                "profile_id": "profile-1",
                "client_quest_id": "notion:page-1",
                "title": "Old title",
                "exp": 30,
                "difficulty": "easy",
                "category": "work",
                "elapsed_seconds": 0,
                "default_duration_seconds": 1500,
                "status": "active",
                "source": "notion",
                "source_reference": "data-source-1",
            },
        )
        repository = SupabaseQuestRepository(client)

        summary = repository.upsert_notion_quests(
            user_id="user-1",
            profile_id="profile-1",
            source_reference="data-source-1",
            pages=[],
            quests=[_make_notion_candidate(external_id="page-1")],
        )

        rows = [
            row
            for row in client.table("quests").rows
            if row.get("user_id") == "user-1"
            and row.get("client_quest_id") == "notion:page-1"
        ]
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["id"], "legacy-row-1")
        self.assertEqual(rows[0]["title"], "Notion quest")
        self.assertEqual(rows[0]["external_source"], "notion")
        self.assertEqual(rows[0]["external_id"], "page-1")
        self.assertEqual(summary.imported_count, 0)
        self.assertEqual(summary.updated_count, 1)
        self.assertEqual(len(client.table("quests").upsert_calls), 0)
        self.assertEqual(len(client.table("quests").update_calls), 1)

    def test_list_quests_deduplicates_notion_client_quest_id_rows(self) -> None:
        client = _FakeSupabaseClient()
        client.table("quests").rows.extend(
            [
                {
                    "id": "new-row",
                    "user_id": "user-1",
                    "client_quest_id": "notion:page-1",
                    "source": "notion",
                    "title": "New Notion title",
                    "exp": 50,
                    "difficulty": "normal",
                    "category": "work",
                    "elapsed_seconds": 0,
                    "default_duration_seconds": 2700,
                    "status": "active",
                },
                {
                    "id": "old-row",
                    "user_id": "user-1",
                    "client_quest_id": "notion:page-1",
                    "source": "notion",
                    "title": "Old Notion title",
                    "exp": 50,
                    "difficulty": "normal",
                    "category": "work",
                    "elapsed_seconds": 0,
                    "default_duration_seconds": 2700,
                    "status": "active",
                },
                {
                    "id": "manual-row",
                    "user_id": "user-1",
                    "client_quest_id": "manual-row",
                    "source": "manual",
                    "title": "Manual title",
                    "exp": 30,
                    "difficulty": "easy",
                    "category": "study",
                    "elapsed_seconds": 0,
                    "default_duration_seconds": 1500,
                    "status": "active",
                },
            ],
        )
        repository = SupabaseQuestRepository(client)

        quests = repository.list_quests("user-1")

        self.assertEqual([quest.id for quest in quests], ["new-row", "manual-row"])
        self.assertEqual([quest.title for quest in quests], ["New Notion title", "Manual title"])

    def test_upsert_notion_quests_uses_client_quest_id_conflict_key(self) -> None:
        client = _FakeSupabaseClient()
        repository = SupabaseQuestRepository(client)

        # Same-title rows are intentionally treated as different records unless
        # they share the same external identity. This avoids risky automatic
        # reconciliation with legacy title-based Notion imports.
        summary = repository.upsert_notion_quests(
            user_id="user-1",
            profile_id="profile-1",
            source_reference="data-source-1",
            pages=[],
            quests=[
                QuestCandidateResponse(
                    title="Same title",
                    difficulty=QuestDifficulty.NORMAL,
                    category=QuestCategory.WORK,
                    exp=50,
                    defaultDurationSeconds=2700,
                    reason="Generated from Notion sync.",
                    external_source="notion",
                    external_id="page-1",
                    external_url="https://www.notion.so/page-1",
                    external_updated_at=datetime(
                        2026,
                        5,
                        18,
                        1,
                        2,
                        3,
                        tzinfo=timezone.utc,
                    ),
                ),
                QuestCandidateResponse(
                    title="Same title",
                    difficulty=QuestDifficulty.NORMAL,
                    category=QuestCategory.WORK,
                    exp=50,
                    defaultDurationSeconds=2700,
                    reason="Generated from Notion sync.",
                    external_source="notion",
                    external_id="page-2",
                    external_url="https://www.notion.so/page-2",
                    external_updated_at=datetime(
                        2026,
                        5,
                        18,
                        1,
                        2,
                        4,
                        tzinfo=timezone.utc,
                    ),
                ),
            ],
        )

        calls = client.tables["quests"].upsert_calls
        self.assertEqual(len(calls), 2)
        self.assertEqual(summary.imported_count, 2)
        self.assertEqual(summary.updated_count, 0)
        self.assertEqual(summary.skipped_count, 0)
        self.assertEqual(summary.stale_count, 0)
        self.assertEqual(
            calls[0]["on_conflict"],
            "user_id,client_quest_id",
        )
        self.assertEqual(calls[0]["payload"]["source"], "notion")
        self.assertEqual(calls[0]["payload"]["external_source"], "notion")
        self.assertEqual(calls[0]["payload"]["external_id"], "page-1")
        self.assertEqual(calls[1]["payload"]["external_id"], "page-2")
        self.assertEqual(calls[0]["payload"]["title"], "Same title")
        self.assertEqual(calls[1]["payload"]["title"], "Same title")
        notion_rows = [
            row
            for row in client.table("quests").rows
            if row.get("user_id") == "user-1" and row.get("external_source") == "notion"
        ]
        self.assertEqual(len(notion_rows), 2)

    def test_upsert_notion_quests_rejects_none_external_id(self) -> None:
        client = _FakeSupabaseClient()
        repository = SupabaseQuestRepository(client)

        with self.assertRaisesRegex(ValueError, "non-empty external_id"):
            repository.upsert_notion_quests(
                user_id="user-1",
                profile_id="profile-1",
                source_reference="data-source-1",
                pages=[],
                quests=[_make_notion_candidate(external_id=None)],
            )

    def test_upsert_notion_quests_rejects_empty_external_id(self) -> None:
        client = _FakeSupabaseClient()
        repository = SupabaseQuestRepository(client)

        with self.assertRaisesRegex(ValueError, "non-empty external_id"):
            repository.upsert_notion_quests(
                user_id="user-1",
                profile_id="profile-1",
                source_reference="data-source-1",
                pages=[],
                quests=[_make_notion_candidate(external_id="")],
            )

    def test_upsert_notion_quests_rejects_whitespace_external_id(self) -> None:
        client = _FakeSupabaseClient()
        repository = SupabaseQuestRepository(client)

        with self.assertRaisesRegex(ValueError, "non-empty external_id"):
            repository.upsert_notion_quests(
                user_id="user-1",
                profile_id="profile-1",
                source_reference="data-source-1",
                pages=[],
                quests=[_make_notion_candidate(external_id="   ")],
            )

    def test_upsert_notion_quests_accepts_valid_external_id(self) -> None:
        client = _FakeSupabaseClient()
        repository = SupabaseQuestRepository(client)

        summary = repository.upsert_notion_quests(
            user_id="user-1",
            profile_id="profile-1",
            source_reference="data-source-1",
            pages=[],
            quests=[_make_notion_candidate(external_id="page-1")],
        )

        calls = client.tables["quests"].upsert_calls
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]["payload"]["external_id"], "page-1")
        self.assertEqual(summary.imported_count, 1)
        self.assertEqual(summary.updated_count, 0)
        self.assertEqual(summary.skipped_count, 0)
        self.assertEqual(summary.stale_count, 0)

    def test_upsert_notion_quests_updates_existing_row_when_incoming_is_newer(self) -> None:
        client = _FakeSupabaseClient()
        client.table("quests").rows = [
            {
                "id": "quest-1",
                "user_id": "user-1",
                "external_source": "notion",
                "external_id": "page-1",
                "external_updated_at": "2026-05-18T01:02:03+00:00",
            }
        ]
        repository = SupabaseQuestRepository(client)

        summary = repository.upsert_notion_quests(
            user_id="user-1",
            profile_id="profile-1",
            source_reference="data-source-1",
            pages=[],
            quests=[
                QuestCandidateResponse(
                    title="Updated title",
                    difficulty=QuestDifficulty.NORMAL,
                    category=QuestCategory.WORK,
                    exp=50,
                    defaultDurationSeconds=2700,
                    reason="Generated from Notion sync.",
                    external_source="notion",
                    external_id="page-1",
                    external_updated_at=datetime(
                        2026,
                        5,
                        18,
                        1,
                        2,
                        4,
                        tzinfo=timezone.utc,
                    ),
                ),
            ],
        )

        calls = client.table("quests").update_calls
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]["payload"]["title"], "Updated title")
        self.assertEqual(summary.imported_count, 0)
        self.assertEqual(summary.updated_count, 1)
        self.assertEqual(summary.skipped_count, 0)
        self.assertEqual(summary.stale_count, 0)
        self.assertEqual(
            calls[0]["payload"]["external_updated_at"],
            "2026-05-18T01:02:04+00:00",
        )

    def test_upsert_notion_quests_does_not_overwrite_with_older_timestamp(self) -> None:
        client = _FakeSupabaseClient()
        client.table("quests").rows = [
            {
                "id": "quest-1",
                "user_id": "user-1",
                "external_source": "notion",
                "external_id": "page-1",
                "title": "Existing title",
                "external_url": "https://www.notion.so/existing-page-1",
                "external_updated_at": "2026-05-18T01:02:05+00:00",
            }
        ]
        repository = SupabaseQuestRepository(client)

        summary = repository.upsert_notion_quests(
            user_id="user-1",
            profile_id="profile-1",
            source_reference="data-source-1",
            pages=[],
            quests=[
                QuestCandidateResponse(
                    title="Stale title",
                    difficulty=QuestDifficulty.NORMAL,
                    category=QuestCategory.WORK,
                    exp=50,
                    defaultDurationSeconds=2700,
                    reason="Generated from Notion sync.",
                    external_source="notion",
                    external_id="page-1",
                    external_updated_at=datetime(
                        2026,
                        5,
                        18,
                        1,
                        2,
                        4,
                        tzinfo=timezone.utc,
                    ),
                ),
            ],
        )

        self.assertEqual(client.table("quests").upsert_calls, [])
        self.assertEqual(client.table("quests").rows[0]["title"], "Existing title")
        self.assertEqual(
            client.table("quests").rows[0]["external_url"],
            "https://www.notion.so/existing-page-1",
        )
        self.assertEqual(summary.imported_count, 0)
        self.assertEqual(summary.updated_count, 0)
        self.assertEqual(summary.skipped_count, 1)
        self.assertEqual(summary.stale_count, 1)

    def test_upsert_notion_quests_allows_same_timestamp_for_idempotent_update(self) -> None:
        client = _FakeSupabaseClient()
        client.table("quests").rows = [
            {
                "id": "quest-1",
                "user_id": "user-1",
                "external_source": "notion",
                "external_id": "page-1",
                "external_updated_at": "2026-05-18T01:02:03+00:00",
            }
        ]
        repository = SupabaseQuestRepository(client)

        summary = repository.upsert_notion_quests(
            user_id="user-1",
            profile_id="profile-1",
            source_reference="data-source-1",
            pages=[],
            quests=[_make_notion_candidate(external_id="page-1")],
        )

        self.assertEqual(len(client.table("quests").update_calls), 1)
        self.assertEqual(summary.updated_count, 1)
        self.assertEqual(summary.stale_count, 0)

    def test_upsert_notion_quests_does_not_overwrite_when_incoming_timestamp_is_null(self) -> None:
        client = _FakeSupabaseClient()
        client.table("quests").rows = [
            {
                "id": "quest-1",
                "user_id": "user-1",
                "external_source": "notion",
                "external_id": "page-1",
                "title": "Existing title",
                "external_url": "https://www.notion.so/existing-page-1",
                "external_updated_at": "2026-05-18T01:02:03+00:00",
            }
        ]
        repository = SupabaseQuestRepository(client)

        summary = repository.upsert_notion_quests(
            user_id="user-1",
            profile_id="profile-1",
            source_reference="data-source-1",
            pages=[],
            quests=[
                QuestCandidateResponse(
                    title="Missing timestamp",
                    difficulty=QuestDifficulty.NORMAL,
                    category=QuestCategory.WORK,
                    exp=50,
                    defaultDurationSeconds=2700,
                    reason="Generated from Notion sync.",
                    external_source="notion",
                    external_id="page-1",
                    external_updated_at=None,
                ),
            ],
        )

        self.assertEqual(client.table("quests").upsert_calls, [])
        self.assertEqual(client.table("quests").rows[0]["title"], "Existing title")
        self.assertEqual(
            client.table("quests").rows[0]["external_url"],
            "https://www.notion.so/existing-page-1",
        )
        self.assertEqual(summary.skipped_count, 1)
        self.assertEqual(summary.stale_count, 1)

    def test_upsert_notion_quests_overwrites_when_existing_timestamp_is_null(self) -> None:
        client = _FakeSupabaseClient()
        client.table("quests").rows = [
            {
                "id": "quest-1",
                "user_id": "user-1",
                "external_source": "notion",
                "external_id": "page-1",
                "external_updated_at": None,
            }
        ]
        repository = SupabaseQuestRepository(client)

        summary = repository.upsert_notion_quests(
            user_id="user-1",
            profile_id="profile-1",
            source_reference="data-source-1",
            pages=[],
            quests=[_make_notion_candidate(external_id="page-1")],
        )

        self.assertEqual(len(client.table("quests").update_calls), 1)
        self.assertEqual(summary.updated_count, 1)
        self.assertEqual(summary.stale_count, 0)

    def test_upsert_notion_quests_falls_back_to_legacy_client_quest_id_when_external_schema_is_missing(
        self,
    ) -> None:
        client = _FakeSupabaseClient()
        client.table("quests").fail_on_external_identity_queries = True
        client.table("quests").fail_on_external_identity_upsert = True
        repository = SupabaseQuestRepository(client)

        summary = repository.upsert_notion_quests(
            user_id="user-1",
            profile_id="profile-1",
            source_reference="data-source-1",
            pages=[],
            quests=[_make_notion_candidate(external_id="page-1")],
        )

        calls = client.table("quests").upsert_calls
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[0]["on_conflict"], "user_id,client_quest_id")
        self.assertEqual(calls[1]["on_conflict"], "user_id,client_quest_id")
        self.assertIn("external_source", calls[0]["payload"])
        self.assertIn("external_id", calls[0]["payload"])
        self.assertIn("external_updated_at", calls[0]["payload"])
        self.assertEqual(calls[1]["payload"]["client_quest_id"], "notion:page-1")
        self.assertNotIn("external_source", calls[1]["payload"])
        self.assertNotIn("external_id", calls[1]["payload"])
        self.assertNotIn("external_updated_at", calls[1]["payload"])
        self.assertEqual(summary.imported_count, 1)


class _SyncConnectionRepository:
    def __init__(self, connection):
        self.connection = connection
        self.mark_synced_calls: list[str] = []
        self.mark_failed_calls: list[tuple[str, str]] = []
        self.ensure_still_connected_calls: list[str] = []
        self.mark_synced_result = True
        self.mark_synced_success_updates = 0

    def get_connected_connection_by_user_id(self, user_id: str):
        if (
            self.connection.get("disconnected_at") is not None
            or not self.connection.get("access_token_encrypted")
        ):
            raise ValueError(
                "The saved Notion connection is disconnected. Reconnect before syncing.",
            )
        return self.connection

    def ensure_connection_still_connected(self, connection_id: str):
        self.ensure_still_connected_calls.append(connection_id)
        if (
            self.connection.get("disconnected_at") is not None
            or not self.connection.get("access_token_encrypted")
        ):
            raise ValueError(
                "The saved Notion connection was disconnected before sync completed.",
            )
        return self.connection

    def mark_synced(self, connection_id: str) -> None:
        self.mark_synced_calls.append(connection_id)

    def mark_synced_if_connected(self, connection_id: str) -> bool:
        self.mark_synced_calls.append(connection_id)
        if self.mark_synced_result:
            self.mark_synced_success_updates += 1
            self.connection["last_successful_synced_at"] = "2026-05-18T01:02:04+00:00"
        return self.mark_synced_result

    def mark_failed_if_connected(self, connection_id: str, *, public_error_message: str) -> bool:
        self.mark_failed_calls.append((connection_id, public_error_message))
        return True


class _FakeNotionClient:
    def __init__(
        self,
        resolved=None,
        *,
        resolve_error: Exception | None = None,
        on_resolve=None,
    ):
        self.resolved = resolved
        self.resolve_error = resolve_error
        self.on_resolve = on_resolve

    def resolve_source(self, **kwargs):
        if self.resolve_error is not None:
            raise self.resolve_error
        if self.on_resolve is not None:
            self.on_resolve()
        return self.resolved


class _FakeResolvedSource:
    def __init__(
        self,
        *,
        database_id: str,
        data_source_id: str | None = None,
        database_title: str,
        database_url: str | None = None,
        pages: list[dict],
    ):
        self.database_id = database_id
        self.data_source_id = data_source_id or database_id
        self.database_title = database_title
        self.database_url = database_url
        self.pages = pages


class _TrackingQuestRepository:
    def __init__(self) -> None:
        self.upsert_calls = 0
        self.summary = NotionQuestUpsertSummary(imported_count=1, updated_count=0, skipped_count=0)

    def upsert_notion_quests(self, **kwargs) -> NotionQuestUpsertSummary:
        self.upsert_calls += 1
        return self.summary


class _ExplodingQuestRepository(_TrackingQuestRepository):
    def upsert_notion_quests(self, **kwargs) -> NotionQuestUpsertSummary:
        raise RuntimeError("Unexpected repository crash during Notion quest upsert")


class _PassThroughCipher:
    def decrypt(self, value: str) -> str:
        return value


class NotionSyncServiceValidationTest(unittest.TestCase):
    def test_sync_creates_one_quest_from_single_page(self) -> None:
        connection_repository = _SyncConnectionRepository(
            {
                "id": "connection-1",
                "profile_id": "profile-1",
                "access_token_encrypted": "encrypted-token",
                "database_id": "database-1",
                "data_source_id": "data-source-1",
                "database_url": "https://www.notion.so/database-1",
                "disconnected_at": None,
            }
        )
        quest_repository = _TrackingQuestRepository()
        quest_repository.summary = NotionQuestUpsertSummary(
            imported_count=1,
            updated_count=0,
            skipped_count=0,
        )
        service = NotionBackendService(
            notion_client=_FakeNotionClient(
                _FakeResolvedSource(
                    database_id="database-1",
                    data_source_id="data-source-1",
                    database_title="Tasks",
                    pages=[
                        {
                            "id": "page-1",
                            "url": "https://www.notion.so/page-1",
                            "last_edited_time": "2026-05-18T01:02:03.000Z",
                            "properties": {
                                "Name": {
                                    "type": "title",
                                    "title": [{"plain_text": "One quest"}],
                                },
                            },
                        },
                    ],
                )
            ),
            notion_connection_repository=connection_repository,
            profile_repository=_UnusedProfileRepository(),  # type: ignore[arg-type]
            quest_repository=quest_repository,  # type: ignore[arg-type]
            secret_cipher=_PassThroughCipher(),  # type: ignore[arg-type]
        )

        result = service.sync("user-1", NotionSyncRequest())

        self.assertEqual(len(result.quests), 1)
        self.assertEqual(result.imported_count, 1)
        self.assertEqual(result.updated_count, 0)
        self.assertEqual(result.skipped_count, 0)
        self.assertEqual(result.quests[0].external_source, "notion")
        self.assertEqual(result.quests[0].external_id, "page-1")

    def test_sync_fails_when_connection_is_already_disconnected(self) -> None:
        connection_repository = _SyncConnectionRepository(
            {
                "id": "connection-1",
                "profile_id": "profile-1",
                "access_token_encrypted": None,
                "database_id": "database-1",
                "database_url": "https://www.notion.so/database-1",
                "disconnected_at": "2026-05-18T01:02:03+00:00",
            }
        )
        quest_repository = _TrackingQuestRepository()
        service = NotionBackendService(
            notion_client=_FakeNotionClient(
                _FakeResolvedSource(
                    database_id="database-1",
                    database_title="Tasks",
                    pages=[],
                )
            ),
            notion_connection_repository=connection_repository,
            profile_repository=_UnusedProfileRepository(),  # type: ignore[arg-type]
            quest_repository=quest_repository,  # type: ignore[arg-type]
            secret_cipher=_PassThroughCipher(),  # type: ignore[arg-type]
        )

        with self.assertRaisesRegex(IntegrationException, "disconnected"):
            service.sync("user-1", NotionSyncRequest())

        self.assertEqual(quest_repository.upsert_calls, 0)
        self.assertEqual(connection_repository.mark_synced_calls, [])
        self.assertEqual(connection_repository.mark_failed_calls, [])

    def test_sync_rejects_whitespace_external_id_before_repository_upsert(self) -> None:
        connection_repository = _SyncConnectionRepository(
            {
                "id": "connection-1",
                "profile_id": "profile-1",
                "access_token_encrypted": "encrypted-token",
                "database_id": "database-1",
                "database_url": "https://www.notion.so/database-1",
                "disconnected_at": None,
            }
        )
        quest_repository = _TrackingQuestRepository()
        service = NotionBackendService(
            notion_client=_FakeNotionClient(
                _FakeResolvedSource(
                    database_id="database-1",
                    database_title="Tasks",
                    pages=[
                        {
                            "id": "   ",
                            "url": "https://www.notion.so/page-1",
                            "properties": {
                                "Name": {
                                    "type": "title",
                                    "title": [{"plain_text": "Broken quest"}],
                                },
                            },
                        },
                    ],
                )
            ),
            notion_connection_repository=connection_repository,
            profile_repository=_UnusedProfileRepository(),  # type: ignore[arg-type]
            quest_repository=quest_repository,  # type: ignore[arg-type]
            secret_cipher=_PassThroughCipher(),  # type: ignore[arg-type]
        )

        with self.assertRaisesRegex(IntegrationException, "missing a stable page ID"):
            service.sync("user-1", NotionSyncRequest())

        self.assertEqual(quest_repository.upsert_calls, 0)
        self.assertEqual(connection_repository.mark_synced_calls, [])
        self.assertEqual(
            connection_repository.mark_failed_calls,
            [
                (
                    "connection-1",
                    "Notion sync failed because at least one page is missing a stable page ID. "
                    "Check the selected database and try again.",
                )
            ],
        )

    def test_sync_recovers_missing_profile_id_from_profile_repository(self) -> None:
        connection_repository = _SyncConnectionRepository(
            {
                "id": "connection-1",
                "profile_id": "   ",
                "access_token_encrypted": "encrypted-token",
                "database_id": "database-1",
                "data_source_id": "data-source-1",
                "database_url": "https://www.notion.so/database-1",
                "disconnected_at": None,
            }
        )
        profile_repository = _FallbackProfileRepository("profile-recovered")

        class _CapturingQuestRepository(_TrackingQuestRepository):
            def __init__(self) -> None:
                super().__init__()
                self.last_kwargs: dict | None = None

            def upsert_notion_quests(self, **kwargs) -> NotionQuestUpsertSummary:
                self.last_kwargs = kwargs
                return super().upsert_notion_quests(**kwargs)

        quest_repository = _CapturingQuestRepository()
        service = NotionBackendService(
            notion_client=_FakeNotionClient(
                _FakeResolvedSource(
                    database_id="database-1",
                    database_title="Tasks",
                    pages=[
                        {
                            "id": "page-1",
                            "url": "https://www.notion.so/page-1",
                            "properties": {
                                "Name": {
                                    "type": "title",
                                    "title": [{"plain_text": "Recovered quest"}],
                                },
                            },
                        },
                    ],
                )
            ),
            notion_connection_repository=connection_repository,
            profile_repository=profile_repository,  # type: ignore[arg-type]
            quest_repository=quest_repository,  # type: ignore[arg-type]
            secret_cipher=_PassThroughCipher(),  # type: ignore[arg-type]
        )

        result = service.sync("user-1", NotionSyncRequest())

        self.assertEqual(result.imported_count, 1)
        self.assertEqual(profile_repository.requests, ["user-1"])
        self.assertIsNotNone(quest_repository.last_kwargs)
        self.assertEqual(quest_repository.last_kwargs["profile_id"], "profile-recovered")

    def test_sync_does_not_store_success_metadata_after_disconnect_race(self) -> None:
        connection_repository = _SyncConnectionRepository(
            {
                "id": "connection-1",
                "profile_id": "profile-1",
                "access_token_encrypted": "encrypted-token",
                "database_id": "database-1",
                "database_url": "https://www.notion.so/database-1",
                "disconnected_at": None,
            }
        )
        connection_repository.mark_synced_result = False
        quest_repository = _TrackingQuestRepository()
        service = NotionBackendService(
            notion_client=_FakeNotionClient(
                _FakeResolvedSource(
                    database_id="database-1",
                    database_title="Tasks",
                    pages=[
                        {
                            "id": "page-1",
                            "url": "https://www.notion.so/page-1",
                            "properties": {
                                "Name": {
                                    "type": "title",
                                    "title": [{"plain_text": "Safe quest"}],
                                },
                            },
                        },
                    ],
                )
            ),
            notion_connection_repository=connection_repository,
            profile_repository=_UnusedProfileRepository(),  # type: ignore[arg-type]
            quest_repository=quest_repository,  # type: ignore[arg-type]
            secret_cipher=_PassThroughCipher(),  # type: ignore[arg-type]
        )

        with self.assertRaisesRegex(IntegrationException, "disconnected"):
            service.sync("user-1", NotionSyncRequest())

        self.assertEqual(quest_repository.upsert_calls, 1)
        self.assertEqual(connection_repository.ensure_still_connected_calls, ["connection-1"])
        self.assertEqual(connection_repository.mark_synced_calls, ["connection-1"])
        self.assertEqual(connection_repository.mark_synced_success_updates, 0)
        self.assertNotIn("last_successful_synced_at", connection_repository.connection)
        self.assertEqual(
            connection_repository.mark_failed_calls,
            [
                (
                    "connection-1",
                    "The Notion connection was disconnected. Reconnect before syncing again.",
                )
            ],
        )

    def test_sync_cancels_before_quest_write_when_disconnect_happens_after_notion_fetch(self) -> None:
        connection_repository = _SyncConnectionRepository(
            {
                "id": "connection-1",
                "profile_id": "profile-1",
                "access_token_encrypted": "encrypted-token",
                "database_id": "database-1",
                "database_url": "https://www.notion.so/database-1",
                "disconnected_at": None,
            }
        )
        quest_repository = _TrackingQuestRepository()

        def _disconnect_midflight() -> None:
            connection_repository.connection["access_token_encrypted"] = None
            connection_repository.connection["disconnected_at"] = "2026-05-18T01:02:03+00:00"

        service = NotionBackendService(
            notion_client=_FakeNotionClient(
                _FakeResolvedSource(
                    database_id="database-1",
                    database_title="Tasks",
                    pages=[
                        {
                            "id": "page-1",
                            "url": "https://www.notion.so/page-1",
                            "properties": {
                                "Name": {
                                    "type": "title",
                                    "title": [{"plain_text": "Safe quest"}],
                                },
                            },
                        },
                    ],
                ),
                on_resolve=_disconnect_midflight,
            ),
            notion_connection_repository=connection_repository,
            profile_repository=_UnusedProfileRepository(),  # type: ignore[arg-type]
            quest_repository=quest_repository,  # type: ignore[arg-type]
            secret_cipher=_PassThroughCipher(),  # type: ignore[arg-type]
        )

        with self.assertRaisesRegex(IntegrationException, "disconnected"):
            service.sync("user-1", NotionSyncRequest())

        self.assertEqual(connection_repository.ensure_still_connected_calls, ["connection-1"])
        self.assertEqual(quest_repository.upsert_calls, 0)
        self.assertEqual(connection_repository.mark_synced_calls, [])
        self.assertEqual(connection_repository.mark_synced_success_updates, 0)
        self.assertNotIn("last_successful_synced_at", connection_repository.connection)
        self.assertEqual(
            connection_repository.mark_failed_calls,
            [
                (
                    "connection-1",
                    "The Notion connection was disconnected. Reconnect before syncing again.",
                )
            ],
        )

    def test_sync_stores_safe_error_message_when_notion_api_fails(self) -> None:
        connection_repository = _SyncConnectionRepository(
            {
                "id": "connection-1",
                "profile_id": "profile-1",
                "access_token_encrypted": "encrypted-token",
                "database_id": "database-1",
                "data_source_id": "data-source-1",
                "database_url": "https://www.notion.so/database-1",
                "disconnected_at": None,
            }
        )
        quest_repository = _TrackingQuestRepository()
        service = NotionBackendService(
            notion_client=_FakeNotionClient(
                resolve_error=NotionClientError("401:unauthorized:Bearer token leaked"),
            ),  # type: ignore[arg-type]
            notion_connection_repository=connection_repository,
            profile_repository=_UnusedProfileRepository(),  # type: ignore[arg-type]
            quest_repository=quest_repository,  # type: ignore[arg-type]
            secret_cipher=_PassThroughCipher(),  # type: ignore[arg-type]
        )

        with self.assertRaisesRegex(IntegrationException, "Notion access was denied"):
            service.sync("user-1", NotionSyncRequest())

        self.assertEqual(
            connection_repository.mark_failed_calls,
            [
                (
                    "connection-1",
                    "Notion access was denied. Reconnect the integration and try again.",
                )
            ],
        )

    def test_sync_wraps_unexpected_repository_error_with_safe_message(self) -> None:
        connection_repository = _SyncConnectionRepository(
            {
                "id": "connection-1",
                "profile_id": "profile-1",
                "access_token_encrypted": "encrypted-token",
                "database_id": "database-1",
                "data_source_id": "data-source-1",
                "database_url": "https://www.notion.so/database-1",
                "disconnected_at": None,
            }
        )
        service = NotionBackendService(
            notion_client=_FakeNotionClient(
                _FakeResolvedSource(
                    database_id="database-1",
                    database_title="Tasks",
                    pages=[
                        {
                            "id": "page-1",
                            "url": "https://www.notion.so/page-1",
                            "properties": {
                                "Name": {
                                    "type": "title",
                                    "title": [{"plain_text": "Safe quest"}],
                                },
                            },
                        },
                    ],
                )
            ),
            notion_connection_repository=connection_repository,
            profile_repository=_UnusedProfileRepository(),  # type: ignore[arg-type]
            quest_repository=_ExplodingQuestRepository(),  # type: ignore[arg-type]
            secret_cipher=_PassThroughCipher(),  # type: ignore[arg-type]
        )

        with self.assertRaisesRegex(
            IntegrationException,
            "The last Notion sync failed. Reconnect the integration or try again.",
        ):
            service.sync("user-1", NotionSyncRequest())

        self.assertEqual(
            connection_repository.mark_failed_calls,
            [
                (
                    "connection-1",
                    "The last Notion sync failed. Reconnect the integration or try again. "
                    "Reason: Unexpected repository crash during Notion quest upsert",
                )
            ],
        )


class NotionStatusServiceTest(unittest.TestCase):
    def test_get_status_returns_disconnected_false_when_missing(self) -> None:
        service = NotionBackendService(
            notion_client=None,  # type: ignore[arg-type]
            notion_connection_repository=_StatusOnlyConnectionRepository(None),
            profile_repository=_UnusedProfileRepository(),  # type: ignore[arg-type]
            quest_repository=_UnusedQuestRepository(),  # type: ignore[arg-type]
            secret_cipher=_UnusedCipher(),  # type: ignore[arg-type]
        )

        result = service.get_status("user-1")

        self.assertFalse(result.connected)
        self.assertIsNone(result.connection_id)

    def test_get_status_returns_connected_server_view(self) -> None:
        service = NotionBackendService(
            notion_client=None,  # type: ignore[arg-type]
            notion_connection_repository=_StatusOnlyConnectionRepository(
                {
                    "id": "connection-1",
                    "database_id": "database-1",
                    "data_source_id": "data-source-1",
                    "database_title": "Tasks",
                    "database_url": "https://www.notion.so/tasks",
                    "access_token_encrypted": "encrypted",
                    "disconnected_at": None,
                    "last_synced_at": "2026-05-18T01:02:03+00:00",
                    "last_successful_synced_at": "2026-05-18T01:02:03+00:00",
                    "sync_status": "active",
                    "last_error_message": None,
                }
            ),
            profile_repository=_UnusedProfileRepository(),  # type: ignore[arg-type]
            quest_repository=_UnusedQuestRepository(),  # type: ignore[arg-type]
            secret_cipher=_UnusedCipher(),  # type: ignore[arg-type]
        )

        result = service.get_status("user-1")

        self.assertTrue(result.connected)
        self.assertEqual(result.connection_id, "connection-1")
        self.assertEqual(result.database_id, "database-1")
        self.assertEqual(result.data_source_id, "data-source-1")
        self.assertEqual(result.sync_status, "success")

    def test_get_status_returns_connected_false_after_disconnect(self) -> None:
        service = NotionBackendService(
            notion_client=None,  # type: ignore[arg-type]
            notion_connection_repository=_StatusOnlyConnectionRepository(
                {
                    "id": "connection-1",
                    "database_id": "database-1",
                    "access_token_encrypted": None,
                    "disconnected_at": "2026-05-18T01:02:03+00:00",
                    "sync_status": "disconnected",
                }
            ),
            profile_repository=_UnusedProfileRepository(),  # type: ignore[arg-type]
            quest_repository=_UnusedQuestRepository(),  # type: ignore[arg-type]
            secret_cipher=_UnusedCipher(),  # type: ignore[arg-type]
        )

        result = service.get_status("user-1")

        self.assertFalse(result.connected)
        self.assertEqual(result.sync_status, "disconnected")

    def test_get_status_sanitizes_sensitive_last_error_message(self) -> None:
        service = NotionBackendService(
            notion_client=None,  # type: ignore[arg-type]
            notion_connection_repository=_StatusOnlyConnectionRepository(
                {
                    "id": "connection-1",
                    "database_id": "database-1",
                    "access_token_encrypted": "encrypted",
                    "disconnected_at": None,
                    "sync_status": "error",
                    "last_error_message": (
                        "401 unauthorized bearer ntn_secret_abc authorization=Bearer xyz"
                    ),
                }
            ),
            profile_repository=_UnusedProfileRepository(),  # type: ignore[arg-type]
            quest_repository=_UnusedQuestRepository(),  # type: ignore[arg-type]
            secret_cipher=_UnusedCipher(),  # type: ignore[arg-type]
        )

        result = service.get_status("user-1")

        self.assertEqual(
            result.last_error_message,
            "The last Notion sync failed. Reconnect the integration or try again.",
        )
        self.assertNotIn("token", result.last_error_message.lower())
        self.assertNotIn("secret", result.last_error_message.lower())
        self.assertNotIn("authorization", result.last_error_message.lower())
        self.assertNotIn("bearer", result.last_error_message.lower())
        self.assertNotIn("encrypted", result.last_error_message.lower())

    def test_get_status_sanitizes_raw_exception_text(self) -> None:
        service = NotionBackendService(
            notion_client=None,  # type: ignore[arg-type]
            notion_connection_repository=_StatusOnlyConnectionRepository(
                {
                    "id": "connection-1",
                    "database_id": "database-1",
                    "access_token_encrypted": "encrypted",
                    "disconnected_at": None,
                    "sync_status": "error",
                    "last_error_message": "RuntimeError: Authorization bearer token leaked",
                }
            ),
            profile_repository=_UnusedProfileRepository(),  # type: ignore[arg-type]
            quest_repository=_UnusedQuestRepository(),  # type: ignore[arg-type]
            secret_cipher=_UnusedCipher(),  # type: ignore[arg-type]
        )

        result = service.get_status("user-1")

        self.assertEqual(
            result.last_error_message,
            "The last Notion sync failed. Reconnect the integration or try again.",
        )
        self.assertNotIn("runtimeerror", result.last_error_message.lower())
        self.assertNotIn("authorization", result.last_error_message.lower())
        self.assertNotIn("bearer", result.last_error_message.lower())
        self.assertNotIn("token", result.last_error_message.lower())

    def test_get_status_returns_user_friendly_last_error_message(self) -> None:
        service = NotionBackendService(
            notion_client=None,  # type: ignore[arg-type]
            notion_connection_repository=_StatusOnlyConnectionRepository(
                {
                    "id": "connection-1",
                    "database_id": "database-1",
                    "access_token_encrypted": "encrypted",
                    "disconnected_at": None,
                    "sync_status": "error",
                    "last_error_message": "404:object_not_found:Database missing",
                }
            ),
            profile_repository=_UnusedProfileRepository(),  # type: ignore[arg-type]
            quest_repository=_UnusedQuestRepository(),  # type: ignore[arg-type]
            secret_cipher=_UnusedCipher(),  # type: ignore[arg-type]
        )

        result = service.get_status("user-1")

        self.assertEqual(
            result.last_error_message,
            "The selected Notion database or data source could not be found.",
        )

    def test_disconnect_delegates_to_repository(self) -> None:
        repository = _StatusOnlyConnectionRepository(None)
        service = NotionBackendService(
            notion_client=None,  # type: ignore[arg-type]
            notion_connection_repository=repository,
            profile_repository=_UnusedProfileRepository(),  # type: ignore[arg-type]
            quest_repository=_UnusedQuestRepository(),  # type: ignore[arg-type]
            secret_cipher=_UnusedCipher(),  # type: ignore[arg-type]
        )

        service.disconnect("user-1")

        self.assertEqual(repository.disconnect_calls, ["user-1"])

    def test_disconnect_then_status_returns_connected_false(self) -> None:
        repository = _MutableStatusConnectionRepository(
            {
                "id": "connection-1",
                "database_id": "database-1",
                "database_title": "Tasks",
                "database_url": "https://www.notion.so/tasks",
                "access_token_encrypted": "encrypted",
                "refresh_token_encrypted": "refresh",
                "disconnected_at": None,
                "sync_status": "active",
                "last_error_message": "old error",
            }
        )
        service = NotionBackendService(
            notion_client=None,  # type: ignore[arg-type]
            notion_connection_repository=repository,
            profile_repository=_UnusedProfileRepository(),  # type: ignore[arg-type]
            quest_repository=_UnusedQuestRepository(),  # type: ignore[arg-type]
            secret_cipher=_UnusedCipher(),  # type: ignore[arg-type]
        )

        service.disconnect("user-1")
        result = service.get_status("user-1")

        self.assertFalse(result.connected)
        self.assertEqual(result.sync_status, "disconnected")


if __name__ == "__main__":
    unittest.main()
