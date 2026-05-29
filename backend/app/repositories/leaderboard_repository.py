from collections import Counter
from typing import Any

from app.repositories.base import LeaderboardRepository
from app.schemas.leaderboard import LeaderboardEntryResponse, LeaderboardResponse


class SupabaseLeaderboardRepository(LeaderboardRepository):
    def __init__(self, client: Any) -> None:
        self._client = client

    def get_leaderboard(
        self,
        current_user_id: str,
        *,
        limit: int = 50,
    ) -> LeaderboardResponse:
        profile_response = (
            self._client.table("users_profile")
            .select(
                "user_id, user_name, user_role, level, credits, "
                "user_stats("
                "earned_exp, completed_quest_count, weekly_completed_count, weekly_completion_rate"
                ")",
            )
            .execute()
        )
        clear_response = self._client.table("dungeon_clears").select("user_id").execute()

        profiles = profile_response.data or []
        cleared_counts = Counter(
            row["user_id"]
            for row in (clear_response.data or [])
            if row.get("user_id")
        )

        entries = [
            _map_entry(row, cleared_dungeon_count=cleared_counts.get(row.get("user_id", ""), 0))
            for row in profiles
            if row.get("user_id")
        ]
        entries.sort(key=lambda entry: (-entry.score, entry.userName.lower(), entry.userId))

        current_user_rank = 0
        annotated_entries: list[LeaderboardEntryResponse] = []
        for index, entry in enumerate(entries, start=1):
            is_current_user = entry.userId == current_user_id
            if is_current_user:
                current_user_rank = index
            annotated_entries.append(
                entry.model_copy(
                    update={
                        "rank": index,
                        "isCurrentUser": is_current_user,
                    }
                )
            )

        if limit > 0 and len(annotated_entries) > limit:
            visible_entries = annotated_entries[:limit]
            if current_user_rank > limit:
                current_user_entry = annotated_entries[current_user_rank - 1]
                visible_entries = [*visible_entries[:-1], current_user_entry]
            annotated_entries = visible_entries

        return LeaderboardResponse(
            entries=annotated_entries,
            currentUserRank=current_user_rank,
        )


def _map_entry(
    row: dict[str, Any],
    *,
    cleared_dungeon_count: int,
) -> LeaderboardEntryResponse:
    raw_stats = row.get("user_stats")
    if isinstance(raw_stats, list):
        stats = raw_stats[0] if raw_stats else {}
    elif isinstance(raw_stats, dict):
        stats = raw_stats
    else:
        stats = {}

    earned_exp = _as_int(stats.get("earned_exp"))
    credits = _as_int(row.get("credits"))
    completed_quest_count = _as_int(stats.get("completed_quest_count"))
    weekly_completed_count = _as_int(stats.get("weekly_completed_count"))
    weekly_completion_rate = _as_int(stats.get("weekly_completion_rate"))

    return LeaderboardEntryResponse(
        rank=0,
        userId=row["user_id"],
        userName=(row.get("user_name") or "Unknown User").strip() or "Unknown User",
        userRole=row.get("user_role") or "Beginner",
        level=_as_int(row.get("level")),
        score=_ranking_score(
            earned_exp=earned_exp,
            credits=credits,
            completed_quest_count=completed_quest_count,
            weekly_completed_count=weekly_completed_count,
            weekly_completion_rate=weekly_completion_rate,
            cleared_dungeon_count=cleared_dungeon_count,
        ),
        earnedExp=earned_exp,
        credits=credits,
        completedQuestCount=completed_quest_count,
        weeklyCompletedCount=weekly_completed_count,
        weeklyCompletionRate=weekly_completion_rate,
        clearedDungeonCount=cleared_dungeon_count,
    )


def _ranking_score(
    *,
    earned_exp: int,
    credits: int,
    completed_quest_count: int,
    weekly_completed_count: int,
    weekly_completion_rate: int,
    cleared_dungeon_count: int,
) -> int:
    return (
        earned_exp
        + (credits * 2)
        + (completed_quest_count * 80)
        + (weekly_completed_count * 120)
        + (weekly_completion_rate * 8)
        + (cleared_dungeon_count * 240)
    )


def _as_int(value: Any) -> int:
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    return 0
