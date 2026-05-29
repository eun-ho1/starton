import unittest
from types import SimpleNamespace

from app.providers.notion_client import (
    NotionClient,
    NotionClientError,
    ResolvedNotionSource,
    extract_notion_identifiers,
    extract_notion_identifier,
)
from app.repositories.notion_connection_repository import NotionConnectionRepository
from app.schemas.notion import NotionConnectRequest
from app.services.notion_backend_service import NotionBackendService
from app.services.notion_sync_service import IntegrationException


class _RepositoryFakeResponse:
    def __init__(self, data=None) -> None:
        self.data = data


class _RepositoryFakeTable:
    def __init__(self, rows: list[dict]) -> None:
        self.rows = rows
        self._selected_columns: str | None = None
        self._filters: dict[str, object] = {}
        self._limit: int | None = None
        self._order_by: str | None = None
        self._order_desc = False
        self._pending_update: dict | None = None
        self._pending_insert: dict | None = None

    def select(self, columns: str):
        self._selected_columns = columns
        return self

    def eq(self, column: str, value: object):
        self._filters[column] = value
        return self

    def limit(self, value: int):
        self._limit = value
        return self

    def order(self, column: str, desc: bool = False):
        self._order_by = column
        self._order_desc = desc
        return self

    def update(self, payload: dict):
        self._pending_update = payload
        return self

    def insert(self, payload: dict):
        self._pending_insert = payload
        return self

    def execute(self):
        matched_rows = [
            row for row in self.rows
            if all(row.get(column) == value for column, value in self._filters.items())
        ]

        if self._pending_update is not None:
            for row in matched_rows:
                row.update(self._pending_update)
            data = [dict(row) for row in matched_rows]
            self._reset()
            return _RepositoryFakeResponse(data=data)

        if self._pending_insert is not None:
            inserted = dict(self._pending_insert)
            inserted.setdefault("id", f"connection-{len(self.rows) + 1}")
            self.rows.append(inserted)
            self._reset()
            return _RepositoryFakeResponse(data=[dict(inserted)])

        rows = [dict(row) for row in matched_rows]
        if self._order_by is not None:
            rows.sort(
                key=lambda row: row.get(self._order_by) or "",
                reverse=self._order_desc,
            )
        if self._limit is not None:
            rows = rows[: self._limit]
        selected_rows = [_select_columns(row, self._selected_columns) for row in rows]
        self._reset()
        return _RepositoryFakeResponse(data=selected_rows)

    def _reset(self) -> None:
        self._selected_columns = None
        self._filters = {}
        self._limit = None
        self._order_by = None
        self._order_desc = False
        self._pending_update = None
        self._pending_insert = None


class _RepositoryFakeClient:
    def __init__(
        self,
        notion_connections_rows: list[dict] | None = None,
        quests_rows: list[dict] | None = None,
    ) -> None:
        self._tables = {
            "notion_connections": _RepositoryFakeTable(notion_connections_rows or []),
            "quests": _RepositoryFakeTable(quests_rows or []),
        }

    def table(self, name: str) -> _RepositoryFakeTable:
        return self._tables[name]


def _select_columns(row: dict, columns: str | None) -> dict:
    if not columns or columns.strip() == "*":
        return dict(row)
    selected = {}
    for column in columns.split(","):
        key = column.strip()
        if key:
            selected[key] = row.get(key)
    return selected


class _FakeConnectNotionClient:
    def __init__(
        self,
        *,
        resolved: ResolvedNotionSource | None = None,
        validate_error: Exception | None = None,
        resolve_error: Exception | None = None,
    ) -> None:
        self.resolved = resolved
        self.validate_error = validate_error
        self.resolve_error = resolve_error
        self.validated_tokens: list[str] = []
        self.resolve_calls: list[dict[str, object]] = []

    def validate_integration_secret(self, *, notion_api_token: str) -> None:
        self.validated_tokens.append(notion_api_token)
        if self.validate_error is not None:
            raise self.validate_error

    def resolve_source(self, **kwargs):
        self.resolve_calls.append(kwargs)
        if self.resolve_error is not None:
            raise self.resolve_error
        return self.resolved


class _RequestStubNotionClient(NotionClient):
    def __init__(self, responses: dict[tuple[str, str], object]) -> None:
        self.responses = responses

    def _request_json(
        self,
        *,
        method: str,
        path: str,
        notion_api_token: str,
        body: dict[str, object] | None = None,
    ) -> dict:
        response = self.responses[(method, path)]
        if isinstance(response, Exception):
            raise response
        return response


class _FakeProfileRepository:
    def get_profile_state(self, user_id: str):
        return SimpleNamespace(profile_id="profile-1")


class _FakeCipher:
    def __init__(self) -> None:
        self.encrypted_values: list[str] = []

    def encrypt(self, value: str) -> str:
        self.encrypted_values.append(value)
        return f"encrypted:{value}"


class _TrackingConnectionRepository:
    def __init__(self) -> None:
        self.upsert_calls: list[dict[str, object]] = []

    def upsert_connection(self, **kwargs):
        self.upsert_calls.append(kwargs)
        return {
            "id": "connection-1",
            "sync_status": "active",
            "disconnected_at": None,
        }


class NotionConnectProviderTest(unittest.TestCase):
    def test_extract_notion_identifier_from_url_normalizes_uuid(self) -> None:
        identifier = extract_notion_identifier(
            database_url=(
                "https://www.notion.so/My-Tasks-35bdd41fce07815292aedabdfc826f3b"
            ),
        )

        self.assertEqual(identifier, "35bdd41f-ce07-8152-92ae-dabdfc826f3b")

    def test_extract_notion_identifiers_from_url_keeps_all_unique_candidates(self) -> None:
        identifiers = extract_notion_identifiers(
            database_url=(
                "https://www.notion.so/My-Tasks-35bdd41fce07815292aedabdfc826f3b"
                "?v=36c9dc177c568025be14efd9fd040a84"
            ),
        )

        self.assertEqual(
            identifiers,
            [
                "35bdd41f-ce07-8152-92ae-dabdfc826f3b",
                "36c9dc17-7c56-8025-be14-efd9fd040a84",
            ],
        )

    def test_resolve_source_uses_parent_database_when_page_url_is_provided(self) -> None:
        client = _RequestStubNotionClient(
            {
                (
                    "GET",
                    "/v1/data_sources/36c9dc17-7c56-8025-be14-efd9fd040a84",
                ): NotionClientError("404:object_not_found:Could not find data source"),
                (
                    "GET",
                    "/v1/databases/36c9dc17-7c56-8025-be14-efd9fd040a84",
                ): NotionClientError("404:object_not_found:Could not find database"),
                (
                    "GET",
                    "/v1/pages/36c9dc17-7c56-8025-be14-efd9fd040a84",
                ): {
                    "parent": {
                        "type": "database_id",
                        "database_id": "35bdd41f-ce07-8152-92ae-dabdfc826f3b",
                    }
                },
                (
                    "GET",
                    "/v1/databases/35bdd41f-ce07-8152-92ae-dabdfc826f3b",
                ): {
                    "title": [{"plain_text": "Tasks"}],
                    "data_sources": [{"id": "46bdd41f-ce07-8152-92ae-dabdfc826f3b"}],
                },
                (
                    "POST",
                    "/v1/data_sources/46bdd41f-ce07-8152-92ae-dabdfc826f3b/query",
                ): {
                    "results": [{"id": "page-1"}],
                    "has_more": False,
                },
            },
        )

        resolved = client.resolve_source(
            notion_api_token="secret",
            database_url=(
                "https://www.notion.so/36c9dc177c568025be14efd9fd040a84"
            ),
        )

        self.assertEqual(resolved.database_id, "35bdd41f-ce07-8152-92ae-dabdfc826f3b")
        self.assertEqual(resolved.data_source_id, "46bdd41f-ce07-8152-92ae-dabdfc826f3b")
        self.assertEqual(resolved.database_title, "Tasks")
        self.assertEqual(resolved.pages, [{"id": "page-1"}])

    def test_resolve_source_rejects_page_without_database_parent(self) -> None:
        client = _RequestStubNotionClient(
            {
                (
                    "GET",
                    "/v1/data_sources/36c9dc17-7c56-8025-be14-efd9fd040a84",
                ): NotionClientError("404:object_not_found:Could not find data source"),
                (
                    "GET",
                    "/v1/databases/36c9dc17-7c56-8025-be14-efd9fd040a84",
                ): NotionClientError("404:object_not_found:Could not find database"),
                (
                    "GET",
                    "/v1/pages/36c9dc17-7c56-8025-be14-efd9fd040a84",
                ): {
                    "parent": {
                        "type": "workspace",
                        "workspace": True,
                    }
                },
            },
        )

        with self.assertRaisesRegex(
            NotionClientError,
            "not connected to a database or data source",
        ):
            client.resolve_source(
                notion_api_token="secret",
                database_url=(
                    "https://www.notion.so/36c9dc177c568025be14efd9fd040a84"
                ),
            )

    def test_resolve_source_tries_multiple_ids_found_in_url(self) -> None:
        client = _RequestStubNotionClient(
            {
                (
                    "GET",
                    "/v1/data_sources/11111111-1111-1111-1111-111111111111",
                ): NotionClientError("404:object_not_found:Could not find data source"),
                (
                    "GET",
                    "/v1/databases/11111111-1111-1111-1111-111111111111",
                ): NotionClientError(
                    "400:validation_error:Provided database id is invalid",
                ),
                (
                    "GET",
                    "/v1/pages/11111111-1111-1111-1111-111111111111",
                ): NotionClientError("404:object_not_found:Could not find page"),
                (
                    "GET",
                    "/v1/data_sources/36c9dc17-7c56-8025-be14-efd9fd040a84",
                ): NotionClientError("404:object_not_found:Could not find data source"),
                (
                    "GET",
                    "/v1/databases/36c9dc17-7c56-8025-be14-efd9fd040a84",
                ): NotionClientError("404:object_not_found:Could not find database"),
                (
                    "GET",
                    "/v1/pages/36c9dc17-7c56-8025-be14-efd9fd040a84",
                ): {
                    "parent": {
                        "type": "database_id",
                        "database_id": "35bdd41f-ce07-8152-92ae-dabdfc826f3b",
                    }
                },
                (
                    "GET",
                    "/v1/databases/35bdd41f-ce07-8152-92ae-dabdfc826f3b",
                ): {
                    "title": [{"plain_text": "Tasks"}],
                    "data_sources": [{"id": "46bdd41f-ce07-8152-92ae-dabdfc826f3b"}],
                },
                (
                    "POST",
                    "/v1/data_sources/46bdd41f-ce07-8152-92ae-dabdfc826f3b/query",
                ): {
                    "results": [{"id": "page-1"}],
                    "has_more": False,
                },
            },
        )

        resolved = client.resolve_source(
            notion_api_token="secret",
            database_url=(
                "https://www.notion.so/My-Tasks-11111111111111111111111111111111"
                "?p=36c9dc177c568025be14efd9fd040a84"
            ),
        )

        self.assertEqual(resolved.database_id, "35bdd41f-ce07-8152-92ae-dabdfc826f3b")
        self.assertEqual(resolved.data_source_id, "46bdd41f-ce07-8152-92ae-dabdfc826f3b")


class NotionConnectRepositoryTest(unittest.TestCase):
    def test_upsert_connection_reconnects_existing_row_and_clears_disconnected_at(self) -> None:
        client = _RepositoryFakeClient(
            notion_connections_rows=[
                {
                    "id": "connection-1",
                    "user_id": "user-1",
                    "profile_id": "profile-old",
                    "database_id": "old-db",
                    "database_title": "Old title",
                    "database_url": "https://old.example",
                    "access_token_encrypted": None,
                    "data_source_id": "old-ds",
                    "api_version": "2025-01-01",
                    "disconnected_at": "2026-05-18T01:02:03+00:00",
                    "last_error_message": "old error",
                    "sync_status": "disconnected",
                    "updated_at": "2026-05-18T01:02:03+00:00",
                }
            ],
        )
        repository = NotionConnectionRepository(client)

        row = repository.upsert_connection(
            user_id="user-1",
            profile_id="profile-1",
            database_id="new-db",
            database_title="Tasks",
            database_url="https://www.notion.so/tasks",
            access_token_encrypted="encrypted:new-secret",
            data_source_id="new-ds",
            api_version="2026-03-11",
            sync_status="active",
        )

        self.assertEqual(row["id"], "connection-1")
        self.assertEqual(row["database_id"], "new-db")
        self.assertEqual(row["data_source_id"], "new-ds")
        self.assertEqual(row["access_token_encrypted"], "encrypted:new-secret")
        self.assertIsNone(row["disconnected_at"])
        self.assertIsNone(row["last_error_message"])
        self.assertEqual(row["sync_status"], "active")
        self.assertEqual(len(client.table("notion_connections").rows), 1)

    def test_disconnect_clears_credentials_and_keeps_imported_quests(self) -> None:
        client = _RepositoryFakeClient(
            notion_connections_rows=[
                {
                    "id": "connection-1",
                    "user_id": "user-1",
                    "profile_id": "profile-1",
                    "database_id": "db-1",
                    "database_title": "Tasks",
                    "database_url": "https://www.notion.so/tasks",
                    "access_token_encrypted": "encrypted:secret",
                    "refresh_token_encrypted": "encrypted:refresh",
                    "disconnected_at": None,
                    "sync_status": "active",
                    "last_error_message": "old error",
                    "updated_at": "2026-05-18T01:02:03+00:00",
                }
            ],
            quests_rows=[
                {
                    "id": "quest-1",
                    "user_id": "user-1",
                    "external_source": "notion",
                    "external_id": "page-1",
                    "title": "Imported quest",
                }
            ],
        )
        repository = NotionConnectionRepository(client)

        repository.disconnect_by_user_id("user-1")

        connection = client.table("notion_connections").rows[0]
        self.assertIsNone(connection["access_token_encrypted"])
        self.assertIsNone(connection["refresh_token_encrypted"])
        self.assertIsNotNone(connection["disconnected_at"])
        self.assertEqual(connection["sync_status"], "disconnected")
        self.assertIsNone(connection["last_error_message"])
        self.assertEqual(len(client.table("quests").rows), 1)
        self.assertEqual(client.table("quests").rows[0]["title"], "Imported quest")

    def test_disconnect_is_idempotent_when_connection_is_already_disconnected(self) -> None:
        client = _RepositoryFakeClient(
            notion_connections_rows=[
                {
                    "id": "connection-1",
                    "user_id": "user-1",
                    "profile_id": "profile-1",
                    "database_id": "db-1",
                    "database_title": "Tasks",
                    "database_url": "https://www.notion.so/tasks",
                    "access_token_encrypted": None,
                    "refresh_token_encrypted": None,
                    "disconnected_at": "2026-05-18T01:02:03+00:00",
                    "sync_status": "disconnected",
                    "last_error_message": None,
                    "updated_at": "2026-05-18T01:02:03+00:00",
                }
            ],
        )
        repository = NotionConnectionRepository(client)

        repository.disconnect_by_user_id("user-1")
        repository.disconnect_by_user_id("user-1")

        connection = client.table("notion_connections").rows[0]
        self.assertIsNone(connection["access_token_encrypted"])
        self.assertIsNone(connection["refresh_token_encrypted"])
        self.assertEqual(connection["disconnected_at"], "2026-05-18T01:02:03+00:00")
        self.assertEqual(connection["sync_status"], "disconnected")


class NotionConnectServiceTest(unittest.TestCase):
    def test_connect_succeeds_with_valid_secret_and_database_id(self) -> None:
        notion_client = _FakeConnectNotionClient(
            resolved=ResolvedNotionSource(
                database_id="35bdd41f-ce07-8152-92ae-dabdfc826f3b",
                data_source_id="55bdd41f-ce07-8152-92ae-dabdfc826f3b",
                database_title="Tasks",
                database_url="https://www.notion.so/tasks",
                pages=[],
            ),
        )
        connection_repository = _TrackingConnectionRepository()
        cipher = _FakeCipher()
        service = NotionBackendService(
            notion_client=notion_client,  # type: ignore[arg-type]
            notion_connection_repository=connection_repository,  # type: ignore[arg-type]
            profile_repository=_FakeProfileRepository(),  # type: ignore[arg-type]
            quest_repository=SimpleNamespace(),  # type: ignore[arg-type]
            secret_cipher=cipher,  # type: ignore[arg-type]
        )

        response = service.connect(
            "user-1",
            NotionConnectRequest(
                notion_api_token="secret_123",
                database_id="35bdd41f-ce07-8152-92ae-dabdfc826f3b",
            ),
        )

        self.assertEqual(notion_client.validated_tokens, ["secret_123"])
        self.assertEqual(len(notion_client.resolve_calls), 1)
        self.assertEqual(
            notion_client.resolve_calls[0]["database_id"],
            "35bdd41f-ce07-8152-92ae-dabdfc826f3b",
        )
        self.assertEqual(cipher.encrypted_values, ["secret_123"])
        self.assertEqual(
            connection_repository.upsert_calls[0]["access_token_encrypted"],
            "encrypted:secret_123",
        )
        self.assertEqual(
            connection_repository.upsert_calls[0]["data_source_id"],
            "55bdd41f-ce07-8152-92ae-dabdfc826f3b",
        )
        self.assertEqual(response.connection_id, "connection-1")
        self.assertEqual(response.database_title, "Tasks")
        dumped = response.model_dump()
        self.assertNotIn("secret", dumped)
        self.assertNotIn("token", dumped)
        self.assertNotIn("encrypted", dumped)

    def test_connect_fails_when_secret_is_invalid(self) -> None:
        service = NotionBackendService(
            notion_client=_FakeConnectNotionClient(
                validate_error=NotionClientError("401:unauthorized:Invalid auth"),
            ),  # type: ignore[arg-type]
            notion_connection_repository=_TrackingConnectionRepository(),  # type: ignore[arg-type]
            profile_repository=_FakeProfileRepository(),  # type: ignore[arg-type]
            quest_repository=SimpleNamespace(),  # type: ignore[arg-type]
            secret_cipher=_FakeCipher(),  # type: ignore[arg-type]
        )

        with self.assertRaisesRegex(IntegrationException, "401:unauthorized"):
            service.connect(
                "user-1",
                NotionConnectRequest(
                    notion_api_token="bad-secret",
                    database_id="35bdd41f-ce07-8152-92ae-dabdfc826f3b",
                ),
            )

    def test_connect_fails_when_database_is_not_shared_with_integration(self) -> None:
        notion_client = _FakeConnectNotionClient(
            resolved=None,
            resolve_error=NotionClientError(
                "404:object_not_found:Could not find database",
            ),
        )
        service = NotionBackendService(
            notion_client=notion_client,  # type: ignore[arg-type]
            notion_connection_repository=_TrackingConnectionRepository(),  # type: ignore[arg-type]
            profile_repository=_FakeProfileRepository(),  # type: ignore[arg-type]
            quest_repository=SimpleNamespace(),  # type: ignore[arg-type]
            secret_cipher=_FakeCipher(),  # type: ignore[arg-type]
        )

        with self.assertRaisesRegex(IntegrationException, "object_not_found"):
            service.connect(
                "user-1",
                NotionConnectRequest(
                    notion_api_token="secret_123",
                    database_id="35bdd41f-ce07-8152-92ae-dabdfc826f3b",
                ),
            )


if __name__ == "__main__":
    unittest.main()
