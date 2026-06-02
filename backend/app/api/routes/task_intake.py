from fastapi import APIRouter, Depends, HTTPException, status

from app.api.dependencies import get_current_user_id, get_intake_service
from app.schemas.common import ApiResponse, ErrorDetail
from app.schemas.task_intake import TaskIntakeRequest, TaskIntakeResponse
from app.services.intake_service import IntakeService


router = APIRouter()

TaskIntakeApiResponse = ApiResponse[TaskIntakeResponse]


@router.post(
    "",
    response_model=TaskIntakeApiResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create task intake",
    description=(
        "Store the raw user input first, run the ADHD-friendly mediator, "
        "and return the generated task candidate for user review."
    ),
)
async def create_task_intake(
    payload: TaskIntakeRequest,
    user_id: str = Depends(get_current_user_id),
    intake_service: IntakeService = Depends(get_intake_service),
) -> TaskIntakeApiResponse:
    try:
        result = intake_service.handle_intake(user_id=user_id, request=payload)
    except ValueError as error:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=ErrorDetail(
                code="invalid_task_intake_request",
                message=str(error),
            ).model_dump(),
        ) from error
    except Exception as error:
        if _is_rate_limited_error(error):
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=ErrorDetail(
                    code="ai_rate_limited",
                    message="AI provider rate limit exceeded. Please retry later.",
                ).model_dump(),
            ) from error
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=ErrorDetail(
                code="task_intake_failed",
                message="Task intake failed unexpectedly.",
            ).model_dump(),
        ) from error

    return TaskIntakeApiResponse(success=True, data=result, error=None)


def _is_rate_limited_error(error: Exception) -> bool:
    message = str(error).lower().strip()
    if not message:
        return False

    return any(
        token in message
        for token in (
            "too many requests",
            "rate limit",
            "rate_limit",
            "resource_exhausted",
            "quota exceeded",
            "429",
        )
    )
