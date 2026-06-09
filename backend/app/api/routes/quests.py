from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, status

from app.api.dependencies import (
    get_current_user_id,
    get_quest_service,
)
from app.schemas.common import ApiResponse, EmptyPayload, ErrorDetail
from app.schemas.quest import (
    CompletedQuestRecordSchema,
    QuestCompleteRequest,
    QuestCreateRequest,
    QuestItemResponse,
    QuestUpdateRequest,
)
from app.schemas.quest_generation import (
    OCRTextQuestExtractionRequest,
    OCRTextQuestExtractionResponse,
    QuestGenerationRequest,
    QuestGenerationResponse,
)
from app.services.quest_generation_service import QuestGenerationService
from app.services.quest_service import (
    QuestNotFoundError,
    QuestOperationError,
    QuestService,
)
from app.services.quest_text_extraction_service import QuestTextExtractionService

router = APIRouter()
quest_generation_service = QuestGenerationService()
quest_text_extraction_service = QuestTextExtractionService()

QuestGenerationApiResponse = ApiResponse[QuestGenerationResponse]
OCRTextQuestExtractionApiResponse = ApiResponse[OCRTextQuestExtractionResponse]
QuestListApiResponse = ApiResponse[list[QuestItemResponse]]
QuestItemApiResponse = ApiResponse[QuestItemResponse]
CompletedQuestRecordApiResponse = ApiResponse[CompletedQuestRecordSchema]
EmptyApiResponse = ApiResponse[EmptyPayload]


@router.post(
    "/generate",
    response_model=QuestGenerationApiResponse,
    summary="Generate quest candidates",
    description=(
        "Generate quest candidates from a short prompt or source text. "
        "The route delegates generation to the service layer so provider logic "
        "can be swapped later without changing the API surface."
    ),
)
async def generate_quest(
    payload: QuestGenerationRequest,
) -> QuestGenerationApiResponse:
    try:
        result = quest_generation_service.generate(payload)
    except ValueError as error:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=ErrorDetail(
                code="invalid_quest_generation_request",
                message=str(error),
            ).model_dump(),
        ) from error
    except Exception as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=ErrorDetail(
                code="quest_generation_failed",
                message="Quest generation failed unexpectedly.",
            ).model_dump(),
        ) from error

    return QuestGenerationApiResponse(
        success=True,
        data=result,
        error=None,
    )


@router.post(
    "/from-text",
    response_model=OCRTextQuestExtractionApiResponse,
    summary="Extract quest candidates from OCR text",
    description=(
        "Normalize OCR text and extract predictable quest candidates on the server. "
        "This mirrors the current Flutter-side post-processing flow while keeping "
        "room for future server OCR or LLM-based refinement."
    ),
)
async def extract_quests_from_text(
    payload: OCRTextQuestExtractionRequest,
) -> OCRTextQuestExtractionApiResponse:
    try:
        result = quest_text_extraction_service.extract(payload.raw_text)
    except ValueError as error:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=ErrorDetail(
                code="invalid_ocr_text_extraction_request",
                message=str(error),
            ).model_dump(),
        ) from error
    except Exception as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=ErrorDetail(
                code="ocr_text_extraction_failed",
                message="OCR text extraction failed unexpectedly.",
            ).model_dump(),
        ) from error

    return OCRTextQuestExtractionApiResponse(
        success=True,
        data=result,
        error=None,
    )


@router.get(
    "",
    response_model=QuestListApiResponse,
    summary="List quests",
    description=(
        "Return active quests for the authenticated Supabase user."
    ),
)
async def list_quests(
    user_id: str = Depends(get_current_user_id),
    quest_service: QuestService = Depends(get_quest_service),
) -> QuestListApiResponse:
    try:
        quests = quest_service.list_quests(user_id)
    except QuestOperationError as error:
        raise _quest_http_exception(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            code=error.code,
            message=error.message,
        ) from error
    except Exception as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=ErrorDetail(
                code="quest_list_failed",
                message="Failed to load quests.",
            ).model_dump(),
        ) from error

    return QuestListApiResponse(success=True, data=quests, error=None)


@router.post(
    "",
    response_model=QuestItemApiResponse,
    summary="Create quest",
    description=(
        "Create an active quest for the current user in Supabase. "
        "The API stores the new quest under the authenticated Supabase user id."
    ),
    status_code=status.HTTP_201_CREATED,
)
async def create_quest(
    payload: QuestCreateRequest,
    user_id: str = Depends(get_current_user_id),
    quest_service: QuestService = Depends(get_quest_service),
) -> QuestItemApiResponse:
    try:
        created_quest = quest_service.create_quest(
            user_id,
            QuestItemResponse(
                id=f"quest-{uuid4()}",
                title=payload.title,
                exp=payload.exp,
                difficulty=payload.difficulty,
                category=payload.category,
                elapsedSeconds=0,
                defaultDurationSeconds=payload.defaultDurationSeconds,
                dueAt=payload.dueAt,
            ),
        )
    except QuestOperationError as error:
        raise _quest_http_exception(
            status_code=status.HTTP_400_BAD_REQUEST,
            code=error.code,
            message=error.message,
        ) from error
    except Exception as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=ErrorDetail(
                code="quest_create_failed",
                message="Failed to create the quest.",
            ).model_dump(),
        ) from error

    return QuestItemApiResponse(
        success=True,
        data=created_quest,
        error=None,
    )


@router.patch(
    "/{quest_id}",
    response_model=QuestItemApiResponse,
    summary="Update quest",
    description="Update an active quest for the current user in Supabase.",
)
async def update_quest(
    quest_id: str,
    payload: QuestUpdateRequest,
    user_id: str = Depends(get_current_user_id),
    quest_service: QuestService = Depends(get_quest_service),
) -> QuestItemApiResponse:
    try:
        updated_quest = quest_service.update_quest(
            user_id,
            quest_id,
            QuestItemResponse(
                id=quest_id,
                title=payload.title,
                exp=payload.exp,
                difficulty=payload.difficulty,
                category=payload.category,
                elapsedSeconds=payload.elapsedSeconds,
                defaultDurationSeconds=payload.defaultDurationSeconds,
                dueAt=payload.dueAt,
            ),
        )
    except QuestNotFoundError as error:
        raise _quest_http_exception(
            status_code=status.HTTP_404_NOT_FOUND,
            code=error.code,
            message=error.message,
        ) from error
    except QuestOperationError as error:
        raise _quest_http_exception(
            status_code=status.HTTP_400_BAD_REQUEST,
            code=error.code,
            message=error.message,
        ) from error
    except Exception as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=ErrorDetail(
                code="quest_update_failed",
                message="Failed to update the quest.",
            ).model_dump(),
        ) from error

    return QuestItemApiResponse(
        success=True,
        data=updated_quest,
        error=None,
    )


@router.delete(
    "/{quest_id}",
    response_model=EmptyApiResponse,
    summary="Delete quest",
    description="Delete an active quest for the current user in Supabase.",
)
async def delete_quest(
    quest_id: str,
    user_id: str = Depends(get_current_user_id),
    quest_service: QuestService = Depends(get_quest_service),
) -> EmptyApiResponse:
    try:
        quest_service.delete_quest(user_id, quest_id)
    except QuestNotFoundError as error:
        raise _quest_http_exception(
            status_code=status.HTTP_404_NOT_FOUND,
            code=error.code,
            message=error.message,
        ) from error
    except QuestOperationError as error:
        raise _quest_http_exception(
            status_code=status.HTTP_400_BAD_REQUEST,
            code=error.code,
            message=error.message,
        ) from error
    except Exception as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=ErrorDetail(
                code="quest_delete_failed",
                message="Failed to delete the quest.",
            ).model_dump(),
        ) from error

    return EmptyApiResponse(
        success=True,
        data=EmptyPayload(),
        error=None,
    )


@router.post(
    "/{quest_id}/undo-complete",
    response_model=QuestItemApiResponse,
    summary="Undo completed quest",
    description="Move a completed legacy quest back to active progress.",
)
async def undo_complete_quest(
    quest_id: str,
    user_id: str = Depends(get_current_user_id),
    quest_service: QuestService = Depends(get_quest_service),
) -> QuestItemApiResponse:
    try:
        quest = quest_service.undo_complete_quest(user_id, quest_id)
    except QuestNotFoundError as error:
        raise _quest_http_exception(
            status_code=status.HTTP_404_NOT_FOUND,
            code=error.code,
            message=error.message,
        ) from error
    except QuestOperationError as error:
        raise _quest_http_exception(
            status_code=status.HTTP_400_BAD_REQUEST,
            code=error.code,
            message=error.message,
        ) from error
    except Exception as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=ErrorDetail(
                code="quest_undo_complete_failed",
                message="Failed to undo quest completion.",
            ).model_dump(),
        ) from error

    return QuestItemApiResponse(success=True, data=quest, error=None)


@router.post(
    "/{quest_id}/complete",
    response_model=CompletedQuestRecordApiResponse,
    summary="Complete quest",
    description=(
        "Complete an active quest and update `completed_quests`, "
        "`recent_activities`, `user_stats`, and `users_profile`."
    ),
)
async def complete_quest(
    quest_id: str,
    payload: QuestCompleteRequest,
    user_id: str = Depends(get_current_user_id),
    quest_service: QuestService = Depends(get_quest_service),
) -> CompletedQuestRecordApiResponse:
    try:
        completed_record = quest_service.complete_quest(
            user_id,
            quest_id,
            elapsed_seconds=payload.elapsedSeconds,
            proof_image_path=payload.proofImagePath,
        )
    except QuestNotFoundError as error:
        raise _quest_http_exception(
            status_code=status.HTTP_404_NOT_FOUND,
            code=error.code,
            message=error.message,
        ) from error
    except QuestOperationError as error:
        raise _quest_http_exception(
            status_code=status.HTTP_400_BAD_REQUEST,
            code=error.code,
            message=error.message,
        ) from error
    except Exception as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=ErrorDetail(
                code="quest_complete_failed",
                message="Failed to complete the quest.",
            ).model_dump(),
        ) from error

    return CompletedQuestRecordApiResponse(
        success=True,
        data=completed_record,
        error=None,
    )


def _quest_http_exception(
    *,
    status_code: int,
    code: str,
    message: str,
) -> HTTPException:
    return HTTPException(
        status_code=status_code,
        detail=ErrorDetail(
            code=code,
            message=message,
        ).model_dump(),
    )
