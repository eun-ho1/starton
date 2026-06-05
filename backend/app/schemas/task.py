from datetime import datetime
from enum import StrEnum
from typing import Any
from uuid import UUID

from pydantic import BaseModel, Field

from app.schemas.reminder import ReminderResponse
from app.schemas.task_candidate import (
    TaskDifficulty,
    TaskEnergyRequired,
    TaskPriority,
)


class TaskSource(StrEnum):
    MANUAL = "manual"
    OCR = "ocr"
    NOTION = "notion"
    VOICE = "voice"
    EMAIL = "email"
    AI = "ai"
    MIGRATION = "migration"


class TaskStatus(StrEnum):
    TODO = "todo"
    DOING = "doing"
    DONE = "done"
    PAUSED = "paused"
    CANCELLED = "cancelled"


class SubtaskStatus(StrEnum):
    TODO = "todo"
    DOING = "doing"
    DONE = "done"
    SKIPPED = "skipped"


class SubtaskResponse(BaseModel):
    id: UUID = Field(..., description="Final subtask id.")
    task_id: UUID = Field(..., description="Final parent task id.")
    user_id: UUID = Field(..., description="Authenticated Supabase user id.")
    candidate_subtask_id: UUID | None = Field(
        default=None,
        description="Candidate subtask this final subtask was committed from.",
    )
    title: str = Field(..., min_length=1, max_length=200, description="Subtask title.")
    order_index: int = Field(..., ge=0, description="Sort order inside the final task.")
    estimated_minutes: int | None = Field(default=None, ge=0)
    status: SubtaskStatus = Field(default=SubtaskStatus.TODO)
    is_next_action: bool = Field(default=False)
    energy_required: TaskEnergyRequired | None = Field(default=None)
    created_at: datetime | None = Field(default=None)
    updated_at: datetime | None = Field(default=None)
    completed_at: datetime | None = Field(default=None)


class TaskResponse(BaseModel):
    id: UUID = Field(..., description="Final task id.")
    user_id: UUID = Field(..., description="Authenticated Supabase user id.")
    candidate_id: UUID | None = Field(default=None, description="Committed candidate id.")
    raw_input_id: UUID | None = Field(default=None, description="Original raw input id.")
    mediator_run_id: UUID | None = Field(default=None, description="Mediator run id.")
    title: str = Field(..., min_length=1, max_length=200, description="Task title.")
    description: str | None = Field(default=None)
    status: TaskStatus = Field(default=TaskStatus.TODO)
    priority: TaskPriority | None = Field(default=None)
    due_at: datetime | None = Field(default=None)
    estimated_minutes: int | None = Field(default=None, ge=0)
    elapsed_seconds: int = Field(default=0, ge=0)
    energy_required: TaskEnergyRequired | None = Field(default=None)
    difficulty: TaskDifficulty | None = Field(default=None)
    next_action: str | None = Field(default=None)
    source: TaskSource = Field(default=TaskSource.AI)
    metadata: dict[str, Any] = Field(default_factory=dict)
    subtasks: list[SubtaskResponse] = Field(default_factory=list)
    reminders: list[ReminderResponse] = Field(default_factory=list)
    created_at: datetime | None = Field(default=None)
    updated_at: datetime | None = Field(default=None)
    completed_at: datetime | None = Field(default=None)


class TaskProgressUpdateRequest(BaseModel):
    elapsed_seconds: int = Field(default=0, ge=0)


class TaskCreateFromCandidateRequest(BaseModel):
    edited_fields: dict[str, Any] = Field(
        default_factory=dict,
        description="User edits to apply before committing the candidate.",
    )
    selected_subtask_ids: list[UUID] | None = Field(
        default=None,
        description="Candidate subtasks selected for final commit.",
    )
    selected_reminder_ids: list[UUID] | None = Field(
        default=None,
        description="Candidate reminders selected for final commit.",
    )


class TaskConfirmRequest(TaskCreateFromCandidateRequest):
    accepted: bool = Field(
        default=True,
        description="Whether the user accepted the candidate for final task creation.",
    )


class TaskCommitResult(BaseModel):
    candidate_id: UUID = Field(..., description="Committed task candidate id.")
    task: TaskResponse = Field(..., description="Final task created from the candidate.")
