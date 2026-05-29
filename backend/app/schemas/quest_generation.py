from datetime import datetime

from pydantic import BaseModel, Field, model_validator

from app.schemas.quest import QuestCategory, QuestDifficulty


class QuestGenerationRequest(BaseModel):
    prompt: str | None = Field(
        default=None,
        description="Optional short prompt used to generate quests.",
    )
    source_text: str | None = Field(
        default=None,
        description="Optional raw source text used to extract quest candidates.",
    )
    difficulty: QuestDifficulty | None = Field(
        default=None,
        description="Optional target difficulty for generated quests.",
    )
    category: QuestCategory | None = Field(
        default=None,
        description="Optional target category for generated quests.",
    )
    max_items: int | None = Field(
        default=None,
        ge=1,
        le=20,
        description="Maximum number of quest candidates to return.",
    )

    @model_validator(mode="after")
    def validate_prompt_or_source_text(self) -> "QuestGenerationRequest":
        has_prompt = bool(self.prompt and self.prompt.strip())
        has_source_text = bool(self.source_text and self.source_text.strip())
        if not has_prompt and not has_source_text:
            raise ValueError("Either prompt or source_text must be provided.")
        return self


class QuestCandidateResponse(BaseModel):
    title: str
    difficulty: QuestDifficulty
    category: QuestCategory
    exp: int
    defaultDurationSeconds: int
    reason: str | None = None
    external_source: str | None = None
    external_id: str | None = None
    external_url: str | None = None
    external_updated_at: datetime | None = None


class QuestGenerationResponse(BaseModel):
    quests: list[QuestCandidateResponse]


class OCRTextQuestExtractionRequest(BaseModel):
    raw_text: str


class OCRTextQuestExtractionResponse(BaseModel):
    quests: list[QuestCandidateResponse]
    cleaned_lines: list[str]
    duplicate_removed_count: int
