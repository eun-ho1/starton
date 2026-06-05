import unittest

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api.routes import task_candidates as task_candidates_route
from app.schemas.reminder import ReminderType
from app.schemas.task import TaskCommitResult, TaskResponse
from app.schemas.task_candidate import (
    CandidateReminderResponse,
    CandidateSubtaskResponse,
    TaskCandidateResponse,
    TaskCandidateStatus,
    TaskDifficulty,
    TaskEnergyRequired,
    TaskPriority,
)


USER_ID = "00000000-0000-4000-8000-000000000001"
RAW_INPUT_ID = "00000000-0000-4000-8000-000000000003"
CANDIDATE_ID = "00000000-0000-4000-8000-000000000004"
MEDIATOR_RUN_ID = "00000000-0000-4000-8000-000000000005"
SUBTASK_ID = "00000000-0000-4000-8000-000000000006"
REMINDER_ID = "00000000-0000-4000-8000-000000000007"
TASK_ID = "00000000-0000-4000-8000-000000000008"


def make_candidate_response() -> TaskCandidateResponse:
    return TaskCandidateResponse(
        id=CANDIDATE_ID,
        user_id=USER_ID,
        raw_input_id=RAW_INPUT_ID,
        mediator_run_id=MEDIATOR_RUN_ID,
        title="컴퓨터비전 과제 제출 준비",
        description="요구사항 확인부터 시작하는 후보입니다.",
        due_at=None,
        priority=TaskPriority.HIGH,
        estimated_minutes=120,
        energy_required=TaskEnergyRequired.HIGH,
        difficulty=TaskDifficulty.HIGH,
        next_action="과제 파일을 열고 요구사항 제목만 확인하기",
        recommended_today=True,
        today_reason="오늘은 시작 단계만 진행하는 것이 현실적입니다.",
        overload_warning=None,
        confidence=0.78,
        status=TaskCandidateStatus.DRAFT,
        model_payload={"source": "test"},
        subtasks=[
            CandidateSubtaskResponse(
                id=SUBTASK_ID,
                candidate_id=CANDIDATE_ID,
                title="과제 파일 열기",
                order_index=0,
                estimated_minutes=5,
                is_next_action=True,
                energy_required=TaskEnergyRequired.LOW,
            )
        ],
        reminders=[
            CandidateReminderResponse(
                id=REMINDER_ID,
                candidate_id=CANDIDATE_ID,
                remind_at=None,
                message="딱 5분만 과제 파일 열기",
                type=ReminderType.START,
                escalation_level=0,
            )
        ],
    )


class FakeTaskCandidateRepository:
    def __init__(self, *, error: Exception | None = None) -> None:
        self.error = error
        self.get_calls: list[dict[str, str]] = []

    def get(self, *, user_id: str, candidate_id: str) -> TaskCandidateResponse:
        self.get_calls.append({"user_id": user_id, "candidate_id": candidate_id})
        if self.error is not None:
            raise self.error
        return make_candidate_response()


class FakeTaskCommitService:
    def __init__(self, *, error: Exception | None = None) -> None:
        self.error = error
        self.calls: list[dict[str, object]] = []

    def commit_candidate(
        self,
        *,
        user_id: str,
        candidate_id: str,
        accepted: bool,
        edited_fields: dict[str, object],
        selected_subtask_ids: list[object] | None,
        selected_reminder_ids: list[object] | None,
    ) -> TaskCommitResult:
        self.calls.append(
            {
                "user_id": user_id,
                "candidate_id": candidate_id,
                "accepted": accepted,
                "edited_fields": edited_fields,
                "selected_subtask_ids": selected_subtask_ids,
                "selected_reminder_ids": selected_reminder_ids,
            }
        )
        if self.error is not None:
            raise self.error
        return TaskCommitResult(
            candidate_id=CANDIDATE_ID,
            task=TaskResponse(
                id=TASK_ID,
                user_id=USER_ID,
                candidate_id=CANDIDATE_ID,
                raw_input_id=RAW_INPUT_ID,
                mediator_run_id=MEDIATOR_RUN_ID,
                title=edited_fields.get("title", "컴퓨터비전 과제 제출 준비"),
                priority=TaskPriority.HIGH,
                estimated_minutes=edited_fields.get("estimated_minutes", 120),
                next_action="과제 파일을 열고 요구사항 제목만 확인하기",
            ),
        )


class FakeTaskCandidateReviewService:
    def __init__(self, *, error: Exception | None = None) -> None:
        self.error = error
        self.revise_calls: list[dict[str, object]] = []
        self.reject_calls: list[dict[str, object]] = []

    def revise_candidate(
        self,
        *,
        user_id: str,
        candidate_id: str,
        revision_type: object,
        edited_fields: dict[str, object],
        note: str | None,
    ) -> TaskCandidateResponse:
        self.revise_calls.append(
            {
                "user_id": user_id,
                "candidate_id": candidate_id,
                "revision_type": revision_type,
                "edited_fields": edited_fields,
                "note": note,
            }
        )
        if self.error is not None:
            raise self.error
        return make_candidate_response().model_copy(
            update={
                **edited_fields,
                "status": TaskCandidateStatus.EDITED,
            }
        )

    def reject_candidate(
        self,
        *,
        user_id: str,
        candidate_id: str,
        reason: str | None,
    ) -> TaskCandidateResponse:
        self.reject_calls.append(
            {
                "user_id": user_id,
                "candidate_id": candidate_id,
                "reason": reason,
            }
        )
        if self.error is not None:
            raise self.error
        return make_candidate_response().model_copy(
            update={"status": TaskCandidateStatus.REJECTED}
        )


class TaskCandidateRouteTest(unittest.TestCase):
    def make_client(
        self,
        repository: FakeTaskCandidateRepository,
        commit_service: FakeTaskCommitService | None = None,
        review_service: FakeTaskCandidateReviewService | None = None,
        *,
        override_user: bool = True,
    ) -> TestClient:
        app = FastAPI()
        app.include_router(
            task_candidates_route.router,
            prefix="/api/v1/task-candidates",
        )
        if override_user:
            app.dependency_overrides[
                task_candidates_route.get_current_user_id
            ] = lambda: USER_ID
        app.dependency_overrides[
            task_candidates_route.get_task_candidate_repository
        ] = lambda: repository
        if commit_service is not None:
            app.dependency_overrides[
                task_candidates_route.get_task_commit_service
            ] = lambda: commit_service
        if review_service is not None:
            app.dependency_overrides[
                task_candidates_route.get_task_candidate_review_service
            ] = lambda: review_service
        return TestClient(app)

    def test_get_task_candidate_returns_candidate_envelope(self) -> None:
        repository = FakeTaskCandidateRepository()
        client = self.make_client(repository)

        response = client.get(f"/api/v1/task-candidates/{CANDIDATE_ID}")

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["success"], True)
        self.assertIsNone(payload["error"])
        self.assertEqual(payload["data"]["id"], CANDIDATE_ID)
        self.assertEqual(payload["data"]["title"], "컴퓨터비전 과제 제출 준비")
        self.assertEqual(payload["data"]["subtasks"][0]["title"], "과제 파일 열기")
        self.assertEqual(
            payload["data"]["reminders"][0]["message"],
            "딱 5분만 과제 파일 열기",
        )
        self.assertEqual(
            repository.get_calls,
            [{"user_id": USER_ID, "candidate_id": CANDIDATE_ID}],
        )

    def test_get_task_candidate_maps_missing_candidate_to_404(self) -> None:
        repository = FakeTaskCandidateRepository(error=ValueError("not found"))
        client = self.make_client(repository)

        response = client.get(f"/api/v1/task-candidates/{CANDIDATE_ID}")

        self.assertEqual(response.status_code, 404)
        detail = response.json()["detail"]
        self.assertEqual(detail["code"], "task_candidate_not_found")
        self.assertEqual(detail["message"], "Task candidate was not found.")

    def test_get_task_candidate_maps_unexpected_error_to_500(self) -> None:
        repository = FakeTaskCandidateRepository(
            error=RuntimeError("database unavailable"),
        )
        client = self.make_client(repository)

        response = client.get(f"/api/v1/task-candidates/{CANDIDATE_ID}")

        self.assertEqual(response.status_code, 500)
        detail = response.json()["detail"]
        self.assertEqual(detail["code"], "task_candidate_lookup_failed")
        self.assertEqual(detail["message"], "Task candidate lookup failed unexpectedly.")

    def test_get_task_candidate_requires_authorization(self) -> None:
        repository = FakeTaskCandidateRepository()
        client = self.make_client(repository, override_user=False)

        response = client.get(f"/api/v1/task-candidates/{CANDIDATE_ID}")

        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json()["detail"]["code"], "missing_authorization")
        self.assertEqual(repository.get_calls, [])

    def test_confirm_task_candidate_returns_committed_task_envelope(self) -> None:
        repository = FakeTaskCandidateRepository()
        commit_service = FakeTaskCommitService()
        client = self.make_client(repository, commit_service)

        response = client.post(
            f"/api/v1/task-candidates/{CANDIDATE_ID}/confirm",
            json={
                "accepted": True,
                "edited_fields": {
                    "title": "컴비전 과제 1차 진행",
                    "estimated_minutes": 90,
                },
                "selected_subtask_ids": [SUBTASK_ID],
                "selected_reminder_ids": [REMINDER_ID],
            },
        )

        self.assertEqual(response.status_code, 201)
        payload = response.json()
        self.assertEqual(payload["success"], True)
        self.assertIsNone(payload["error"])
        self.assertEqual(payload["data"]["candidate_id"], CANDIDATE_ID)
        self.assertEqual(payload["data"]["task"]["id"], TASK_ID)
        self.assertEqual(payload["data"]["task"]["title"], "컴비전 과제 1차 진행")
        self.assertEqual(payload["data"]["task"]["estimated_minutes"], 90)
        self.assertEqual(len(commit_service.calls), 1)
        call = commit_service.calls[0]
        self.assertEqual(call["user_id"], USER_ID)
        self.assertEqual(call["candidate_id"], CANDIDATE_ID)
        self.assertEqual(call["accepted"], True)
        self.assertEqual(
            call["edited_fields"],
            {"title": "컴비전 과제 1차 진행", "estimated_minutes": 90},
        )
        self.assertEqual(
            [str(item) for item in call["selected_subtask_ids"]],
            [SUBTASK_ID],
        )
        self.assertEqual(
            [str(item) for item in call["selected_reminder_ids"]],
            [REMINDER_ID],
        )
        self.assertEqual(repository.get_calls, [])

    def test_confirm_task_candidate_preserves_omitted_selection_as_none(self) -> None:
        repository = FakeTaskCandidateRepository()
        commit_service = FakeTaskCommitService()
        client = self.make_client(repository, commit_service)

        response = client.post(
            f"/api/v1/task-candidates/{CANDIDATE_ID}/confirm",
            json={"edited_fields": {}},
        )

        self.assertEqual(response.status_code, 201)
        call = commit_service.calls[0]
        self.assertEqual(call["accepted"], True)
        self.assertEqual(call["edited_fields"], {})
        self.assertIsNone(call["selected_subtask_ids"])
        self.assertIsNone(call["selected_reminder_ids"])

    def test_confirm_task_candidate_requires_authorization(self) -> None:
        repository = FakeTaskCandidateRepository()
        commit_service = FakeTaskCommitService()
        client = self.make_client(
            repository,
            commit_service,
            override_user=False,
        )

        response = client.post(
            f"/api/v1/task-candidates/{CANDIDATE_ID}/confirm",
            json={"accepted": True},
        )

        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json()["detail"]["code"], "missing_authorization")
        self.assertEqual(commit_service.calls, [])

    def test_confirm_task_candidate_maps_commit_errors(self) -> None:
        cases = [
            ("candidate_not_found", 404),
            ("invalid_edited_fields", 400),
            ("invalid_subtask_selection", 400),
            ("invalid_reminder_selection", 400),
            ("candidate_already_committed", 409),
            ("candidate_not_committable", 409),
            ("task_storage_unavailable", 503),
        ]

        for code, expected_status in cases:
            with self.subTest(code=code):
                repository = FakeTaskCandidateRepository()
                commit_service = FakeTaskCommitService(
                    error=task_candidates_route.TaskCommitError(
                        code,
                        f"{code} message",
                    )
                )
                client = self.make_client(repository, commit_service)

                response = client.post(
                    f"/api/v1/task-candidates/{CANDIDATE_ID}/confirm",
                    json={"accepted": True},
                )

                self.assertEqual(response.status_code, expected_status)
                detail = response.json()["detail"]
                self.assertEqual(detail["code"], code)
                self.assertEqual(detail["message"], f"{code} message")

    def test_confirm_task_candidate_maps_unexpected_error_to_500(self) -> None:
        repository = FakeTaskCandidateRepository()
        commit_service = FakeTaskCommitService(error=RuntimeError("database down"))
        client = self.make_client(repository, commit_service)

        response = client.post(
            f"/api/v1/task-candidates/{CANDIDATE_ID}/confirm",
            json={"accepted": True},
        )

        self.assertEqual(response.status_code, 500)
        detail = response.json()["detail"]
        self.assertEqual(detail["code"], "task_candidate_confirm_failed")
        self.assertEqual(
            detail["message"],
            "Task candidate confirmation failed unexpectedly.",
        )

    def test_revise_task_candidate_returns_candidate_envelope(self) -> None:
        repository = FakeTaskCandidateRepository()
        review_service = FakeTaskCandidateReviewService()
        client = self.make_client(repository, review_service=review_service)

        response = client.post(
            f"/api/v1/task-candidates/{CANDIDATE_ID}/revise",
            json={
                "revision_type": "manual_edit",
                "edited_fields": {
                    "title": "컴비전 과제 1차 진행",
                    "estimated_minutes": 45,
                },
                "note": "오늘 가능한 크기로 줄임",
            },
        )

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["success"], True)
        self.assertIsNone(payload["error"])
        self.assertEqual(payload["data"]["id"], CANDIDATE_ID)
        self.assertEqual(payload["data"]["status"], "edited")
        self.assertEqual(payload["data"]["title"], "컴비전 과제 1차 진행")
        self.assertEqual(len(review_service.revise_calls), 1)
        call = review_service.revise_calls[0]
        self.assertEqual(call["user_id"], USER_ID)
        self.assertEqual(call["candidate_id"], CANDIDATE_ID)
        self.assertEqual(str(call["revision_type"]), "manual_edit")
        self.assertEqual(
            call["edited_fields"],
            {"title": "컴비전 과제 1차 진행", "estimated_minutes": 45},
        )
        self.assertEqual(call["note"], "오늘 가능한 크기로 줄임")

    def test_reject_task_candidate_returns_candidate_envelope(self) -> None:
        repository = FakeTaskCandidateRepository()
        review_service = FakeTaskCandidateReviewService()
        client = self.make_client(repository, review_service=review_service)

        response = client.post(
            f"/api/v1/task-candidates/{CANDIDATE_ID}/reject",
            json={"reason": "지금 저장할 일이 아님"},
        )

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["success"], True)
        self.assertIsNone(payload["error"])
        self.assertEqual(payload["data"]["id"], CANDIDATE_ID)
        self.assertEqual(payload["data"]["status"], "rejected")
        self.assertEqual(
            review_service.reject_calls,
            [
                {
                    "user_id": USER_ID,
                    "candidate_id": CANDIDATE_ID,
                    "reason": "지금 저장할 일이 아님",
                }
            ],
        )

    def test_revise_task_candidate_requires_authorization(self) -> None:
        repository = FakeTaskCandidateRepository()
        review_service = FakeTaskCandidateReviewService()
        client = self.make_client(
            repository,
            review_service=review_service,
            override_user=False,
        )

        response = client.post(
            f"/api/v1/task-candidates/{CANDIDATE_ID}/revise",
            json={"revision_type": "make_smaller", "note": "더 작게"},
        )

        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json()["detail"]["code"], "missing_authorization")
        self.assertEqual(review_service.revise_calls, [])

    def test_reject_task_candidate_requires_authorization(self) -> None:
        repository = FakeTaskCandidateRepository()
        review_service = FakeTaskCandidateReviewService()
        client = self.make_client(
            repository,
            review_service=review_service,
            override_user=False,
        )

        response = client.post(
            f"/api/v1/task-candidates/{CANDIDATE_ID}/reject",
            json={"reason": "취소"},
        )

        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json()["detail"]["code"], "missing_authorization")
        self.assertEqual(review_service.reject_calls, [])

    def test_revise_task_candidate_maps_review_errors(self) -> None:
        cases = [
            ("candidate_not_found", 404),
            ("invalid_candidate_revision", 400),
            ("invalid_edited_fields", 400),
            ("candidate_already_committed", 409),
            ("candidate_not_revisable", 409),
        ]

        for code, expected_status in cases:
            with self.subTest(code=code):
                repository = FakeTaskCandidateRepository()
                review_service = FakeTaskCandidateReviewService(
                    error=task_candidates_route.TaskCandidateReviewError(
                        code,
                        f"{code} message",
                    )
                )
                client = self.make_client(repository, review_service=review_service)

                response = client.post(
                    f"/api/v1/task-candidates/{CANDIDATE_ID}/revise",
                    json={"revision_type": "make_smaller", "note": "더 작게"},
                )

                self.assertEqual(response.status_code, expected_status)
                detail = response.json()["detail"]
                self.assertEqual(detail["code"], code)
                self.assertEqual(detail["message"], f"{code} message")

    def test_reject_task_candidate_maps_review_errors(self) -> None:
        cases = [
            ("candidate_not_found", 404),
            ("candidate_already_committed", 409),
            ("candidate_not_rejectable", 409),
        ]

        for code, expected_status in cases:
            with self.subTest(code=code):
                repository = FakeTaskCandidateRepository()
                review_service = FakeTaskCandidateReviewService(
                    error=task_candidates_route.TaskCandidateReviewError(
                        code,
                        f"{code} message",
                    )
                )
                client = self.make_client(repository, review_service=review_service)

                response = client.post(
                    f"/api/v1/task-candidates/{CANDIDATE_ID}/reject",
                    json={"reason": "취소"},
                )

                self.assertEqual(response.status_code, expected_status)
                detail = response.json()["detail"]
                self.assertEqual(detail["code"], code)
                self.assertEqual(detail["message"], f"{code} message")

    def test_revise_task_candidate_maps_unexpected_error_to_500(self) -> None:
        repository = FakeTaskCandidateRepository()
        review_service = FakeTaskCandidateReviewService(
            error=RuntimeError("database down")
        )
        client = self.make_client(repository, review_service=review_service)

        response = client.post(
            f"/api/v1/task-candidates/{CANDIDATE_ID}/revise",
            json={"revision_type": "make_smaller", "note": "더 작게"},
        )

        self.assertEqual(response.status_code, 500)
        detail = response.json()["detail"]
        self.assertEqual(detail["code"], "task_candidate_revise_failed")
        self.assertEqual(
            detail["message"],
            "Task candidate revision failed unexpectedly.",
        )

    def test_reject_task_candidate_maps_unexpected_error_to_500(self) -> None:
        repository = FakeTaskCandidateRepository()
        review_service = FakeTaskCandidateReviewService(
            error=RuntimeError("database down")
        )
        client = self.make_client(repository, review_service=review_service)

        response = client.post(
            f"/api/v1/task-candidates/{CANDIDATE_ID}/reject",
            json={"reason": "취소"},
        )

        self.assertEqual(response.status_code, 500)
        detail = response.json()["detail"]
        self.assertEqual(detail["code"], "task_candidate_reject_failed")
        self.assertEqual(
            detail["message"],
            "Task candidate rejection failed unexpectedly.",
        )


if __name__ == "__main__":
    unittest.main()
