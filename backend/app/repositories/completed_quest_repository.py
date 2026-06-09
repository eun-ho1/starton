from datetime import datetime
from typing import Any
from uuid import UUID

from app.repositories.base import CompletedQuestRepository, QuestRecord
from app.schemas.quest import CompletedQuestRecordSchema


class SupabaseCompletedQuestRepository(CompletedQuestRepository):
    def __init__(self, client: Any) -> None:
        self._client = client

    def create_completed_quest(
        self,
        user_id: str,
        quest: QuestRecord,
        earned_exp: int,
        completed_at: datetime,
        elapsed_seconds: int,
        proof_image_path: str | None = None,
    ) -> tuple[str, CompletedQuestRecordSchema]:
        return self._create_completed_record(
            user_id=user_id,
            record=quest,
            earned_exp=earned_exp,
            completed_at=completed_at,
            elapsed_seconds=elapsed_seconds,
            proof_image_path=proof_image_path,
            quest_id=_optional_uuid_string(quest.id),
            task_id=None,
        )

    def create_completed_task(
        self,
        user_id: str,
        task: QuestRecord,
        earned_exp: int,
        completed_at: datetime,
        elapsed_seconds: int,
        proof_image_path: str | None = None,
    ) -> tuple[str, CompletedQuestRecordSchema]:
        return self._create_completed_record(
            user_id=user_id,
            record=task,
            earned_exp=earned_exp,
            completed_at=completed_at,
            elapsed_seconds=elapsed_seconds,
            proof_image_path=proof_image_path,
            quest_id=None,
            task_id=task.id,
        )

    def _create_completed_record(
        self,
        *,
        user_id: str,
        record: QuestRecord,
        earned_exp: int,
        completed_at: datetime,
        elapsed_seconds: int,
        proof_image_path: str | None,
        quest_id: str | None,
        task_id: str | None,
    ) -> tuple[str, CompletedQuestRecordSchema]:
        payload = {
            "user_id": user_id,
            "profile_id": record.profile_id,
            "quest_id": quest_id,
            "client_quest_id": record.id,
            "title": record.title,
            "difficulty": record.difficulty,
            "category": record.category,
            "earned_exp": earned_exp,
            "completed_at": completed_at.isoformat(),
            "elapsed_seconds": elapsed_seconds,
            "proof_image_path": proof_image_path,
            "completion_source": "timer" if elapsed_seconds > 0 else "manual",
        }
        if task_id is not None:
            payload["task_id"] = task_id

        completed_response = (
            self._client.table("completed_quests").insert(payload).execute()
        )
        created_row = _single_row(completed_response)
        return created_row["id"], _map_completed_row(created_row)

    def create_recent_activity(
        self,
        user_id: str,
        profile_id: str,
        completed_quest_id: str,
        activity_date: datetime,
        subtitle: str,
        exp: int,
    ) -> None:
        payload = {
            "user_id": user_id,
            "profile_id": profile_id,
            "completed_quest_id": completed_quest_id,
            "activity_date": activity_date.date().isoformat(),
            "subtitle": subtitle,
            "exp": exp,
            "activity_type": "quest_completed",
        }
        self._client.table("recent_activities").insert(payload).execute()

    def get_latest_completed_record(
        self,
        user_id: str,
        *,
        quest_id: str | None = None,
        task_id: str | None = None,
    ) -> dict[str, Any]:
        candidates: list[dict[str, Any]] = []

        client_id = task_id or quest_id
        if client_id:
            candidates.extend(
                self._list_completion_rows(
                    user_id=user_id,
                    column="client_quest_id",
                    value=client_id,
                )
            )

        normalized_task_id = _optional_uuid_string(task_id)
        if normalized_task_id is not None:
            candidates.extend(
                self._list_completion_rows(
                    user_id=user_id,
                    column="task_id",
                    value=normalized_task_id,
                )
            )

        normalized_quest_id = _optional_uuid_string(quest_id)
        if normalized_quest_id is not None:
            candidates.extend(
                self._list_completion_rows(
                    user_id=user_id,
                    column="quest_id",
                    value=normalized_quest_id,
                )
            )

        unique_rows = {row["id"]: row for row in candidates if row.get("id")}
        rows = sorted(
            unique_rows.values(),
            key=lambda row: str(row.get("completed_at") or ""),
            reverse=True,
        )
        if not rows:
            raise ValueError("Completed quest record was not found for the given user_id.")
        return rows[0]

    def delete_completed_record(
        self,
        user_id: str,
        completed_quest_id: str,
    ) -> None:
        response = (
            self._client.table("completed_quests")
            .delete()
            .eq("user_id", user_id)
            .eq("id", completed_quest_id)
            .execute()
        )
        _ensure_mutation_succeeded(
            response,
            "Completed quest delete did not affect any rows.",
        )

    def delete_recent_activity_for_completed_quest(
        self,
        user_id: str,
        completed_quest_id: str,
    ) -> None:
        (
            self._client.table("recent_activities")
            .delete()
            .eq("user_id", user_id)
            .eq("completed_quest_id", completed_quest_id)
            .execute()
        )

    def _list_completion_rows(
        self,
        *,
        user_id: str,
        column: str,
        value: str,
    ) -> list[dict[str, Any]]:
        response = (
            self._client.table("completed_quests")
            .select("*")
            .eq("user_id", user_id)
            .eq(column, value)
            .order("completed_at", desc=True)
            .limit(3)
            .execute()
        )
        return response.data or []


def _single_row(response: Any) -> dict[str, Any]:
    rows = response.data or []
    if not rows:
        raise ValueError("Requested resource was not found for the given user_id.")
    return rows[0]


def _ensure_mutation_succeeded(response: Any, message: str) -> None:
    if getattr(response, "data", None) is None:
        return
    if isinstance(response.data, list) and response.data == []:
        raise ValueError(message)


def _map_completed_row(row: dict[str, Any]) -> CompletedQuestRecordSchema:
    return CompletedQuestRecordSchema(
        questId=(
            row.get("client_quest_id")
            or row.get("quest_id")
            or row.get("task_id")
            or ""
        ),
        title=row["title"],
        difficulty=row["difficulty"],
        category=row["category"],
        earnedExp=row["earned_exp"],
        completedAt=row["completed_at"],
        elapsedSeconds=row["elapsed_seconds"],
        proofImagePath=row.get("proof_image_path"),
    )


def _optional_uuid_string(value: str | None) -> str | None:
    if value is None:
        return None
    try:
        return str(UUID(str(value)))
    except (TypeError, ValueError):
        return None
