import logging

from fastapi import APIRouter, Depends, HTTPException, status
from starlette.concurrency import run_in_threadpool

from app.api.dependencies import get_current_user_id, get_intake_service
from app.schemas.common import ApiResponse, ErrorDetail
from app.schemas.task_intake import TaskIntakeRequest, TaskIntakeResponse
from app.services.intake_service import IntakeService


logger = logging.getLogger(__name__)
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
        result = await run_in_threadpool(
            intake_service.handle_intake,
            user_id=user_id,
            request=payload,
        )
    except ValueError as error:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=ErrorDetail(
                code="invalid_task_intake_request",
                message=str(error),
            ).model_dump(),
        ) from error
    except Exception as error:
        status_code, error_detail = _task_intake_error_detail(error)
        logger.exception(
            "Task intake failed for user_id=%s with code=%s",
            user_id,
            error_detail.code,
        )
        raise HTTPException(
            status_code=status_code,
            detail=error_detail.model_dump(),
        ) from error

    return TaskIntakeApiResponse(success=True, data=result, error=None)


def _task_intake_error_detail(error: Exception) -> tuple[int, ErrorDetail]:
    if _is_rate_limited_error(error):
        return (
            status.HTTP_429_TOO_MANY_REQUESTS,
            ErrorDetail(
                code="ai_rate_limited",
                message="AI provider rate limit exceeded. Please retry later.",
            ),
        )
    if _is_timeout_error(error):
        return (
            status.HTTP_504_GATEWAY_TIMEOUT,
            ErrorDetail(
                code="ai_provider_timeout",
                message="AI provider response timed out. Please retry later.",
            ),
        )
    if _is_provider_temporarily_unavailable_error(error):
        return (
            status.HTTP_503_SERVICE_UNAVAILABLE,
            ErrorDetail(
                code="ai_provider_temporarily_unavailable",
                message="AI provider is temporarily unavailable. Please retry shortly.",
            ),
        )
    if _is_provider_configuration_error(error):
        return (
            status.HTTP_503_SERVICE_UNAVAILABLE,
            ErrorDetail(
                code="ai_provider_unavailable",
                message="AI provider is not configured correctly on the server.",
            ),
        )

    return (
        status.HTTP_500_INTERNAL_SERVER_ERROR,
        ErrorDetail(
            code="task_intake_failed",
            message="Task intake failed unexpectedly.",
        ),
    )


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


def _is_timeout_error(error: Exception) -> bool:
    message = str(error).lower().strip()
    if not message:
        return False

    return any(
        token in message
        for token in (
            "deadline exceeded",
            "timed out",
            "timeout",
            "504",
            "gateway timeout",
        )
    )


def _is_provider_configuration_error(error: Exception) -> bool:
    message = str(error).lower().strip()
    if not message:
        return False

    return any(
        token in message
        for token in (
            "gemini_api_key is required",
            "google-genai is required",
            "gemini mediator prompt file was not found",
            "gemini_thinking_level must be one of",
            "api key not valid",
            "api_key_invalid",
            "invalid api key",
        )
    )


def _is_provider_temporarily_unavailable_error(error: Exception) -> bool:
    message = str(error).lower().strip()
    if not message:
        return False

    return any(
        token in message
        for token in (
            "503 unavailable",
            "status: 'unavailable'",
            "status\":\"unavailable\"",
            "servererror: 503",
            "currently experiencing high demand",
            "try again later",
        )
    )
