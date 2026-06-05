from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from app.api.dependencies import get_current_user_id, get_task_service
from app.schemas.common import ApiResponse, ErrorDetail
from app.schemas.quest import CompletedQuestRecordSchema, QuestCompleteRequest
from app.schemas.task import TaskProgressUpdateRequest, TaskResponse
from app.services.task_service import TaskService, TaskServiceError


router = APIRouter()

TaskListApiResponse = ApiResponse[list[TaskResponse]]
TaskItemApiResponse = ApiResponse[TaskResponse]
CompletedTaskApiResponse = ApiResponse[CompletedQuestRecordSchema]

_TASK_ERROR_STATUSES = {
    "task_list_failed": status.HTTP_500_INTERNAL_SERVER_ERROR,
    "task_not_found": status.HTTP_404_NOT_FOUND,
    "task_already_completed": status.HTTP_409_CONFLICT,
    "task_dependency_not_found": status.HTTP_500_INTERNAL_SERVER_ERROR,
    "task_progress_update_failed": status.HTTP_500_INTERNAL_SERVER_ERROR,
}


@router.get(
    "",
    response_model=TaskListApiResponse,
    summary="List active tasks",
    description=(
        "Return committed task records that are still active for the "
        "authenticated Supabase user."
    ),
)
async def list_tasks(
    user_id: str = Depends(get_current_user_id),
    task_service: TaskService = Depends(get_task_service),
) -> TaskListApiResponse:
    try:
        tasks = task_service.list_active_tasks(user_id=user_id)
    except TaskServiceError as error:
        raise HTTPException(
            status_code=_TASK_ERROR_STATUSES.get(
                error.code,
                status.HTTP_500_INTERNAL_SERVER_ERROR,
            ),
            detail=ErrorDetail(code=error.code, message=error.message).model_dump(),
        ) from error
    except Exception as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=ErrorDetail(
                code="task_list_failed",
                message="Failed to load tasks.",
            ).model_dump(),
        ) from error

    return TaskListApiResponse(success=True, data=tasks, error=None)


@router.patch(
    "/{task_id}/progress",
    response_model=TaskItemApiResponse,
    summary="Update task progress",
    description="Persist elapsed seconds for an active task-backed quest.",
)
async def update_task_progress(
    task_id: UUID,
    payload: TaskProgressUpdateRequest,
    user_id: str = Depends(get_current_user_id),
    task_service: TaskService = Depends(get_task_service),
) -> TaskItemApiResponse:
    try:
        task = task_service.update_task_progress(
            user_id=user_id,
            task_id=str(task_id),
            elapsed_seconds=payload.elapsed_seconds,
        )
    except TaskServiceError as error:
        raise HTTPException(
            status_code=_TASK_ERROR_STATUSES.get(error.code, status.HTTP_400_BAD_REQUEST),
            detail=ErrorDetail(code=error.code, message=error.message).model_dump(),
        ) from error
    except Exception as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=ErrorDetail(
                code="task_progress_update_failed",
                message="Failed to update task progress.",
            ).model_dump(),
        ) from error

    return TaskItemApiResponse(success=True, data=task, error=None)


@router.post(
    "/{task_id}/complete",
    response_model=CompletedTaskApiResponse,
    summary="Complete task",
    description=(
        "Complete a committed task and apply the same reward, profile, and "
        "leaderboard progress updates used for quest completion."
    ),
)
async def complete_task(
    task_id: UUID,
    payload: QuestCompleteRequest,
    user_id: str = Depends(get_current_user_id),
    task_service: TaskService = Depends(get_task_service),
) -> CompletedTaskApiResponse:
    try:
        completed_record = task_service.complete_task(
            user_id=user_id,
            task_id=str(task_id),
            elapsed_seconds=payload.elapsedSeconds,
            proof_image_path=payload.proofImagePath,
        )
    except TaskServiceError as error:
        raise HTTPException(
            status_code=_TASK_ERROR_STATUSES.get(error.code, status.HTTP_400_BAD_REQUEST),
            detail=ErrorDetail(code=error.code, message=error.message).model_dump(),
        ) from error
    except Exception as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=ErrorDetail(
                code="task_complete_failed",
                message="Failed to complete the task.",
            ).model_dump(),
        ) from error

    return CompletedTaskApiResponse(success=True, data=completed_record, error=None)
