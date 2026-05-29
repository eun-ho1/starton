from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.api.dependencies import get_current_user_id, get_leaderboard_service
from app.schemas.common import ApiResponse, ErrorDetail
from app.schemas.leaderboard import LeaderboardResponse
from app.services.leaderboard_service import LeaderboardService

router = APIRouter()

LeaderboardApiResponse = ApiResponse[LeaderboardResponse]


@router.get(
    "/leaderboard",
    response_model=LeaderboardApiResponse,
    summary="Get leaderboard",
    description="Return the leaderboard built from real user profile, stats, and dungeon clear data.",
)
async def get_leaderboard(
    limit: int = Query(default=50, ge=1, le=200),
    user_id: str = Depends(get_current_user_id),
    leaderboard_service: LeaderboardService = Depends(get_leaderboard_service),
) -> LeaderboardApiResponse:
    try:
        leaderboard = leaderboard_service.get_leaderboard(user_id, limit=limit)
    except ValueError as error:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=ErrorDetail(
                code="leaderboard_not_found",
                message=str(error),
            ).model_dump(),
        ) from error
    except Exception as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=ErrorDetail(
                code="leaderboard_load_failed",
                message="Failed to load leaderboard data.",
            ).model_dump(),
        ) from error

    return LeaderboardApiResponse(success=True, data=leaderboard, error=None)

