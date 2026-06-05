from datetime import datetime
from dataclasses import dataclass
from typing import Any

from app.repositories.base import QuestRecord, QuestRepository
from app.schemas.quest_generation import QuestCandidateResponse
from app.schemas.quest import QuestItemResponse


@dataclass
class NotionQuestUpsertSummary:
    imported_count: int = 0
    updated_count: int = 0
    skipped_count: int = 0
    stale_count: int = 0


class SupabaseQuestRepository(QuestRepository):
    def __init__(self, client: Any) -> None:
        self._client = client

    def list_quests(self, user_id: str) -> list[QuestItemResponse]:
        response = (
            self._client.table("quests")
            .select(
                "id, client_quest_id, source, title, exp, difficulty, category, "
                "elapsed_seconds, default_duration_seconds, due_at",
            )
            .eq("user_id", user_id)
            .eq("status", "active")
            .order("created_at", desc=True)
            .execute()
        )
        completed_quest_ids = _completed_quest_ids(self._client, user_id)
        rows = [
            row
            for row in _deduplicate_notion_rows(response.data or [])
            if str(row.get("id") or "") not in completed_quest_ids
            and str(row.get("client_quest_id") or "") not in completed_quest_ids
        ]
        return [_map_quest_row(row) for row in rows]

    def create_quest(
        self,
        user_id: str,
        quest: QuestItemResponse,
    ) -> QuestItemResponse:
        profile_id = _get_profile_id(self._client, user_id)
        payload = {
            "user_id": user_id,
            "profile_id": profile_id,
            "client_quest_id": quest.id,
            "title": quest.title,
            "exp": quest.exp,
            "difficulty": quest.difficulty.value,
            "category": quest.category.value,
            "elapsed_seconds": quest.elapsedSeconds,
            "default_duration_seconds": quest.defaultDurationSeconds,
            "due_at": _encode_datetime(quest.dueAt),
            "status": "active",
            "source": "manual",
        }
        response = self._client.table("quests").insert(payload).execute()
        created = _single_row(response)
        return _map_quest_row(created)

    def update_quest(
        self,
        user_id: str,
        quest_id: str,
        quest: QuestItemResponse,
    ) -> QuestItemResponse:
        payload = {
            "title": quest.title,
            "exp": quest.exp,
            "difficulty": quest.difficulty.value,
            "category": quest.category.value,
            "elapsed_seconds": quest.elapsedSeconds,
            "default_duration_seconds": quest.defaultDurationSeconds,
            "due_at": _encode_datetime(quest.dueAt),
        }
        existing = self.get_active_quest(user_id, quest_id)
        response = (
            self._client.table("quests")
            .update(payload)
            .eq("user_id", user_id)
            .eq("id", quest_id)
            .eq("status", "active")
            .execute()
        )
        _ensure_mutation_succeeded(response, "Quest update did not affect any rows.")
        refreshed = self.get_active_quest(user_id, quest_id)
        return QuestItemResponse(
            id=refreshed.id,
            title=refreshed.title,
            exp=refreshed.exp,
            difficulty=refreshed.difficulty,
            category=refreshed.category,
            elapsedSeconds=refreshed.elapsed_seconds,
            defaultDurationSeconds=refreshed.default_duration_seconds,
            dueAt=refreshed.due_at,
        )

    def delete_quest(self, user_id: str, quest_id: str) -> None:
        _get_quest_for_delete(self._client, user_id, quest_id)
        response = (
            self._client.table("quests")
            .delete()
            .eq("user_id", user_id)
            .eq("id", quest_id)
            .execute()
        )
        _ensure_mutation_succeeded(response, "Quest delete did not affect any rows.")

    def get_active_quest(self, user_id: str, quest_id: str) -> QuestRecord:
        response = (
            self._client.table("quests")
            .select(
                "id, profile_id, title, exp, difficulty, category, "
                "elapsed_seconds, default_duration_seconds, due_at",
            )
            .eq("user_id", user_id)
            .eq("id", quest_id)
            .eq("status", "active")
            .limit(1)
            .execute()
        )
        return _map_quest_record(_single_row(response))

    def mark_completed(self, user_id: str, quest_id: str) -> None:
        self.get_active_quest(user_id, quest_id)
        response = (
            self._client.table("quests")
            .update({"status": "completed"})
            .eq("user_id", user_id)
            .eq("id", quest_id)
            .eq("status", "active")
            .execute()
        )
        _ensure_mutation_succeeded(response, "Quest completion update did not affect any rows.")

    def upsert_notion_quests(
        self,
        *,
        user_id: str,
        profile_id: str,
        source_reference: str,
        quests: list[QuestCandidateResponse],
        pages: list[dict[str, Any]],
    ) -> NotionQuestUpsertSummary:
        # Intentionally do not reconcile against legacy Notion rows that were
        # imported before external_source/external_id existed. Those rows can
        # be title-based and ambiguous, so auto-merging would risk overwriting
        # the wrong quest. New Notion sync integrity is anchored only on the
        # stable Notion page identity encoded into client_quest_id. This keeps
        # sync working even when external identity indexes are not present yet.
        summary = NotionQuestUpsertSummary()
        for quest in quests:
            external_source = _normalize_external_source(quest.external_source)
            external_id = _require_notion_external_id(
                external_source=external_source,
                external_id=quest.external_id,
            )
            client_quest_id = f"notion:{external_id}"
            existing_row = _load_existing_notion_row(
                self._client,
                user_id=user_id,
                external_source=external_source,
                external_id=external_id,
                client_quest_id=client_quest_id,
            )
            payload = {
                "user_id": user_id,
                "profile_id": profile_id,
                "client_quest_id": client_quest_id,
                "title": quest.title,
                "exp": quest.exp,
                "difficulty": quest.difficulty.value,
                "category": quest.category.value,
                "elapsed_seconds": 0,
                "default_duration_seconds": quest.defaultDurationSeconds,
                "due_at": _encode_datetime(quest.due_at),
                "status": "active",
                "source": "notion",
                "source_reference": source_reference,
            }
            existing_external_updated_at = (
                existing_row.get("external_updated_at")
                if existing_row is not None
                else None
            )
            if not _should_apply_notion_update(
                existing_external_updated_at=existing_external_updated_at,
                incoming_external_updated_at=quest.external_updated_at,
            ):
                summary.skipped_count += 1
                summary.stale_count += 1
                continue

            upsert_payload = {
                **payload,
                "external_source": external_source,
                "external_id": external_id,
                "external_url": quest.external_url,
                "external_updated_at": _encode_datetime(quest.external_updated_at),
                "deleted_at": None,
            }
            _write_notion_quest(
                self._client,
                user_id=user_id,
                existing_row=existing_row,
                payload=payload,
                upsert_payload=upsert_payload,
            )

            if existing_row is None:
                summary.imported_count += 1
            else:
                summary.updated_count += 1
        return summary


def _completed_quest_ids(client: Any, user_id: str) -> set[str]:
    try:
        response = (
            client.table("completed_quests")
            .select("quest_id, client_quest_id")
            .eq("user_id", user_id)
            .execute()
        )
    except Exception:
        return set()

    completed_ids: set[str] = set()
    for row in response.data or []:
        for key in ("quest_id", "client_quest_id"):
            value = row.get(key)
            if value is not None and str(value).strip():
                completed_ids.add(str(value))
    return completed_ids


def _get_profile_id(client: Any, user_id: str) -> str:
    response = (
        client.table("users_profile")
        .select("id")
        .eq("user_id", user_id)
        .limit(1)
        .execute()
    )
    rows = response.data or []
    if not rows:
        raise ValueError("Profile was not found for the given user_id.")
    row = rows[0]
    return row["id"]


def _single_row(response: Any) -> dict[str, Any]:
    rows = response.data or []
    if not rows:
        raise ValueError("Quest was not found for the given user_id.")
    return rows[0]


def _get_quest_for_delete(client: Any, user_id: str, quest_id: str) -> dict[str, Any]:
    response = (
        client.table("quests")
        .select("id")
        .eq("user_id", user_id)
        .eq("id", quest_id)
        .limit(1)
        .execute()
    )
    return _single_row(response)


def _ensure_mutation_succeeded(response: Any, message: str) -> None:
    if getattr(response, "data", None) is None:
        return
    if isinstance(response.data, list) and response.data == []:
        raise ValueError(message)


def _deduplicate_notion_rows(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen_notion_ids: set[str] = set()
    deduplicated: list[dict[str, Any]] = []
    for row in rows:
        client_quest_id = row.get("client_quest_id")
        source = row.get("source")
        is_notion_row = (
            isinstance(source, str)
            and source.strip().lower() == "notion"
            and isinstance(client_quest_id, str)
            and client_quest_id.strip()
        )
        if is_notion_row:
            normalized_id = client_quest_id.strip()
            if normalized_id in seen_notion_ids:
                continue
            seen_notion_ids.add(normalized_id)
        deduplicated.append(row)
    return deduplicated


def _write_notion_quest(
    client: Any,
    *,
    user_id: str,
    existing_row: dict[str, Any] | None,
    payload: dict[str, Any],
    upsert_payload: dict[str, Any],
) -> None:
    if existing_row is not None:
        _update_existing_notion_quest(
            client,
            user_id=user_id,
            quest_id=existing_row["id"],
            payload=payload,
            upsert_payload=upsert_payload,
        )
        return

    try:
        client.table("quests").upsert(
            upsert_payload,
            on_conflict="user_id,client_quest_id",
        ).execute()
    except Exception as error:
        if not _is_legacy_notion_schema_error(error):
            raise
        client.table("quests").upsert(
            payload,
            on_conflict="user_id,client_quest_id",
        ).execute()


def _update_existing_notion_quest(
    client: Any,
    *,
    user_id: str,
    quest_id: str,
    payload: dict[str, Any],
    upsert_payload: dict[str, Any],
) -> None:
    try:
        response = (
            client.table("quests")
            .update(upsert_payload)
            .eq("user_id", user_id)
            .eq("id", quest_id)
            .execute()
        )
    except Exception as error:
        if not _is_legacy_notion_schema_error(error):
            raise
        response = (
            client.table("quests")
            .update(payload)
            .eq("user_id", user_id)
            .eq("id", quest_id)
            .execute()
        )
    _ensure_mutation_succeeded(response, "Notion quest update did not affect any rows.")


def _find_existing_notion_quest(
    client: Any,
    *,
    user_id: str,
    external_source: str,
    external_id: str,
) -> dict[str, Any] | None:
    response = (
        client.table("quests")
        .select("id, external_updated_at")
        .eq("user_id", user_id)
        .eq("external_source", external_source)
        .eq("external_id", external_id)
        .limit(1)
        .execute()
    )
    rows = response.data or []
    return rows[0] if rows else None


def _find_existing_legacy_notion_quest(
    client: Any,
    *,
    user_id: str,
    client_quest_id: str,
) -> dict[str, Any] | None:
    response = (
        client.table("quests")
        .select("id, external_updated_at")
        .eq("user_id", user_id)
        .eq("client_quest_id", client_quest_id)
        .limit(1)
        .execute()
    )
    rows = response.data or []
    return rows[0] if rows else None


def _load_existing_notion_row(
    client: Any,
    *,
    user_id: str,
    external_source: str,
    external_id: str,
    client_quest_id: str,
) -> dict[str, Any] | None:
    try:
        existing = _find_existing_notion_quest(
            client,
            user_id=user_id,
            external_source=external_source,
            external_id=external_id,
        )
    except Exception as error:
        if not _is_legacy_notion_schema_error(error):
            raise
        return _find_existing_legacy_notion_quest(
            client,
            user_id=user_id,
            client_quest_id=client_quest_id,
        )

    if existing is not None:
        return existing
    return _find_existing_legacy_notion_quest(
        client,
        user_id=user_id,
        client_quest_id=client_quest_id,
    )


def _should_apply_notion_update(
    *,
    existing_external_updated_at: object,
    incoming_external_updated_at: object,
) -> bool:
    incoming_timestamp = _coerce_datetime(incoming_external_updated_at)
    existing_timestamp = _coerce_datetime(existing_external_updated_at)

    if existing_timestamp is None:
        return True
    if incoming_timestamp is None:
        return False
    return incoming_timestamp >= existing_timestamp


def _coerce_datetime(value: object) -> datetime | None:
    if isinstance(value, datetime):
        return value
    if not isinstance(value, str):
        return None

    normalized = value.strip()
    if not normalized:
        return None
    if normalized.endswith("Z"):
        normalized = f"{normalized[:-1]}+00:00"
    try:
        return datetime.fromisoformat(normalized)
    except ValueError:
        return None


def _encode_datetime(value: datetime | None) -> str | None:
    if value is None:
        return None
    return value.isoformat()


def _is_legacy_notion_schema_error(error: Exception) -> bool:
    message = str(error).lower()
    return any(
        keyword in message
        for keyword in (
            "external_source",
            "external_id",
            "external_url",
            "external_updated_at",
            "deleted_at",
        )
    )


def _normalize_external_source(external_source: str | None) -> str:
    normalized = (external_source or "").strip().lower()
    return normalized or "notion"


def _require_notion_external_id(
    *,
    external_source: str,
    external_id: str | None,
) -> str:
    normalized_external_id = external_id.strip() if isinstance(external_id, str) else ""
    if external_source == "notion" and not normalized_external_id:
        raise ValueError(
            "Notion quest upsert requires a non-empty external_id (page.id).",
        )
    return normalized_external_id


def _map_quest_row(row: dict[str, Any]) -> QuestItemResponse:
    return QuestItemResponse(
        id=row["id"],
        title=row["title"],
        exp=row["exp"],
        difficulty=row["difficulty"],
        category=row["category"],
        elapsedSeconds=row["elapsed_seconds"],
        defaultDurationSeconds=row["default_duration_seconds"],
        dueAt=_coerce_datetime(row.get("due_at")),
    )


def _map_quest_record(row: dict[str, Any]) -> QuestRecord:
    return QuestRecord(
        id=row["id"],
        profile_id=row["profile_id"],
        title=row["title"],
        exp=row["exp"],
        difficulty=row["difficulty"],
        category=row["category"],
        elapsed_seconds=row["elapsed_seconds"],
        default_duration_seconds=row["default_duration_seconds"],
        due_at=_coerce_datetime(row.get("due_at")),
    )


