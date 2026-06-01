from datetime import datetime
from enum import StrEnum

from pydantic import BaseModel, Field


class QuestDifficulty(StrEnum):
    EASY = "easy"
    NORMAL = "normal"
    HARD = "hard"


class QuestCategory(StrEnum):
    WORK = "work"
    LIFE = "life"
    STUDY = "study"
    HOME = "home"


class QuestItemResponse(BaseModel):
    id: str = Field(..., description="Quest id stored in Supabase.")
    title: str = Field(..., min_length=1, max_length=120, examples=["Prepare weekly report"])
    exp: int = Field(..., ge=0, le=10000, description="Configured quest EXP reward.")
    difficulty: QuestDifficulty = Field(..., description="Quest difficulty.")
    category: QuestCategory = Field(..., description="Quest category.")
    elapsedSeconds: int = Field(..., ge=0, description="Accumulated elapsed seconds.")
    defaultDurationSeconds: int = Field(
        ...,
        ge=0,
        description="Expected default duration for the quest in seconds.",
    )
    dueAt: datetime | None = Field(
        default=None,
        description="Optional due date/time for the quest.",
        serialization_alias="due_at",
        validation_alias="due_at",
    )


class QuestCreateRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=120, examples=["Prepare weekly report"])
    exp: int = Field(..., ge=0, le=10000, examples=[50])
    difficulty: QuestDifficulty = Field(..., examples=["normal"])
    category: QuestCategory = Field(..., examples=["work"])
    defaultDurationSeconds: int = Field(..., ge=0, examples=[2700])
    dueAt: datetime | None = Field(
        default=None,
        examples=["2026-06-02T09:00:00+09:00"],
        serialization_alias="due_at",
        validation_alias="due_at",
    )


class QuestUpdateRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=120, examples=["Prepare weekly report"])
    exp: int = Field(..., ge=0, le=10000, examples=[50])
    difficulty: QuestDifficulty = Field(..., examples=["normal"])
    category: QuestCategory = Field(..., examples=["work"])
    elapsedSeconds: int = Field(..., ge=0, examples=[1800])
    defaultDurationSeconds: int = Field(..., ge=0, examples=[2700])
    dueAt: datetime | None = Field(
        default=None,
        examples=["2026-06-02T09:00:00+09:00"],
        serialization_alias="due_at",
        validation_alias="due_at",
    )


class CompletedQuestRecordSchema(BaseModel):
    questId: str = Field(..., description="Completed quest id.")
    title: str = Field(..., description="Completed quest title.")
    difficulty: QuestDifficulty = Field(..., description="Completed quest difficulty.")
    category: QuestCategory = Field(..., description="Completed quest category.")
    earnedExp: int = Field(..., ge=0, description="Earned EXP after completion.")
    completedAt: datetime = Field(..., description="Completion timestamp.")
    elapsedSeconds: int = Field(..., ge=0, description="Elapsed seconds recorded at completion.")
    proofImagePath: str | None = Field(
        default=None,
        description="Optional proof image path if stored.",
    )


class QuestCompleteRequest(BaseModel):
    elapsedSeconds: int = Field(default=0, ge=0, examples=[1800])
    proofImagePath: str | None = Field(default=None, examples=["/proofs/quest.png"])
