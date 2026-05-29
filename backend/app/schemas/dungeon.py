from pydantic import BaseModel


class DungeonStatusResponse(BaseModel):
    dungeonId: str
    title: str
    difficulty: str
    completed: bool
    cleared: bool
    canClaim: bool
    creditReward: int
    clearedAt: str | None = None


class DungeonListResponse(BaseModel):
    dungeons: list[DungeonStatusResponse]


class DungeonClearResponse(BaseModel):
    dungeonId: str
    cleared: bool
    credits: int
    clearedAt: str
