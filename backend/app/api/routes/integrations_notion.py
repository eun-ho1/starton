import logging

from fastapi import APIRouter, Depends, HTTPException, status

from app.api.dependencies import get_current_user_id, get_notion_backend_service
from app.schemas.common import ApiResponse, EmptyPayload, ErrorDetail
from app.schemas.notion import (
    NotionConnectionStatusResponse,
    NotionConnectRequest,
    NotionConnectResponse,
    NotionSyncRequest,
    NotionSyncResponse,
)
from app.services.notion_backend_service import (
    NotionBackendService,
    map_connect_error_message,
    map_sync_error_message,
)
from app.services.notion_sync_service import IntegrationException

router = APIRouter()
logger = logging.getLogger(__name__)

NotionConnectApiResponse = ApiResponse[NotionConnectResponse]
NotionSyncApiResponse = ApiResponse[NotionSyncResponse]
NotionStatusApiResponse = ApiResponse[NotionConnectionStatusResponse]
EmptyApiResponse = ApiResponse[EmptyPayload]


@router.post(
    "/integrations/notion/connect",
    response_model=NotionConnectApiResponse,
    summary="Connect a user's Notion integration",
    description=(
        "Stores an encrypted Notion token and the selected database or data source "
        "for later server-side sync."
    ),
)
async def connect_notion(
    payload: NotionConnectRequest,
    user_id: str = Depends(get_current_user_id),
    notion_service: NotionBackendService = Depends(get_notion_backend_service),
) -> NotionConnectApiResponse:
    try:
        result = notion_service.connect(user_id, payload)
    except IntegrationException as error:
        logger.exception("Notion connect request failed for user_id=%s", user_id)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=ErrorDetail(
                code="notion_connection_failed",
                message=map_connect_error_message(str(error)),
            ).model_dump(),
        ) from error
    except Exception as error:
        logger.exception("Unexpected Notion connect error for user_id=%s", user_id)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=ErrorDetail(
                code="notion_connection_failed",
                message="Notion connection failed unexpectedly.",
            ).model_dump(),
        ) from error
    return NotionConnectApiResponse(success=True, data=result, error=None)


@router.post(
    "/integrations/notion/sync",
    response_model=NotionSyncApiResponse,
    summary="Sync quests from a saved Notion connection",
    description=(
        "Uses the saved Notion connection to fetch incomplete pages and upsert them "
        "into Supabase quests."
    ),
)
async def sync_notion_database(
    payload: NotionSyncRequest,
    user_id: str = Depends(get_current_user_id),
    notion_service: NotionBackendService = Depends(get_notion_backend_service),
) -> NotionSyncApiResponse:
    try:
        result = notion_service.sync(user_id, payload)
    except IntegrationException as error:
        logger.exception("Notion sync request failed for user_id=%s", user_id)
        error_message = str(error)
        is_disconnect_race = "disconnected" in error_message.lower()
        raise HTTPException(
            status_code=(
                status.HTTP_409_CONFLICT
                if is_disconnect_race
                else status.HTTP_400_BAD_REQUEST
            ),
            detail=ErrorDetail(
                code=(
                    "notion_sync_cancelled"
                    if is_disconnect_race
                    else "notion_integration_failed"
                ),
                message=error_message,
            ).model_dump(),
        ) from error
    except Exception as error:
        logger.exception("Unexpected Notion sync error for user_id=%s", user_id)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=ErrorDetail(
                code="notion_sync_failed",
                message=map_sync_error_message(str(error)),
            ).model_dump(),
        ) from error

    return NotionSyncApiResponse(success=True, data=result, error=None)


@router.get(
    "/integrations/notion/status",
    response_model=NotionStatusApiResponse,
    summary="Get the current user's Notion connection status",
    description=(
        "Returns the latest saved Notion connection status for the authenticated user "
        "without exposing any secret or token values."
    ),
)
async def get_notion_status(
    user_id: str = Depends(get_current_user_id),
    notion_service: NotionBackendService = Depends(get_notion_backend_service),
) -> NotionStatusApiResponse:
    try:
        result = notion_service.get_status(user_id)
    except Exception as error:
        logger.exception("Notion status lookup failed for user_id=%s", user_id)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=ErrorDetail(
                code="notion_status_failed",
                message="Notion status lookup failed unexpectedly.",
            ).model_dump(),
        ) from error
    return NotionStatusApiResponse(success=True, data=result, error=None)


@router.delete(
    "/integrations/notion/connection",
    response_model=EmptyApiResponse,
    summary="Disconnect the current user's Notion connection",
    description=(
        "Marks the latest saved Notion connection as disconnected without deleting "
        "previously imported quests."
    ),
)
async def disconnect_notion(
    user_id: str = Depends(get_current_user_id),
    notion_service: NotionBackendService = Depends(get_notion_backend_service),
) -> EmptyApiResponse:
    try:
        notion_service.disconnect(user_id)
    except Exception as error:
        logger.exception("Notion disconnect failed for user_id=%s", user_id)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=ErrorDetail(
                code="notion_disconnect_failed",
                message="Notion disconnect failed unexpectedly.",
            ).model_dump(),
        ) from error
    return EmptyApiResponse(success=True, data=EmptyPayload(), error=None)
