import logging

from app.core.crypto import SecretCipher
from app.providers.notion_client import NOTION_API_VERSION, NotionClient, NotionClientError
from app.repositories.notion_connection_repository import NotionConnectionRepository
from app.repositories.profile_repository import SupabaseProfileRepository
from app.repositories.quest_repository import NotionQuestUpsertSummary, SupabaseQuestRepository
from app.schemas.notion import (
    NotionConnectionStatusResponse,
    NotionConnectRequest,
    NotionConnectResponse,
    NotionSyncRequest,
    NotionSyncResponse,
)
from app.services.notion_parser import parse_notion_pages_to_quests
from app.services.notion_sync_service import IntegrationException

logger = logging.getLogger(__name__)


class NotionBackendService:
    def __init__(
        self,
        *,
        notion_client: NotionClient,
        notion_connection_repository: NotionConnectionRepository,
        profile_repository: SupabaseProfileRepository,
        quest_repository: SupabaseQuestRepository,
        secret_cipher: SecretCipher,
    ) -> None:
        self._notion_client = notion_client
        self._notion_connection_repository = notion_connection_repository
        self._profile_repository = profile_repository
        self._quest_repository = quest_repository
        self._secret_cipher = secret_cipher

    def connect(self, user_id: str, request: NotionConnectRequest) -> NotionConnectResponse:
        try:
            self._notion_client.validate_integration_secret(
                notion_api_token=request.notion_api_token,
            )
            resolved = self._notion_client.resolve_source(
                notion_api_token=request.notion_api_token,
                data_source_id=request.data_source_id,
                database_id=request.database_id,
                database_url=request.database_url,
            )
            profile = self._profile_repository.get_profile_state(user_id)
            connection = self._notion_connection_repository.upsert_connection(
                user_id=user_id,
                profile_id=profile.profile_id,
                database_id=resolved.database_id,
                database_title=resolved.database_title,
                database_url=resolved.database_url or request.database_url or resolved.database_id,
                access_token_encrypted=self._secret_cipher.encrypt(
                    request.notion_api_token.strip(),
                ),
                data_source_id=resolved.data_source_id,
                api_version=NOTION_API_VERSION,
                sync_status="active",
            )
            return NotionConnectResponse(
                connection_id=connection["id"],
                database_id=resolved.database_id,
                database_title=resolved.database_title,
                sync_status=connection.get("sync_status", "active"),
            )
        except NotionClientError as error:
            logger.exception("Notion connect failed for user_id=%s", user_id)
            raise IntegrationException(str(error)) from error
        except ValueError as error:
            logger.exception("Notion connect validation failed for user_id=%s", user_id)
            raise IntegrationException(str(error)) from error

    def sync(self, user_id: str, request: NotionSyncRequest) -> NotionSyncResponse:
        connection_id: str | None = None
        try:
            connection = self._notion_connection_repository.get_connected_connection_by_user_id(
                user_id,
            )
            connection_id = _require_connection_value(
                connection,
                key="id",
                message="The saved Notion connection no longer exists.",
            )
            notion_token = self._secret_cipher.decrypt(
                _require_connection_value(
                    connection,
                    key="access_token_encrypted",
                    message="The saved Notion connection is disconnected. Reconnect before syncing.",
                ),
            )
            resolved = self._notion_client.resolve_source(
                notion_api_token=notion_token,
                data_source_id=connection.get("data_source_id"),
                database_id=connection.get("database_id"),
                database_url=connection.get("database_url"),
            )
            quests = parse_notion_pages_to_quests(resolved.pages)
            _validate_notion_quest_external_ids(quests)
            # Disconnect can happen while an in-flight sync is talking to Notion.
            # Re-check the saved connection immediately before quest writes so a
            # disconnect that lands after token decryption/API fetch cancels the
            # write path before any quest upsert begins.
            self._notion_connection_repository.ensure_connection_still_connected(
                connection["id"],
            )
            # Repository applies external_updated_at ordering so older sync
            # completions do not overwrite newer Notion page state.
            summary = self._quest_repository.upsert_notion_quests(
                user_id=user_id,
                profile_id=_resolve_connection_profile_id(
                    connection,
                    user_id=user_id,
                    profile_repository=self._profile_repository,
                ),
                source_reference=resolved.database_id,
                quests=quests,
                pages=resolved.pages,
            )
            # Check one more time while storing success metadata. If disconnect
            # won the race after quest writes started, the conditional update
            # below must reject the stale success completion.
            marked_synced = self._notion_connection_repository.mark_synced_if_connected(
                connection["id"],
            )
            if not marked_synced:
                raise ValueError(
                    "The saved Notion connection was disconnected before sync completed.",
                )
            return NotionSyncResponse(
                database_id=resolved.database_id,
                database_title=resolved.database_title,
                quests=quests,
                imported_count=summary.imported_count,
                updated_count=summary.updated_count,
                skipped_count=summary.skipped_count,
                stale_count=summary.stale_count,
            )
        except NotionClientError as error:
            logger.exception("Notion sync failed for user_id=%s", user_id)
            public_message = map_sync_error_message(str(error))
            _store_sync_failure_metadata(
                self._notion_connection_repository,
                connection_id=connection_id,
                public_message=public_message,
            )
            raise IntegrationException(public_message) from error
        except ValueError as error:
            logger.exception("Notion sync validation failed for user_id=%s", user_id)
            public_message = map_sync_error_message(str(error))
            _store_sync_failure_metadata(
                self._notion_connection_repository,
                connection_id=connection_id,
                public_message=public_message,
            )
            raise IntegrationException(public_message) from error
        except Exception as error:
            logger.exception("Unexpected Notion sync failure for user_id=%s", user_id)
            public_message = map_sync_error_message(str(error))
            _store_sync_failure_metadata(
                self._notion_connection_repository,
                connection_id=connection_id,
                public_message=public_message,
            )
            raise IntegrationException(public_message) from error

    def get_status(self, user_id: str) -> NotionConnectionStatusResponse:
        connection = self._notion_connection_repository.find_connection_by_user_id(user_id)
        if connection is None:
            return NotionConnectionStatusResponse(connected=False)

        connected = bool(
            connection.get("disconnected_at") is None
            and connection.get("access_token_encrypted")
        )

        return NotionConnectionStatusResponse(
            connected=connected,
            connection_id=connection.get("id"),
            database_id=connection.get("database_id"),
            data_source_id=connection.get("data_source_id") or connection.get("database_id"),
            database_title=connection.get("database_title"),
            database_url=connection.get("database_url"),
            last_synced_at=connection.get("last_synced_at"),
            last_successful_synced_at=connection.get("last_successful_synced_at"),
            sync_status=_public_sync_status(connection),
            last_error_message=_sanitize_public_error_message(
                connection.get("last_error_message"),
            ),
        )

    def disconnect(self, user_id: str) -> None:
        self._notion_connection_repository.disconnect_by_user_id(user_id)


def _public_sync_status(connection: dict[str, object]) -> str | None:
    raw_status = connection.get("sync_status")
    if not isinstance(raw_status, str) or not raw_status:
        return None
    if raw_status == "active" and (
        connection.get("last_successful_synced_at") or connection.get("last_synced_at")
    ):
        return "success"
    return raw_status


def _require_connection_value(
    connection: dict[str, object],
    *,
    key: str,
    message: str,
) -> str:
    value = connection.get(key)
    normalized = value.strip() if isinstance(value, str) else ""
    if not normalized:
        raise ValueError(message)
    return normalized


def _resolve_connection_profile_id(
    connection: dict[str, object],
    *,
    user_id: str,
    profile_repository: SupabaseProfileRepository,
) -> str:
    existing_profile_id = connection.get("profile_id")
    normalized_profile_id = (
        existing_profile_id.strip()
        if isinstance(existing_profile_id, str)
        else ""
    )
    if normalized_profile_id:
        return normalized_profile_id
    return profile_repository.get_profile_state(user_id).profile_id


def _validate_notion_quest_external_ids(quests: list[object]) -> None:
    for quest in quests:
        external_source = getattr(quest, "external_source", None)
        normalized_source = (
            external_source.strip().lower()
            if isinstance(external_source, str)
            else ""
        )
        if normalized_source != "notion":
            continue

        external_id = getattr(quest, "external_id", None)
        normalized_external_id = (
            external_id.strip() if isinstance(external_id, str) else ""
        )
        if not normalized_external_id:
            raise ValueError(
                "Parsed Notion quest is missing a non-empty external_id (page.id).",
            )


def _sanitize_public_error_message(raw_message: object) -> str | None:
    if not isinstance(raw_message, str):
        return None

    normalized = raw_message.strip()
    if not normalized:
        return None

    lowered = normalized.lower()
    if any(
        keyword in lowered
        for keyword in (
            "token",
            "secret",
            "authorization",
            "bearer",
            "encrypted",
            "password",
            "service_role",
            "api key",
            "api_key",
            "traceback",
            "stack trace",
            "exception",
            "runtimeerror",
            "valueerror",
            "supabase",
        )
    ):
        return "The last Notion sync failed. Reconnect the integration or try again."

    if "disconnected" in lowered:
        return "The Notion connection was disconnected. Reconnect before syncing again."
    if any(keyword in lowered for keyword in ("401", "403", "unauthorized", "forbidden")):
        return "Notion access was denied. Reconnect the integration and try again."
    if any(keyword in lowered for keyword in ("not found", "object_not_found", "404")):
        return "The selected Notion database or data source could not be found."
    if any(keyword in lowered for keyword in ("timeout", "failed to reach", "network")):
        return "Unable to reach Notion right now. Try again later."
    if "decode" in lowered:
        return "Received an invalid response from Notion. Try again later."

    return "The last Notion sync failed. Reconnect the integration or try again."


def map_connect_error_message(raw_message: str) -> str:
    lowered = raw_message.lower()
    identifier_hint = _extract_identifier_hint(raw_message)
    if any(keyword in lowered for keyword in ("401", "unauthorized", "invalid_auth")):
        return _append_identifier_hint(
            "The provided Notion integration secret is invalid. Check the secret and try again.",
            identifier_hint,
        )
    if any(
        keyword in lowered
        for keyword in ("403", "restricted_resource", "object_not_found", "not found", "404")
    ):
        return _append_identifier_hint(
            (
            "The selected Notion database or data source is unavailable, or the integration "
            "does not have access to it. Share the database with the integration and try again."
            ),
            identifier_hint,
        )
    if any(keyword in lowered for keyword in ("failed to reach", "network", "timeout")):
        return _append_identifier_hint(
            "Unable to reach Notion right now. Try again later.",
            identifier_hint,
        )
    if "decode" in lowered:
        return _append_identifier_hint(
            "Received an invalid response from Notion. Try again later.",
            identifier_hint,
        )
    return _append_identifier_hint(raw_message, identifier_hint)


def map_sync_error_message(raw_message: str) -> str:
    lowered = raw_message.lower()
    identifier_hint = _extract_identifier_hint(raw_message)
    if "disconnected" in lowered:
        return _append_identifier_hint(
            "The Notion connection was disconnected. Reconnect before syncing again.",
            identifier_hint,
        )
    if any(keyword in lowered for keyword in ("401", "unauthorized", "invalid_auth")):
        return _append_identifier_hint(
            "Notion access was denied. Reconnect the integration and try again.",
            identifier_hint,
        )
    if any(
        keyword in lowered
        for keyword in ("403", "restricted_resource", "object_not_found", "not found", "404")
    ):
        return _append_identifier_hint(
            (
            "The selected Notion database or data source is unavailable, or the integration "
            "does not have access to it. Share the database with the integration and try again."
            ),
            identifier_hint,
        )
    if "external_id" in lowered or "page.id" in lowered:
        return _append_identifier_hint(
            (
            "Notion sync failed because at least one page is missing a stable page ID. "
            "Check the selected database and try again."
            ),
            identifier_hint,
        )
    if any(keyword in lowered for keyword in ("failed to reach", "network", "timeout")):
        return _append_identifier_hint(
            "Unable to reach Notion right now. Try again later.",
            identifier_hint,
        )
    if "decode" in lowered:
        return _append_identifier_hint(
            "Received an invalid response from Notion. Try again later.",
            identifier_hint,
        )
    return _append_identifier_hint(
        _append_debug_reason(
            "The last Notion sync failed. Reconnect the integration or try again.",
            raw_message,
        ),
        identifier_hint,
    )


def _extract_identifier_hint(raw_message: str) -> str | None:
    marker = "Extracted Notion identifiers:"
    if marker not in raw_message:
        return None
    _, _, tail = raw_message.partition(marker)
    normalized = tail.strip()
    return normalized or None


def _append_identifier_hint(message: str, identifier_hint: str | None) -> str:
    if not identifier_hint:
        return message
    return f"{message} Extracted ID: {identifier_hint}"


def _append_debug_reason(message: str, raw_message: str) -> str:
    detail = _sanitize_debug_reason(raw_message)
    if detail is None:
        return message
    return f"{message} Reason: {detail}"


def _sanitize_debug_reason(raw_message: str) -> str | None:
    normalized = " ".join(raw_message.strip().split())
    if not normalized:
        return None

    lowered = normalized.lower()
    if any(
        keyword in lowered
        for keyword in (
            "token",
            "secret",
            "authorization",
            "bearer",
            "password",
            "service_role",
            "api key",
            "api_key",
        )
    ):
        return None

    return normalized[:240]


def _store_sync_failure_metadata(
    repository: NotionConnectionRepository,
    *,
    connection_id: str | None,
    public_message: str,
) -> None:
    if not connection_id:
        return
    try:
        repository.mark_failed_if_connected(
            connection_id,
            public_error_message=public_message,
        )
    except Exception:
        logger.exception(
            "Failed to persist Notion sync failure metadata for connection_id=%s",
            connection_id,
        )
