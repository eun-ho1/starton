from app.providers.base import QuestGenerationProvider
from app.providers.rule_based_quest_generation import (
    RuleBasedQuestGenerationProvider,
)
from app.schemas.quest_generation import (
    OCRTextQuestExtractionRequest,
    OCRTextQuestExtractionResponse,
    QuestCandidateResponse,
    QuestGenerationRequest,
    QuestGenerationResponse,
)
from app.services.difficulty_rules import (
    duration_from_difficulty,
    exp_from_difficulty,
)

DEFAULT_MAX_ITEMS = 5


class QuestGenerationService:
    def __init__(
        self,
        provider: QuestGenerationProvider | None = None,
    ) -> None:
        self._provider = provider or RuleBasedQuestGenerationProvider()

    def generate(
        self,
        request: QuestGenerationRequest,
    ) -> QuestGenerationResponse:
        validated_request = self._normalize_generation_request(request)
        provider_response = self._provider.generate(validated_request)
        quests = [
            self._normalize_candidate(candidate)
            for candidate in provider_response.quests[
                : validated_request.max_items or DEFAULT_MAX_ITEMS
            ]
        ]
        return QuestGenerationResponse(quests=quests)

    def extract_from_text(
        self,
        request: OCRTextQuestExtractionRequest,
    ) -> OCRTextQuestExtractionResponse:
        provider_response = self._provider.extract_from_text(request)
        quests = [
            self._normalize_candidate(candidate)
            for candidate in provider_response.quests
        ]
        return OCRTextQuestExtractionResponse(
            quests=quests,
            cleaned_lines=provider_response.cleaned_lines,
            duplicate_removed_count=provider_response.duplicate_removed_count,
        )

    def _normalize_generation_request(
        self,
        request: QuestGenerationRequest,
    ) -> QuestGenerationRequest:
        normalized_prompt = request.prompt.strip() if request.prompt else None
        normalized_source_text = (
            request.source_text.strip() if request.source_text else None
        )
        normalized_max_items = request.max_items or DEFAULT_MAX_ITEMS

        return QuestGenerationRequest(
            prompt=normalized_prompt,
            source_text=normalized_source_text,
            difficulty=request.difficulty,
            category=request.category,
            max_items=normalized_max_items,
        )

    def _normalize_candidate(
        self,
        candidate: QuestCandidateResponse,
    ) -> QuestCandidateResponse:
        return QuestCandidateResponse(
            title=candidate.title.strip(),
            difficulty=candidate.difficulty,
            category=candidate.category,
            exp=exp_from_difficulty(candidate.difficulty),
            defaultDurationSeconds=duration_from_difficulty(
                candidate.difficulty,
            ),
            reason=candidate.reason,
            external_source=candidate.external_source,
            external_id=candidate.external_id,
            external_url=candidate.external_url,
            external_updated_at=candidate.external_updated_at,
        )
