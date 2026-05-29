from datetime import UTC, datetime
from typing import Any


class NotionConnectionRepository:
    def __init__(self, client: Any) -> None:
        self._client = client

    def upsert_connection(
        self,
        *,
        user_id: str,
        profile_id: str,
        database_id: str,
        database_title: str,
        database_url: str,
        access_token_encrypted: str,
        data_source_id: str | None = None,
        api_version: str | None = None,
        sync_status: str = "active",
    ) -> dict[str, Any]:
        existing_for_database = (
            self._client.table("notion_connections")
            .select("id")
            .eq("user_id", user_id)
            .eq("database_id", database_id)
            .limit(1)
            .execute()
        )
        rows = existing_for_database.data or []
        existing = rows[0] if rows else self.find_connection_by_user_id(user_id)
        payload = {
            "user_id": user_id,
            "profile_id": profile_id,
            "database_id": database_id,
            "data_source_id": data_source_id or database_id,
            "database_title": database_title,
            "database_url": database_url,
            "access_token_encrypted": access_token_encrypted,
            "api_version": api_version,
            "disconnected_at": None,
            "last_error_message": None,
            "sync_status": sync_status,
        }
        if existing:
            response = (
                self._client.table("notion_connections")
                .update(payload)
                .eq("id", existing["id"])
                .execute()
            )
            return (response.data or [])[0]

        response = self._client.table("notion_connections").insert(payload).execute()
        return (response.data or [])[0]

    def get_connection_by_user_id(self, user_id: str) -> dict[str, Any]:
        connection = self.find_connection_by_user_id(user_id)
        if connection is None:
            raise ValueError("No saved Notion connection was found for this user.")
        return connection

    def get_connected_connection_by_user_id(self, user_id: str) -> dict[str, Any]:
        connection = self.get_connection_by_user_id(user_id)
        _ensure_connection_is_connected(
            connection,
            message="The saved Notion connection is disconnected. Reconnect before syncing.",
        )
        return connection

    def find_connection_by_user_id(self, user_id: str) -> dict[str, Any] | None:
        response = (
            self._client.table("notion_connections")
            .select("*")
            .eq("user_id", user_id)
            .order("updated_at", desc=True)
            .limit(1)
            .execute()
        )
        rows = response.data or []
        return rows[0] if rows else None

    def find_connection_by_id(self, connection_id: str) -> dict[str, Any] | None:
        response = (
            self._client.table("notion_connections")
            .select("*")
            .eq("id", connection_id)
            .limit(1)
            .execute()
        )
        rows = response.data or []
        return rows[0] if rows else None

    def ensure_connection_still_connected(self, connection_id: str) -> dict[str, Any]:
        connection = self.find_connection_by_id(connection_id)
        if connection is None:
            raise ValueError("The saved Notion connection no longer exists.")
        _ensure_connection_is_connected(
            connection,
            message="The saved Notion connection was disconnected before sync completed.",
        )
        return connection

    def mark_synced(self, connection_id: str) -> None:
        now = datetime.now(UTC).isoformat()
        (
            self._client.table("notion_connections")
            .update(
                {
                    "last_synced_at": now,
                    "last_successful_synced_at": now,
                    "last_error_message": None,
                    "sync_status": "active",
                },
            )
            .eq("id", connection_id)
            .execute()
        )

    def mark_synced_if_connected(self, connection_id: str) -> bool:
        connection = self.find_connection_by_id(connection_id)
        if connection is None or not _is_connection_connected(connection):
            return False

        now = datetime.now(UTC).isoformat()
        (
            self._client.table("notion_connections")
            .update(
                {
                    "last_synced_at": now,
                    "last_successful_synced_at": now,
                    "last_error_message": None,
                    "sync_status": "active",
                },
            )
            .eq("id", connection_id)
            .execute()
        )
        return True

    def mark_failed_if_connected(
        self,
        connection_id: str,
        *,
        public_error_message: str,
    ) -> bool:
        connection = self.find_connection_by_id(connection_id)
        if connection is None or not _is_connection_connected(connection):
            return False

        now = datetime.now(UTC).isoformat()
        (
            self._client.table("notion_connections")
            .update(
                {
                    "last_synced_at": now,
                    "last_error_message": public_error_message,
                    "sync_status": "error",
                },
            )
            .eq("id", connection_id)
            .execute()
        )
        return True

    def disconnect_by_user_id(self, user_id: str) -> None:
        connection = self.find_connection_by_user_id(user_id)
        if connection is None:
            return

        now = connection.get("disconnected_at") or datetime.now(UTC).isoformat()
        (
            self._client.table("notion_connections")
            .update(
                {
                    "access_token_encrypted": None,
                    "refresh_token_encrypted": None,
                    "disconnected_at": now,
                    "sync_status": "disconnected",
                    "last_error_message": None,
                },
            )
            .eq("id", connection["id"])
            .execute()
        )


def _is_connection_connected(connection: dict[str, Any]) -> bool:
    return bool(
        connection.get("disconnected_at") is None
        and connection.get("access_token_encrypted")
    )


def _ensure_connection_is_connected(
    connection: dict[str, Any],
    *,
    message: str,
) -> None:
    if not _is_connection_connected(connection):
        raise ValueError(message)
