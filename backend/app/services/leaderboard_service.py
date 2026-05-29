from app.repositories.base import LeaderboardRepository
from app.schemas.leaderboard import LeaderboardResponse


class LeaderboardService:
    def __init__(self, leaderboard_repository: LeaderboardRepository) -> None:
        self._leaderboard_repository = leaderboard_repository

    def get_leaderboard(
        self,
        current_user_id: str,
        *,
        limit: int = 50,
    ) -> LeaderboardResponse:
        return self._leaderboard_repository.get_leaderboard(
            current_user_id,
            limit=limit,
        )

