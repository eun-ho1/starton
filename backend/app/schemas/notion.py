from pydantic import BaseModel, Field, model_validator

from app.schemas.quest_generation import QuestCandidateResponse


class NotionConnectRequest(BaseModel):
    notion_api_token: str = Field(..., min_length=1)
    database_id: str | None = None
    database_url: str | None = None
    data_source_id: str | None = None

    @model_validator(mode="after")
    def validate_database_identifier(self) -> "NotionConnectRequest":
        has_database_id = bool(self.database_id and self.database_id.strip())
        has_database_url = bool(self.database_url and self.database_url.strip())
        has_data_source_id = bool(self.data_source_id and self.data_source_id.strip())
        if not has_database_id and not has_database_url and not has_data_source_id:
            raise ValueError(
                "Either database_id, database_url, or data_source_id must be provided.",
            )
        return self


class NotionConnectResponse(BaseModel):
    connection_id: str
    database_id: str
    database_title: str
    sync_status: str


class NotionSyncRequest(BaseModel):
    pass


class NotionSyncResponse(BaseModel):
    database_id: str
    database_title: str
    quests: list[QuestCandidateResponse]
    imported_count: int = 0
    updated_count: int = 0
    skipped_count: int = 0
    stale_count: int = 0


class NotionConnectionStatusResponse(BaseModel):
    connected: bool = Field(
        description="True when the saved Notion connection is still active.",
    )
    connection_id: str | None = Field(
        default=None,
        description="Stable backend identifier for the saved Notion connection row.",
    )
    database_id: str | None = Field(
        default=None,
        description="Resolved Notion database or data source identifier in snake_case JSON.",
    )
    data_source_id: str | None = Field(
        default=None,
        description="Resolved Notion data source identifier in snake_case JSON.",
    )
    database_title: str | None = Field(
        default=None,
        description="Human-readable Notion database or data source title.",
    )
    database_url: str | None = Field(
        default=None,
        description="Canonical Notion database URL when available.",
    )
    last_synced_at: str | None = Field(
        default=None,
        description="Last sync attempt timestamp as an ISO-8601 string, or null.",
    )
    last_successful_synced_at: str | None = Field(
        default=None,
        description="Last successful sync timestamp as an ISO-8601 string, or null.",
    )
    sync_status: str | None = Field(
        default=None,
        description="Public sync status value in snake_case JSON.",
    )
    last_error_message: str | None = Field(
        default=None,
        description=(
            "Sanitized client-safe error summary for the most recent Notion sync failure."
        ),
    )
