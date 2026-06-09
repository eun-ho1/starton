from typing import Any

from pydantic import BaseModel

from app.repositories.mediator_run_repository import (
    MediatorRunRecord,
    SupabaseMediatorRunRepository,
)
from app.repositories.raw_input_repository import (
    RawTaskInputRecord,
    SupabaseRawInputRepository,
)
from app.repositories.task_candidate_repository import SupabaseTaskCandidateRepository
from app.providers.gemini_provider import GeminiMediatorResult, GeminiProvider
from app.schemas.mediator import MediatorOutput
from app.schemas.task_candidate import TaskCandidateResponse
from app.schemas.task_intake import RawTaskInputStatus, UserContext
from app.services.subtask_time_allocation import (
    apply_time_allocation,
    resolve_time_allocation,
)
from app.services.today_planning_service import (
    DEFAULT_TIMEZONE,
    TodayContext,
    TodayPlanningService,
)
from app.services.fallback_mediator_service import FallbackMediatorService
from app.services.user_task_pattern_service import UserTaskPatternService


class MediatorService:
    def __init__(
        self,
        *,
        raw_input_repository: SupabaseRawInputRepository,
        mediator_run_repository: SupabaseMediatorRunRepository,
        task_candidate_repository: SupabaseTaskCandidateRepository,
        gemini_provider: GeminiProvider,
        today_planning_service: TodayPlanningService,
        fallback_mediator_service: FallbackMediatorService,
        user_task_pattern_service: UserTaskPatternService,
    ) -> None:
        self._raw_input_repository = raw_input_repository
        self._mediator_run_repository = mediator_run_repository
        self._task_candidate_repository = task_candidate_repository
        self._gemini_provider = gemini_provider
        self._today_planning_service = today_planning_service
        self._fallback_mediator_service = fallback_mediator_service
        self._user_task_pattern_service = user_task_pattern_service

    def create_candidate(
        self,
        *,
        user_id: str,
        raw_input_id: str,
        client_timezone: str | None = None,
        user_context: UserContext | dict[str, Any] | None = None,
        profile_id: str | None = None,
    ) -> TaskCandidateResponse:
        raw_input = self._raw_input_repository.get(
            user_id=user_id,
            raw_input_id=raw_input_id,
        )
        resolved_profile_id = profile_id or raw_input.profile_id
        resolved_timezone = _resolve_client_timezone(
            client_timezone,
            raw_input.client_timezone,
        )
        normalized_user_context = _compact_user_context(_context_dict(user_context))
        existing_tasks: list[dict[str, Any]] = []
        user_patterns: dict[str, Any] = {}
        run: MediatorRunRecord | None = None
        raw_model_output: dict[str, Any] | None = None

        try:
            self._raw_input_repository.update_status(
                user_id=user_id,
                raw_input_id=raw_input.id,
                status=RawTaskInputStatus.PROCESSING,
            )
            today_context = self._today_planning_service.get_today_context(
                user_id=user_id,
                timezone=resolved_timezone,
            )
            compact_today_context = _compact_today_context(today_context)
            existing_tasks, user_patterns = _pattern_prompt_context(
                self._user_task_pattern_service,
                user_id=user_id,
            )
            model_context = _build_model_context(
                raw_input=raw_input,
                client_timezone=resolved_timezone,
                user_context=normalized_user_context,
                today_context=compact_today_context,
                user_patterns=user_patterns,
                time_allocation=resolve_time_allocation(raw_input.client_metadata),
            )
            run = self._mediator_run_repository.start(
                user_id=user_id,
                profile_id=resolved_profile_id,
                raw_input_id=raw_input.id,
                model_name=_provider_model_name(self._gemini_provider),
                input_context=model_context,
            )
            try:
                mediator_result = self._gemini_provider.generate_mediator_result(
                    raw_text=raw_input.raw_text,
                    source=raw_input.source,
                    user_context=normalized_user_context,
                    today_context=compact_today_context,
                    existing_tasks=existing_tasks,
                    user_patterns=user_patterns,
                )
                mediator_output = mediator_result.output
                raw_model_output = _raw_model_output(mediator_result)
            except Exception as error:
                if not _is_transient_ai_error(error):
                    raise
                mediator_output = self._fallback_mediator_service.create_output(
                    raw_text=raw_input.raw_text,
                    user_context=normalized_user_context,
                    today_context=compact_today_context,
                    client_metadata=raw_input.client_metadata,
                    user_patterns=user_patterns,
                )
                raw_model_output = _fallback_model_output(
                    provider=self._gemini_provider,
                    error=error,
                    output=mediator_output,
                )

            mediator_output = apply_time_allocation(
                mediator_output,
                client_metadata=raw_input.client_metadata,
            )
            guarded_output = self._today_planning_service.apply_capacity_guard(
                output=mediator_output,
                today_context=today_context,
            )
            candidate = self._task_candidate_repository.create_from_mediator_output(
                user_id=user_id,
                profile_id=resolved_profile_id,
                raw_input_id=raw_input.id,
                mediator_run_id=run.id,
                output=guarded_output,
            )
            self._mediator_run_repository.mark_succeeded(
                user_id=user_id,
                run_id=run.id,
                raw_model_output=raw_model_output or _parsed_output(guarded_output),
                parsed_output=_parsed_output(guarded_output),
            )
            self._raw_input_repository.update_status(
                user_id=user_id,
                raw_input_id=raw_input.id,
                status=RawTaskInputStatus.CANDIDATE_READY,
            )
            return candidate
        except Exception as error:
            error_message = _error_message(error)
            if run is not None:
                _try_mark_run_failed(
                    mediator_run_repository=self._mediator_run_repository,
                    user_id=user_id,
                    run_id=run.id,
                    error_message=error_message,
                )
            _try_mark_raw_input_failed(
                raw_input_repository=self._raw_input_repository,
                user_id=user_id,
                raw_input_id=raw_input.id,
                error_message=error_message,
            )
            raise


def _resolve_client_timezone(
    requested_timezone: str | None,
    stored_timezone: str | None,
) -> str:
    return (
        (requested_timezone or "").strip()
        or (stored_timezone or "").strip()
        or DEFAULT_TIMEZONE
    )


def _context_dict(value: UserContext | dict[str, Any] | None) -> dict[str, Any]:
    if value is None:
        return {}
    if isinstance(value, BaseModel):
        return value.model_dump(mode="json")
    return dict(value)


def _compact_user_context(value: dict[str, Any]) -> dict[str, Any]:
    compact: dict[str, Any] = {}
    energy_now = value.get("energy_now")
    if isinstance(energy_now, str) and energy_now.strip():
        compact["energy_now"] = energy_now.strip()
    available_minutes_today = value.get("available_minutes_today")
    if isinstance(available_minutes_today, int) and available_minutes_today > 0:
        compact["available_minutes_today"] = available_minutes_today
    extra = value.get("extra")
    if isinstance(extra, dict) and extra:
        compact["extra"] = extra
    return compact


def _compact_today_context(today_context: TodayContext) -> dict[str, Any]:
    compact: dict[str, Any] = {}
    if today_context.today_task_count > 0:
        compact["today_task_count"] = today_context.today_task_count
    if today_context.today_estimated_minutes > 0:
        compact["today_estimated_minutes"] = today_context.today_estimated_minutes
    return compact


def _build_model_context(
    *,
    raw_input: RawTaskInputRecord,
    client_timezone: str,
    user_context: dict[str, Any],
    today_context: dict[str, Any],
    user_patterns: dict[str, Any],
    time_allocation: str | None,
) -> dict[str, Any]:
    context = {
        "raw_input_id": raw_input.id,
        "raw_text": raw_input.raw_text,
        "source": raw_input.source,
        "client_timezone": client_timezone,
        "user_context": user_context,
        "today_context": today_context,
        "user_patterns": user_patterns,
        "client_metadata": raw_input.client_metadata,
    }
    if time_allocation is not None:
        context["time_allocation"] = time_allocation
    return context


def _provider_model_name(provider: GeminiProvider) -> str:
    return str(getattr(provider, "_model_name", "unknown"))


def _raw_model_output(result: GeminiMediatorResult) -> dict[str, Any]:
    return {
        "model_name": result.model_name,
        "prompt_version": result.prompt_version,
        "raw_text": result.raw_text,
        "parsed": result.parsed,
        "rendered_prompt": result.rendered_prompt,
    }


def _fallback_model_output(
    *,
    provider: GeminiProvider,
    error: Exception,
    output: MediatorOutput,
) -> dict[str, Any]:
    return {
        "model_name": _provider_model_name(provider),
        "prompt_version": "fallback_mediator_v1",
        "fallback_used": True,
        "fallback_reason": str(error).strip() or error.__class__.__name__,
        "parsed": output.model_dump(mode="json"),
    }


def _parsed_output(output: MediatorOutput) -> dict[str, Any]:
    return output.model_dump(mode="json")


def _try_mark_run_failed(
    *,
    mediator_run_repository: SupabaseMediatorRunRepository,
    user_id: str,
    run_id: str,
    error_message: str,
) -> None:
    try:
        mediator_run_repository.mark_failed(
            user_id=user_id,
            run_id=run_id,
            error_message=error_message,
        )
    except Exception:
        return


def _try_mark_raw_input_failed(
    *,
    raw_input_repository: SupabaseRawInputRepository,
    user_id: str,
    raw_input_id: str,
    error_message: str,
) -> None:
    try:
        raw_input_repository.update_status(
            user_id=user_id,
            raw_input_id=raw_input_id,
            status=RawTaskInputStatus.FAILED,
            error_message=error_message,
        )
    except Exception:
        return


def _error_message(error: Exception) -> str:
    return str(error).strip() or error.__class__.__name__


def _pattern_prompt_context(
    user_task_pattern_service: UserTaskPatternService,
    *,
    user_id: str,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    try:
        analysis = user_task_pattern_service.analyze(user_id=user_id)
    except Exception:
        return [], {}
    if not analysis.data_sufficient:
        return [], {}
    return analysis.existing_tasks, analysis.prompt_payload


def _is_transient_ai_error(error: Exception) -> bool:
    message = str(error).lower().strip()
    if not message:
        return False
    return any(
        token in message
        for token in (
            "503",
            "unavailable",
            "resource_exhausted",
            "rate limit",
            "too many requests",
            "deadline exceeded",
            "timeout",
            "timed out",
        )
    )
