from datetime import datetime
from typing import Any

from app.repositories.base import DungeonRepository
from app.schemas.dungeon import (
    DungeonClearResponse,
    DungeonStatusResponse,
)


class SupabaseDungeonRepository(DungeonRepository):
    def __init__(self, client: Any) -> None:
        self._client = client

    def list_dungeons(self, user_id: str) -> list[DungeonStatusResponse]:
        quest_response = (
            self._client.table("quests")
            .select("id, title, difficulty, status, created_at")
            .eq("user_id", user_id)
            .in_("status", ["active", "completed"])
            .order("created_at", desc=True)
            .execute()
        )
        clear_response = (
            self._client.table("dungeon_clears")
            .select("dungeon_id, cleared_at")
            .eq("user_id", user_id)
            .execute()
        )

        quests = quest_response.data or []
        clears = clear_response.data or []
        cleared_by_id = {row["dungeon_id"]: row for row in clears}

        return [
            DungeonStatusResponse(
                dungeonId=quest["id"],
                title=quest["title"],
                difficulty=quest["difficulty"],
                completed=quest["status"] == "completed",
                cleared=quest["id"] in cleared_by_id,
                canClaim=quest["status"] == "completed"
                and quest["id"] not in cleared_by_id,
                creditReward=_credit_reward_for_difficulty(quest["difficulty"]),
                clearedAt=cleared_by_id.get(quest["id"], {}).get("cleared_at"),
            )
            for quest in quests
        ]

    def clear_dungeon(
        self,
        user_id: str,
        dungeon_id: str,
    ) -> DungeonClearResponse:
        quest_response = (
            self._client.table("quests")
            .select("id, difficulty, status")
            .eq("user_id", user_id)
            .eq("id", dungeon_id)
            .limit(1)
            .execute()
        )
        quest_rows = quest_response.data or []
        if not quest_rows:
            raise ValueError("Quest was not found for the given user_id.")

        quest_row = quest_rows[0]
        if quest_row["status"] != "completed":
            raise PermissionError("Quest reward can only be claimed after completion.")

        credit_reward = _credit_reward_for_difficulty(quest_row["difficulty"])
        existing = (
            self._client.table("dungeon_clears")
            .select("id, cleared_at")
            .eq("user_id", user_id)
            .eq("dungeon_id", dungeon_id)
            .limit(1)
            .execute()
        )
        rows = existing.data or []
        if rows:
            profile = (
                self._client.table("users_profile")
                .select("credits")
                .eq("user_id", user_id)
                .limit(1)
                .execute()
            )
            profile_row = (profile.data or [{}])[0]
            return DungeonClearResponse(
                dungeonId=dungeon_id,
                cleared=True,
                credits=profile_row.get("credits", 0),
                clearedAt=rows[0]["cleared_at"],
            )

        profile_response = (
            self._client.table("users_profile")
            .select("id, credits")
            .eq("user_id", user_id)
            .limit(1)
            .execute()
        )
        profile_rows = profile_response.data or []
        if not profile_rows:
            raise ValueError("Profile was not found for the given user_id.")

        profile_row = profile_rows[0]
        cleared_at = datetime.utcnow().isoformat()
        self._client.table("dungeon_clears").insert(
            {
                "user_id": user_id,
                "profile_id": profile_row["id"],
                "dungeon_id": dungeon_id,
                "cleared_at": cleared_at,
            },
        ).execute()
        next_credits = profile_row["credits"] + credit_reward
        (
            self._client.table("users_profile")
            .update({"credits": next_credits})
            .eq("user_id", user_id)
            .execute()
        )
        return DungeonClearResponse(
            dungeonId=dungeon_id,
            cleared=True,
            credits=next_credits,
            clearedAt=cleared_at,
        )


def _credit_reward_for_difficulty(difficulty: str) -> int:
    normalized = (difficulty or "").strip().lower()
    if normalized == "easy":
        return 8
    if normalized == "hard":
        return 16
    return 12
