import json
from datetime import date, datetime
from enum import StrEnum
from typing import Any
from uuid import UUID

from pydantic import BaseModel

from app.schemas.reminder import ReminderResponse, ReminderStatus
from app.schemas.task import (
    SubtaskResponse,
    SubtaskStatus,
    TaskResponse,
    TaskSource,
    TaskStatus,
)


_TASK_COLUMNS = (
    "id, user_id, profile_id, candidate_id, raw_input_id, mediator_run_id, title, "
    "description, status, priority, due_at, estimated_minutes, energy_required, "
    "difficulty, next_action, source, metadata, created_at, updated_at, completed_at"
)
_SUBTASK_COLUMNS = (
    "id, task_id, user_id, candidate_subtask_id, title, order_index, "
    "estimated_minutes, status, is_next_action, energy_required, created_at, "
    "updated_at, completed_at"
)
_REMINDER_COLUMNS = (
    "id, user_id, task_id, candidate_reminder_id, remind_at, message, type, "
    "status, escalation_level, created_at, updated_at, sent_at"
)


class SupabaseTaskRepository:
    def __init__(self, client: Any) -> None:
        self._client = client

    def get(self, *, user_id: str, task_id: str) -> TaskResponse:
        response = (
            self._client.table("tasks")
            .select(_TASK_COLUMNS)
            .eq("user_id", user_id)
            .eq("id", task_id)
            .limit(1)
            .execute()
        )
        task_row = _single_row(response, "Task was not found for the given user_id.")
        return _map_task_response(
            task_row,
            subtask_rows=self._list_subtasks(user_id=user_id, task_id=task_row["id"]),
            reminder_rows=self._list_reminders(user_id=user_id, task_id=task_row["id"]),
        )

    def get_by_candidate_id(self, *, user_id: str, candidate_id: str) -> TaskResponse | None:
        response = (
            self._client.table("tasks")
            .select(_TASK_COLUMNS)
            .eq("user_id", user_id)
            .eq("candidate_id", candidate_id)
            .limit(1)
            .execute()
        )
        rows = response.data or []
        if not rows:
            return None
        task_row = rows[0]
        return _map_task_response(
            task_row,
            subtask_rows=self._list_subtasks(user_id=user_id, task_id=task_row["id"]),
            reminder_rows=self._list_reminders(user_id=user_id, task_id=task_row["id"]),
        )

    def list_for_pattern_analysis(
        self,
        *,
        user_id: str,
        limit: int = 50,
    ) -> list[TaskResponse]:
        response = (
            self._client.table("tasks")
            .select(_TASK_COLUMNS)
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
        )
        task_rows = response.data or []
        if not task_rows:
            return []

        task_ids = [row["id"] for row in task_rows if row.get("id")]
        subtasks_by_task_id = self._list_subtasks_for_tasks(
            user_id=user_id,
            task_ids=task_ids,
        )
        return [
            _map_task_response(
                row,
                subtask_rows=subtasks_by_task_id.get(row["id"], []),
                reminder_rows=[],
            )
            for row in task_rows
        ]

    def create_task(self, payload: dict[str, Any]) -> TaskResponse:
        response = (
            self._client.table("tasks")
            .insert(_json_object(payload))
            .select(_TASK_COLUMNS)
            .execute()
        )
        task_row = _single_row(response, "Task creation did not return a row.")
        return _map_task_response(task_row, subtask_rows=[], reminder_rows=[])

    def create_subtasks(
        self,
        *,
        user_id: str,
        task_id: str,
        payloads: list[dict[str, Any]],
    ) -> list[SubtaskResponse]:
        if not payloads:
            return []
        normalized_payloads = [
            _json_object({"user_id": user_id, "task_id": task_id, **payload})
            for payload in payloads
        ]
        response = (
            self._client.table("subtasks")
            .insert(normalized_payloads)
            .select(_SUBTASK_COLUMNS)
            .execute()
        )
        rows = sorted(response.data or [], key=lambda row: row.get("order_index") or 0)
        return [_map_subtask_response(row) for row in rows]

    def create_reminders(
        self,
        *,
        user_id: str,
        task_id: str,
        payloads: list[dict[str, Any]],
    ) -> list[ReminderResponse]:
        if not payloads:
            return []
        normalized_payloads = [
            _json_object({"user_id": user_id, "task_id": task_id, **payload})
            for payload in payloads
        ]
        response = (
            self._client.table("reminders")
            .insert(normalized_payloads)
            .select(_REMINDER_COLUMNS)
            .execute()
        )
        return [_map_reminder_response(row) for row in _sort_reminder_rows(response.data or [])]

    def mark_completed(
        self,
        *,
        user_id: str,
        task_id: str,
        completed_at: datetime,
    ) -> TaskResponse:
        payload = {
            "status": TaskStatus.DONE.value,
            "completed_at": completed_at.isoformat(),
        }
        response = (
            self._client.table("tasks")
            .update(payload)
            .eq("user_id", user_id)
            .eq("id", task_id)
            .execute()
        )
        _ensure_mutation_succeeded(
            response,
            "Task completion update did not affect any rows.",
        )
        self._mark_subtasks_completed(
            user_id=user_id,
            task_id=task_id,
            completed_at=completed_at,
        )
        return self.get(user_id=user_id, task_id=task_id)

    def _mark_subtasks_completed(
        self,
        *,
        user_id: str,
        task_id: str,
        completed_at: datetime,
    ) -> None:
        payload = {
            "status": SubtaskStatus.DONE.value,
            "completed_at": completed_at.isoformat(),
        }
        (
            self._client.table("subtasks")
            .update(payload)
            .eq("user_id", user_id)
            .eq("task_id", task_id)
            .in_(
                "status",
                [
                    SubtaskStatus.TODO.value,
                    SubtaskStatus.DOING.value,
                    SubtaskStatus.SKIPPED.value,
                ],
            )
            .execute()
        )

    def _list_subtasks(self, *, user_id: str, task_id: str) -> list[dict[str, Any]]:
        response = (
            self._client.table("subtasks")
            .select(_SUBTASK_COLUMNS)
            .eq("user_id", user_id)
            .eq("task_id", task_id)
            .order("order_index")
            .execute()
        )
        return response.data or []

    def _list_subtasks_for_tasks(
        self,
        *,
        user_id: str,
        task_ids: list[str],
    ) -> dict[str, list[dict[str, Any]]]:
        if not task_ids:
            return {}

        response = (
            self._client.table("subtasks")
            .select(_SUBTASK_COLUMNS)
            .eq("user_id", user_id)
            .in_("task_id", task_ids)
            .order("order_index")
            .execute()
        )
        rows = response.data or []
        grouped: dict[str, list[dict[str, Any]]] = {}
        for row in rows:
            task_id = row.get("task_id")
            if not task_id:
                continue
            grouped.setdefault(task_id, []).append(row)
        return grouped

    def _list_reminders(self, *, user_id: str, task_id: str) -> list[dict[str, Any]]:
        response = (
            self._client.table("reminders")
            .select(_REMINDER_COLUMNS)
            .eq("user_id", user_id)
            .eq("task_id", task_id)
            .order("remind_at")
            .execute()
        )
        return _sort_reminder_rows(response.data or [])


def _map_task_response(
    row: dict[str, Any],
    *,
    subtask_rows: list[dict[str, Any]],
    reminder_rows: list[dict[str, Any]],
) -> TaskResponse:
    return TaskResponse(
        id=row["id"],
        user_id=row["user_id"],
        candidate_id=row.get("candidate_id"),
        raw_input_id=row.get("raw_input_id"),
        mediator_run_id=row.get("mediator_run_id"),
        title=row["title"],
        description=row.get("description"),
        status=row.get("status") or TaskStatus.TODO.value,
        priority=row.get("priority"),
        due_at=row.get("due_at"),
        estimated_minutes=row.get("estimated_minutes"),
        energy_required=row.get("energy_required"),
        difficulty=row.get("difficulty"),
        next_action=row.get("next_action"),
        source=row.get("source") or TaskSource.AI.value,
        metadata=_json_object(row.get("metadata") or {}),
        subtasks=[_map_subtask_response(item) for item in subtask_rows],
        reminders=[_map_reminder_response(item) for item in reminder_rows],
        created_at=row.get("created_at"),
        updated_at=row.get("updated_at"),
        completed_at=row.get("completed_at"),
    )


def _map_subtask_response(row: dict[str, Any]) -> SubtaskResponse:
    return SubtaskResponse(
        id=row["id"],
        task_id=row["task_id"],
        user_id=row["user_id"],
        candidate_subtask_id=row.get("candidate_subtask_id"),
        title=row["title"],
        order_index=row["order_index"],
        estimated_minutes=row.get("estimated_minutes"),
        status=row.get("status") or SubtaskStatus.TODO.value,
        is_next_action=row.get("is_next_action") or False,
        energy_required=row.get("energy_required"),
        created_at=row.get("created_at"),
        updated_at=row.get("updated_at"),
        completed_at=row.get("completed_at"),
    )


def _map_reminder_response(row: dict[str, Any]) -> ReminderResponse:
    return ReminderResponse(
        id=row["id"],
        user_id=row["user_id"],
        task_id=row["task_id"],
        candidate_reminder_id=row.get("candidate_reminder_id"),
        remind_at=row["remind_at"],
        message=row["message"],
        type=row.get("type") or "start",
        status=row.get("status") or ReminderStatus.SCHEDULED.value,
        escalation_level=row.get("escalation_level") or 0,
        created_at=row.get("created_at"),
        updated_at=row.get("updated_at"),
        sent_at=row.get("sent_at"),
    )


def _json_object(value: Any) -> dict[str, Any]:
    normalized = json.loads(
        json.dumps(
            value,
            ensure_ascii=False,
            default=_json_default,
        )
    )
    if not isinstance(normalized, dict):
        return {"value": normalized}
    return normalized


def _json_default(value: Any) -> Any:
    if isinstance(value, BaseModel):
        return value.model_dump(mode="json")
    if isinstance(value, datetime | date):
        return value.isoformat()
    if isinstance(value, UUID):
        return str(value)
    if isinstance(value, StrEnum):
        return value.value
    return str(value)


def _single_row(response: Any, message: str) -> dict[str, Any]:
    rows = response.data or []
    if not rows:
        raise ValueError(message)
    return rows[0]


def _sort_reminder_rows(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return sorted(rows, key=lambda row: row.get("remind_at") or "")


def _ensure_mutation_succeeded(response: Any, message: str) -> None:
    if getattr(response, "data", None) is None:
        return
    if isinstance(response.data, list) and response.data == []:
        raise ValueError(message)
