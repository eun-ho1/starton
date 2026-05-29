from pydantic import BaseModel, Field


class LeaderboardEntryResponse(BaseModel):
    rank: int
    userId: str
    userName: str
    userRole: str
    level: int
    score: int
    earnedExp: int
    credits: int
    completedQuestCount: int
    weeklyCompletedCount: int
    weeklyCompletionRate: int
    clearedDungeonCount: int = Field(
        ...,
        description="Number of cleared dungeons used in the score calculation.",
    )
    isCurrentUser: bool = False


class LeaderboardResponse(BaseModel):
    entries: list[LeaderboardEntryResponse]
    currentUserRank: int
