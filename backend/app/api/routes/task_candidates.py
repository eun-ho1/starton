from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from starlette.concurrency import run_in_threadpool

from app.api.dependencies import (
    get_current_user_id,
    get_task_candidate_repository,
    get_task_candidate_review_service,
    get_task_commit_service,
)
from app.repositories.task_candidate_repository import SupabaseTaskCandidateRepository
from app.schemas.common import ApiResponse, ErrorDetail
from app.schemas.task import TaskCommitResult, TaskConfirmRequest
from app.schemas.task_candidate import (
    TaskCandidateRejectRequest,
    TaskCandidateResponse,
    TaskCandidateReviseRequest,
)
from app.services.task_candidate_review_service import (
    TaskCandidateReviewError,
    TaskCandidateReviewService,
)
from app.services.task_commit_service import TaskCommitError, TaskCommitService


router = APIRouter()

TaskCandidateApiResponse = ApiResponse[TaskCandidateResponse]
TaskConfirmApiResponse = ApiResponse[TaskCommitResult]


_TASK_COMMIT_ERROR_STATUSES = {
    "candidate_not_found": status.HTTP_404_NOT_FOUND,
    "candidate_already_committed": status.HTTP_409_CONFLICT,
    "candidate_not_committable": status.HTTP_409_CONFLICT,
    "invalid_task_commit_request": status.HTTP_400_BAD_REQUEST,
    "invalid_edited_fields": status.HTTP_400_BAD_REQUEST,
    "invalid_subtask_selection": status.HTTP_400_BAD_REQUEST,
    "invalid_reminder_selection": status.HTTP_400_BAD_REQUEST,
    "task_storage_unavailable": status.HTTP_503_SERVICE_UNAVAILABLE,
}
_TASK_CANDIDATE_REVIEW_ERROR_STATUSES = {
    "candidate_not_found": status.HTTP_404_NOT_FOUND,
    "candidate_already_committed": status.HTTP_409_CONFLICT,
    "candidate_not_revisable": status.HTTP_409_CONFLICT,
    "candidate_not_rejectable": status.HTTP_409_CONFLICT,
    "invalid_candidate_revision": status.HTTP_400_BAD_REQUEST,
    "invalid_edited_fields": status.HTTP_400_BAD_REQUEST,
}


@router.get(
    "/{candidate_id}",
    response_model=TaskCandidateApiResponse,
    summary="Get task candidate",
    description=(
        "Return a stored task candidate with its subtasks and reminders for "
        "the authenticated user review flow."
    ),
)
async def get_task_candidate(
    candidate_id: UUID,
    user_id: str = Depends(get_current_user_id),
    task_candidate_repository: SupabaseTaskCandidateRepository = Depends(
        get_task_candidate_repository,
    ),
) -> TaskCandidateApiResponse:
    try:
        candidate = task_candidate_repository.get(
            user_id=user_id,
            candidate_id=str(candidate_id),
        )
    except ValueError as error:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=ErrorDetail(
                code="task_candidate_not_found",
                message="Task candidate was not found.",
            ).model_dump(),
        ) from error
    except Exception as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=ErrorDetail(
                code="task_candidate_lookup_failed",
                message="Task candidate lookup failed unexpectedly.",
            ).model_dump(),
        ) from error

    return TaskCandidateApiResponse(success=True, data=candidate, error=None)


@router.post(
    "/{candidate_id}/confirm",
    response_model=TaskConfirmApiResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Confirm task candidate",
    description=(
        "Commit a reviewed task candidate into final task, subtask, and "
        "reminder records for the authenticated user."
    ),
)
async def confirm_task_candidate(
    candidate_id: UUID,
    payload: TaskConfirmRequest,
    user_id: str = Depends(get_current_user_id),
    task_commit_service: TaskCommitService = Depends(get_task_commit_service),
) -> TaskConfirmApiResponse:
    try:
        result = await run_in_threadpool(
            task_commit_service.commit_candidate,
            user_id=user_id,
            candidate_id=str(candidate_id),
            accepted=payload.accepted,
            edited_fields=payload.edited_fields,
            selected_subtask_ids=payload.selected_subtask_ids,
            selected_reminder_ids=payload.selected_reminder_ids,
        )
    except TaskCommitError as error:
        raise HTTPException(
            status_code=_status_for_task_commit_error(error.code),
            detail=ErrorDetail(code=error.code, message=error.message).model_dump(),
        ) from error
    except Exception as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=ErrorDetail(
                code="task_candidate_confirm_failed",
                message="Task candidate confirmation failed unexpectedly.",
            ).model_dump(),
        ) from error

    return TaskConfirmApiResponse(success=True, data=result, error=None)


@router.post(
    "/{candidate_id}/revise",
    response_model=TaskCandidateApiResponse,
    summary="Revise task candidate",
    description=(
        "Record a user revision intent and update allowed top-level candidate "
        "fields without creating final task records."
    ),
)
async def revise_task_candidate(
    candidate_id: UUID,
    payload: TaskCandidateReviseRequest,
    user_id: str = Depends(get_current_user_id),
    review_service: TaskCandidateReviewService = Depends(
        get_task_candidate_review_service,
    ),
) -> TaskCandidateApiResponse:
    try:
        candidate = review_service.revise_candidate(
            user_id=user_id,
            candidate_id=str(candidate_id),
            revision_type=payload.revision_type,
            edited_fields=payload.edited_fields,
            note=payload.note,
        )
    except TaskCandidateReviewError as error:
        raise HTTPException(
            status_code=_status_for_task_candidate_review_error(error.code),
            detail=ErrorDetail(code=error.code, message=error.message).model_dump(),
        ) from error
    except Exception as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=ErrorDetail(
                code="task_candidate_revise_failed",
                message="Task candidate revision failed unexpectedly.",
            ).model_dump(),
        ) from error

    return TaskCandidateApiResponse(success=True, data=candidate, error=None)


@router.post(
    "/{candidate_id}/reject",
    response_model=TaskCandidateApiResponse,
    summary="Reject task candidate",
    description=(
        "Mark a reviewed task candidate as rejected without creating final "
        "task records."
    ),
)
async def reject_task_candidate(
    candidate_id: UUID,
    payload: TaskCandidateRejectRequest,
    user_id: str = Depends(get_current_user_id),
    review_service: TaskCandidateReviewService = Depends(
        get_task_candidate_review_service,
    ),
) -> TaskCandidateApiResponse:
    try:
        candidate = review_service.reject_candidate(
            user_id=user_id,
            candidate_id=str(candidate_id),
            reason=payload.reason,
        )
    except TaskCandidateReviewError as error:
        raise HTTPException(
            status_code=_status_for_task_candidate_review_error(error.code),
            detail=ErrorDetail(code=error.code, message=error.message).model_dump(),
        ) from error
    except Exception as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=ErrorDetail(
                code="task_candidate_reject_failed",
                message="Task candidate rejection failed unexpectedly.",
            ).model_dump(),
        ) from error

    return TaskCandidateApiResponse(success=True, data=candidate, error=None)


def _status_for_task_commit_error(code: str) -> int:
    return _TASK_COMMIT_ERROR_STATUSES.get(code, status.HTTP_400_BAD_REQUEST)


def _status_for_task_candidate_review_error(code: str) -> int:
    return _TASK_CANDIDATE_REVIEW_ERROR_STATUSES.get(
        code,
        status.HTTP_400_BAD_REQUEST,
    )
