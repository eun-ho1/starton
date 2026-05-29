import httpx
from fastapi import APIRouter, HTTPException, status

from app.core.config import settings
from app.schemas.auth import (
    AuthEmailPasswordRequest,
    AuthRefreshRequest,
    AuthSessionResponse,
    AuthUserResponse,
)
from app.schemas.common import ApiResponse, ErrorDetail


router = APIRouter(prefix="/auth")

AuthSessionApiResponse = ApiResponse[AuthSessionResponse]


@router.post(
    "/sign-in",
    response_model=AuthSessionApiResponse,
    summary="Sign in with Supabase email/password",
)
async def sign_in(
    payload: AuthEmailPasswordRequest,
) -> AuthSessionApiResponse:
    data = await _call_supabase_auth(
        path="/auth/v1/token?grant_type=password",
        body={
            "email": payload.email,
            "password": payload.password,
        },
    )
    return AuthSessionApiResponse(
        success=True,
        data=_build_session_response(data),
        error=None,
    )


@router.post(
    "/refresh",
    response_model=AuthSessionApiResponse,
    summary="Refresh a Supabase access token using refresh token",
)
async def refresh_session(
    payload: AuthRefreshRequest,
) -> AuthSessionApiResponse:
    data = await _call_supabase_auth(
        path="/auth/v1/token?grant_type=refresh_token",
        body={
            "refresh_token": payload.refreshToken,
        },
    )
    return AuthSessionApiResponse(
        success=True,
        data=_build_session_response(data),
        error=None,
    )


@router.post(
    "/sign-up",
    response_model=AuthSessionApiResponse,
    summary="Sign up with Supabase email/password",
)
async def sign_up(
    payload: AuthEmailPasswordRequest,
) -> AuthSessionApiResponse:
    data = await _call_supabase_auth(
        path="/auth/v1/signup",
        body={
            "email": payload.email,
            "password": payload.password,
        },
    )
    session = _build_session_response(data)
    if not session.accessToken:
        raise _auth_http_exception(
            status_code=status.HTTP_400_BAD_REQUEST,
            code="signup_requires_confirmation",
            message="Sign-up succeeded, but no active session was returned. Check your email confirmation settings.",
        )
    return AuthSessionApiResponse(success=True, data=session, error=None)


async def _call_supabase_auth(
    *,
    path: str,
    body: dict[str, object],
) -> dict[str, object]:
    base_url = settings.supabase_url.rstrip("/")
    url = f"{base_url}{path}"
    headers = {
        "apikey": settings.supabase_service_role_key,
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
        "Content-Type": "application/json",
    }

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.post(url, headers=headers, json=body)
    except httpx.HTTPError as error:
        raise _auth_http_exception(
            status_code=status.HTTP_502_BAD_GATEWAY,
            code="supabase_auth_network_error",
            message="Failed to reach Supabase Auth.",
        ) from error

    try:
        data = response.json()
    except ValueError as error:
        raise _auth_http_exception(
            status_code=status.HTTP_502_BAD_GATEWAY,
            code="supabase_auth_invalid_response",
            message="Supabase Auth returned invalid JSON.",
        ) from error

    if response.status_code >= 400:
        message = (
            data.get("msg")
            or data.get("message")
            or data.get("error_description")
            or "Supabase Auth request failed."
        )
        is_rate_limited = response.status_code == status.HTTP_429_TOO_MANY_REQUESTS
        raise _auth_http_exception(
            status_code=(
                status.HTTP_429_TOO_MANY_REQUESTS
                if is_rate_limited
                else status.HTTP_400_BAD_REQUEST
            ),
            code=(
                "supabase_auth_rate_limited"
                if is_rate_limited
                else "supabase_auth_failed"
            ),
            message=str(message),
        )

    return data


def _build_session_response(data: dict[str, object]) -> AuthSessionResponse:
    user = _extract_auth_user(data)
    if not isinstance(user, dict):
        raise _auth_http_exception(
            status_code=status.HTTP_502_BAD_GATEWAY,
            code="supabase_auth_invalid_user",
            message="Supabase Auth response did not include a user.",
        )

    access_token = data.get("access_token")
    if access_token is None:
        access_token = ""

    return AuthSessionResponse(
        accessToken=str(access_token),
        refreshToken=(
            str(data["refresh_token"])
            if data.get("refresh_token") is not None
            else None
        ),
        user=AuthUserResponse(
            id=str(user.get("id", "")),
            email=user.get("email") if isinstance(user.get("email"), str) else None,
        ),
    )


def _extract_auth_user(data: dict[str, object]) -> dict[str, object] | None:
    user = data.get("user")
    if isinstance(user, dict):
        return user

    # Supabase sign-up can return the created user as the top-level response
    # when email confirmation is required and no session is issued.
    if isinstance(data.get("id"), str):
        return data

    return None


def _auth_http_exception(
    *,
    status_code: int,
    code: str,
    message: str,
) -> HTTPException:
    return HTTPException(
        status_code=status_code,
        detail=ErrorDetail(code=code, message=message).model_dump(),
    )
