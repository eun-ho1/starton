from dataclasses import dataclass
from datetime import date, datetime
from enum import StrEnum
from typing import Any
from uuid import UUID

from pydantic import BaseModel

from app.schemas.task import (
    SubtaskStatus,
    TaskCommitResult,
    TaskResponse,
    TaskSource,
    TaskStatus,
)
from app.schemas.task_candidate import (
    CandidateReminderResponse,
    CandidateSubtaskResponse,
    TaskCandidateResponse,
    TaskCandidateStatus,
)


_COMMITTABLE_STATUSES = {
    TaskCandidateStatus.DRAFT.value,
    TaskCandidateStatus.ACCEPTED.value,
    TaskCandidateStatus.EDITED.value,
}
_EDITABLE_TASK_FIELDS = {
    "title",
    "description",
    "due_at",
    "priority",
    "estimated_minutes",
    "energy_required",
    "difficulty",
    "next_action",
}
_ALLOWED_SOURCES = {source.value for source in TaskSource}


@dataclass(frozen=True)
class TaskCommitError(Exception):
    code: str
    message: str

    def __str__(self) -> str:
        return self.message


class TaskCommitService:
    def __init__(
        self,
        *,
        task_candidate_repository: Any,
        task_repository: Any,
        raw_input_repository: Any | None = None,
    ) -> None:
        self._task_candidate_repository = task_candidate_repository
        self._task_repository = task_repository
        self._raw_input_repository = raw_input_repository

    def commit_candidate(
        self,
        *,
        user_id: str,
        candidate_id: str,
        accepted: bool = True,
        edited_fields: dict[str, Any] | None = None,
        selected_subtask_ids: list[str] | list[UUID] | None = None,
        selected_reminder_ids: list[str] | list[UUID] | None = None,
        profile_id: str | None = None,
    ) -> TaskCommitResult:
        if not accepted:
            raise TaskCommitError(
                "invalid_task_commit_request",
                "Only accepted candidates can be committed in this flow.",
            )

        candidate = self._get_candidate(user_id=user_id, candidate_id=candidate_id)
        self._ensure_candidate_is_committable(candidate)
        if self._task_repository.get_by_candidate_id(
            user_id=user_id,
            candidate_id=str(candidate.id),
        ):
            raise TaskCommitError(
                "candidate_already_committed",
                "This task candidate has already been committed.",
            )

        edits = _validated_edited_fields(edited_fields or {})
        selected_subtasks = _select_subtasks(candidate, selected_subtask_ids)
        selected_reminders = _select_reminders(candidate, selected_reminder_ids)

        task = self._create_task(
            user_id=user_id,
            candidate=candidate,
            profile_id=profile_id,
            edited_fields=edits,
            selected_subtask_ids=[str(item.id) for item in selected_subtasks],
            selected_reminder_ids=[str(item.id) for item in selected_reminders],
        )
        subtasks = self._task_repository.create_subtasks(
            user_id=user_id,
            task_id=str(task.id),
            payloads=[_subtask_payload(item) for item in selected_subtasks],
        )
        reminders = self._task_repository.create_reminders(
            user_id=user_id,
            task_id=str(task.id),
            payloads=[_reminder_payload(item) for item in selected_reminders],
        )

        committed_task = task.model_copy(
            update={
                "subtasks": subtasks,
                "reminders": reminders,
            }
        )
        self._task_candidate_repository.mark_committed(
            user_id=user_id,
            candidate_id=str(candidate.id),
        )

        return TaskCommitResult(candidate_id=candidate.id, task=committed_task)

    def _get_candidate(self, *, user_id: str, candidate_id: str) -> TaskCandidateResponse:
        try:
            return self._task_candidate_repository.get(
                user_id=user_id,
                candidate_id=candidate_id,
            )
        except ValueError as error:
            raise TaskCommitError(
                "candidate_not_found",
                "Task candidate was not found.",
            ) from error

    def _ensure_candidate_is_committable(self, candidate: TaskCandidateResponse) -> None:
        status = _enum_value(candidate.status)
        if status == TaskCandidateStatus.COMMITTED.value:
            raise TaskCommitError(
                "candidate_already_committed",
                "This task candidate has already been committed.",
            )
        if status not in _COMMITTABLE_STATUSES:
            raise TaskCommitError(
                "candidate_not_committable",
                f"Task candidate with status '{status}' cannot be committed.",
            )

    def _create_task(
        self,
        *,
        user_id: str,
        candidate: TaskCandidateResponse,
        profile_id: str | None,
        edited_fields: dict[str, Any],
        selected_subtask_ids: list[str],
        selected_reminder_ids: list[str],
    ) -> TaskResponse:
        client_metadata = _client_metadata_from_candidate(candidate)
        raw_input_repository = self._raw_input_repository
        if raw_input_repository is not None:
            try:
                raw_input = raw_input_repository.get(
                    user_id=user_id,
                    raw_input_id=str(candidate.raw_input_id),
                )
                client_metadata.update(raw_input.client_metadata)
            except Exception:
                pass

        payload = {
            "user_id": user_id,
            "profile_id": profile_id,
            "candidate_id": str(candidate.id),
            "raw_input_id": str(candidate.raw_input_id),
            "mediator_run_id": str(candidate.mediator_run_id)
            if candidate.mediator_run_id
            else None,
            "title": candidate.title,
            "description": candidate.description,
            "status": TaskStatus.TODO.value,
            "priority": _enum_value(candidate.priority),
            "due_at": _datetime_value(candidate.due_at),
            "estimated_minutes": candidate.estimated_minutes,
            "energy_required": _enum_value(candidate.energy_required),
            "difficulty": _enum_value(candidate.difficulty),
            "next_action": candidate.next_action,
            "source": _candidate_source(candidate),
            "metadata": _json_safe(
                _task_metadata_for_commit(
                    client_metadata=client_metadata,
                    edited_fields=edited_fields,
                    selected_subtask_ids=selected_subtask_ids,
                    selected_reminder_ids=selected_reminder_ids,
                )
            ),
        }
        payload.update(_json_safe(edited_fields))
        if not str(payload.get("title") or "").strip():
            raise TaskCommitError(
                "invalid_edited_fields",
                "Task title must not be empty.",
            )
        return self._task_repository.create_task(payload)


def _client_metadata_from_candidate(candidate: TaskCandidateResponse) -> dict[str, Any]:
    metadata: dict[str, Any] = {}
    candidate_metadata = candidate.model_payload.get("client_metadata")
    if isinstance(candidate_metadata, dict):
        metadata.update(candidate_metadata)

    raw_input = candidate.model_payload.get("raw_input")
    if isinstance(raw_input, dict):
        raw_metadata = raw_input.get("client_metadata")
        if isinstance(raw_metadata, dict):
            metadata.update(raw_metadata)

    return metadata


def _task_metadata_for_commit(
    *,
    client_metadata: dict[str, Any],
    edited_fields: dict[str, Any],
    selected_subtask_ids: list[str],
    selected_reminder_ids: list[str],
) -> dict[str, Any]:
    metadata: dict[str, Any] = {
        "committed_from": "task_candidate",
        "client_metadata": _json_safe(client_metadata),
        "edited_fields": _json_safe(edited_fields),
        "selected_subtask_ids": selected_subtask_ids,
        "selected_reminder_ids": selected_reminder_ids,
    }
    for key in (
        "category",
        "exp",
        "default_duration_seconds",
        "defaultDurationSeconds",
        "elapsed_seconds",
        "elapsedSeconds",
        "subtask_generation_prompt",
    ):
        value = client_metadata.get(key)
        if value is not None:
            metadata[key] = value
    return metadata


def _validated_edited_fields(edited_fields: dict[str, Any]) -> dict[str, Any]:
    unknown_fields = set(edited_fields) - _EDITABLE_TASK_FIELDS
    if unknown_fields:
        raise TaskCommitError(
            "invalid_edited_fields",
            f"Unsupported edited field(s): {', '.join(sorted(unknown_fields))}.",
        )
    return {key: value for key, value in edited_fields.items()}


def _select_subtasks(
    candidate: TaskCandidateResponse,
    selected_ids: list[str] | list[UUID] | None,
) -> list[CandidateSubtaskResponse]:
    if selected_ids is None:
        return list(candidate.subtasks)

    selected = {str(item) for item in selected_ids}
    available = {str(item.id): item for item in candidate.subtasks}
    missing = selected - set(available)
    if missing:
        raise TaskCommitError(
            "invalid_subtask_selection",
            "Selected subtask id does not belong to this candidate.",
        )
    return [item for item in candidate.subtasks if str(item.id) in selected]


def _select_reminders(
    candidate: TaskCandidateResponse,
    selected_ids: list[str] | list[UUID] | None,
) -> list[CandidateReminderResponse]:
    if selected_ids is None:
        selected_reminders = list(candidate.reminders)
    else:
        selected = {str(item) for item in selected_ids}
        available = {str(item.id): item for item in candidate.reminders}
        missing = selected - set(available)
        if missing:
            raise TaskCommitError(
                "invalid_reminder_selection",
                "Selected reminder id does not belong to this candidate.",
            )
        selected_reminders = [item for item in candidate.reminders if str(item.id) in selected]

    for reminder in selected_reminders:
        if reminder.remind_at is None:
            raise TaskCommitError(
                "invalid_reminder_selection",
                "Selected reminder must have remind_at before final commit.",
            )
    return selected_reminders


def _subtask_payload(subtask: CandidateSubtaskResponse) -> dict[str, Any]:
    return {
        "candidate_subtask_id": str(subtask.id),
        "title": subtask.title,
        "order_index": subtask.order_index,
        "estimated_minutes": subtask.estimated_minutes,
        "status": SubtaskStatus.TODO.value,
        "is_next_action": subtask.is_next_action,
        "energy_required": _enum_value(subtask.energy_required),
    }


def _reminder_payload(reminder: CandidateReminderResponse) -> dict[str, Any]:
    return {
        "candidate_reminder_id": str(reminder.id),
        "remind_at": _datetime_value(reminder.remind_at),
        "message": reminder.message,
        "type": _enum_value(reminder.type),
        "status": "scheduled",
        "escalation_level": reminder.escalation_level,
    }


def _candidate_source(candidate: TaskCandidateResponse) -> str:
    source = candidate.model_payload.get("source")
    if source is None and isinstance(candidate.model_payload.get("raw_input"), dict):
        source = candidate.model_payload["raw_input"].get("source")
    if source in _ALLOWED_SOURCES:
        return str(source)
    return TaskSource.AI.value


def _enum_value(value: StrEnum | str | None) -> str | None:
    if value is None:
        return None
    if isinstance(value, StrEnum):
        return value.value
    return str(value)


def _datetime_value(value: datetime | date | str | None) -> str | None:
    if value is None:
        return None
    if isinstance(value, str):
        return value
    return value.isoformat()


def _json_safe(value: Any) -> Any:
    if isinstance(value, BaseModel):
        return value.model_dump(mode="json")
    if isinstance(value, dict):
        return {key: _json_safe(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_json_safe(item) for item in value]
    if isinstance(value, tuple):
        return [_json_safe(item) for item in value]
    if isinstance(value, datetime | date):
        return value.isoformat()
    if isinstance(value, UUID):
        return str(value)
    if isinstance(value, StrEnum):
        return value.value
    return value
