# Start On 프로젝트 구조 설명

이 문서는 현재 저장소의 프론트엔드, 백엔드, Supabase 구조를 빠르게 파악하기 위한 정리 문서입니다. 소스 기준 위치는 `start_on/`이며, `gpt_pro_ai_suggestion_context/`, 빌드 산출물, 캐시, APK, 가상환경, 로그 파일은 실제 애플리케이션 소스 구조 설명에서 제외합니다.

## 최상단 구조

```text
start_on/
├── README.md
├── vercel-build.sh
├── starton-test.apk
├── frontend/
├── backend/
├── supabase/
├── docs/
└── gpt_pro_ai_suggestion_context/
```

- `frontend/`: Flutter 앱 전체 코드입니다.
- `backend/`: FastAPI 서버 코드입니다.
- `supabase/`: 로컬 Supabase 설정과 DB 마이그레이션 원본입니다.
- `backend/migrations/`: 백엔드 쪽에 보관된 Supabase 마이그레이션 복사본입니다. 실제 Supabase CLI 기준으로는 `supabase/migrations/`가 중심입니다.
- `docs/`: 별도 문서 보관 위치입니다.
- `gpt_pro_ai_suggestion_context/`: AI 제안 기능 분석을 위해 만든 임시 복사본입니다. 앱이 직접 사용하는 소스는 아닙니다.
- `starton-test.apk`: 최상단 APK 산출물입니다.

## 프론트엔드 구조

프론트엔드는 `frontend/` 아래의 Flutter 앱입니다.

```text
frontend/
├── lib/
│   ├── main.dart
│   ├── app_shell.dart
│   ├── models/
│   ├── pages/
│   ├── repositories/
│   ├── services/
│   ├── storage/
│   └── widgets/
├── test/
├── android/
├── web/
├── assets/
├── pubspec.yaml
└── analysis_options.yaml
```

### 프론트엔드 진입점

- `lib/main.dart`
  - Flutter 바인딩을 초기화합니다.
  - `QuestTimerBackgroundService.instance`를 초기화합니다.
  - `AdFocusApp`을 실행합니다.

- `lib/app_shell.dart`
  - 앱 전체 상태와 화면 전환을 담당하는 핵심 파일입니다.
  - `AdFocusApp`에서 `MaterialApp`, 테마, 인증 게이트를 구성합니다.
  - `_AuthGate`가 `AuthSessionStore`에서 로그인 세션을 불러와 로컬 모드 또는 서버 로그인 모드를 결정합니다.
  - `AdFocusShell`이 홈, 재도전, 랭킹, 기록 화면과 퀘스트 추가/수정/완료 흐름을 연결합니다.
  - 서버 세션이 있으면 `ProfileRepository`, `QuestRepository`, `StatsRepository`, `DungeonRepository`, `LeaderboardRepository`, `TaskIntakeRepository`를 생성해서 서버 데이터를 사용합니다.
  - 로컬 전용 세션이면 `LocalDataStore` 기반으로 동작합니다.

### 프론트엔드 모델

주요 위치는 `frontend/lib/models/`입니다.

- `app_local_data.dart`
  - 모델 export 파일입니다.

- `app_local_data_model.dart`
  - 로컬 앱 상태 전체를 담는 모델입니다.
  - 프로필, 스탯, 퀘스트, 던전, 완료 기록, 최근 활동 등을 한 번에 저장합니다.

- `quest_item.dart`
  - 앱에서 사용하는 퀘스트 핵심 모델입니다.
  - 퀘스트 제목, 설명, 난이도, 카테고리, EXP, 소요 시간, 타이머 상태, 하위 작업, 서버 동기화 대상 정보를 포함합니다.
  - 로컬 퀘스트, 기존 서버 퀘스트, AI task 기반 퀘스트를 구분하는 필드가 있습니다.

- `completed_quest_record.dart`
  - 완료된 퀘스트 기록 모델입니다.
  - 완료 시점, 증빙 이미지, 소요 시간, 하위 작업 결과 등을 저장합니다.

- `task_intake_api_models.dart`
  - AI 제안 기능에서 사용하는 API 요청/응답 모델입니다.
  - 원본 입력, 후보 작업, 최종 작업, 하위 작업, 리마인더 정보를 다룹니다.

- `task_quest_mapper.dart`
  - 백엔드의 최종 `TaskResponse`를 앱 화면에서 쓰는 `QuestItem`으로 변환합니다.
  - AI로 생성되어 확정된 task를 일반 퀘스트처럼 보여주기 위한 연결 계층입니다.

- 그 외 API 모델
  - `auth_models.dart`: 로그인, 회원가입, 토큰 세션 모델입니다.
  - `profile_api_models.dart`: 사용자 프로필 API 모델입니다.
  - `stats_api_models.dart`: 통계 API 모델입니다.
  - `quest_api_models.dart`: 기존 퀘스트 API 모델입니다.
  - `leaderboard_api_models.dart`: 랭킹 API 모델입니다.
  - `dungeon_api_models.dart`: 던전 API 모델입니다.

### 프론트엔드 화면 구조

주요 위치는 `frontend/lib/pages/`입니다.

- `login_screen.dart`
  - 이메일 로그인, 회원가입, 로컬 모드 진입을 담당합니다.

- `home_screen.dart`, `pages/home/`
  - 메인 홈 화면과 홈 화면 구성 위젯입니다.
  - 진행 중 퀘스트, 완료 상태, 프로필 요약, 타이머 진입 등을 보여줍니다.

- `add_quest_screen.dart`
  - 퀘스트 직접 추가 화면입니다.
  - 제목, 마감일, 난이도, 카테고리, 하위 작업, AI 제안 요청을 입력합니다.
  - AI 제안 버튼을 누르면 일반 `QuestItem` 대신 `AddQuestScreenAiSuggestionRequest`를 반환할 수 있습니다.

- `task_candidate_review_screen.dart`
  - AI가 만든 후보 작업을 검토하는 화면입니다.
  - 그대로 저장, 오늘 할 일만 저장, 수정 요청, 취소 흐름을 제공합니다.

- `quest_timer_screen.dart`, `pages/quest_timer/`
  - 퀘스트 타이머, 하위 작업 진행, 완료 증빙, 완료 처리 UI를 담당합니다.

- `record_screen.dart`, `pages/record/`
  - 완료 기록과 활동 기록을 보여줍니다.

- `profile_screen.dart`, `pages/profile/`
  - 프로필, 스탯, 설정 진입 등 사용자 정보 화면을 구성합니다.

- 기타 화면
  - `ranking_screen.dart`: 랭킹 화면입니다.
  - `settings_screen.dart`: 앱 설정 화면입니다.
  - `retry_screen.dart`: 재도전 화면입니다.
  - `shop_screen.dart`: 상점 화면입니다.

### 프론트엔드 서버 통신 계층

주요 위치는 `frontend/lib/repositories/`와 `frontend/lib/services/`입니다.

- `services/api_client.dart`
  - 모든 HTTP 요청의 공통 클라이언트입니다.
  - `START_ON_API_BASE_URL` dart-define 값을 사용합니다.
  - 기본값은 `https://starton.onrender.com/api/v1`입니다.
  - Bearer 토큰 설정, 토큰 갱신, API 응답 envelope 파싱을 담당합니다.

- `repositories/auth_repository.dart`
  - `/auth/sign-in`, `/auth/sign-up`, `/auth/refresh` 호출을 담당합니다.

- `repositories/quest_repository.dart`
  - 기존 퀘스트 CRUD, 완료 API를 담당합니다.

- `repositories/task_intake_repository.dart`
  - AI 제안 기능의 중심 repository입니다.
  - `/task-intake`로 원본 입력을 보내 후보 작업을 생성합니다.
  - `/task-candidates/{id}` 조회, 수정 요청, 거절, 확정을 처리합니다.
  - `/tasks` 목록, 진행률 업데이트, 완료 처리를 담당합니다.

- `repositories/profile_repository.dart`
  - 사용자 프로필 조회/수정 API를 담당합니다.

- `repositories/stats_repository.dart`
  - 사용자 통계 API를 담당합니다.

- `repositories/dungeon_repository.dart`
  - 던전 클리어 정보 API를 담당합니다.

- `repositories/leaderboard_repository.dart`
  - 랭킹 API를 담당합니다.

- `repositories/quest_text_extraction_repository.dart`
  - 이미지/OCR 기반 퀘스트 텍스트 추출 API를 담당합니다.

- `services/notion_sync_service.dart`
  - Notion 연동 상태, 동기화, disconnect 흐름을 담당합니다.

- `services/quest_timer_background_service.dart`
  - 퀘스트 타이머의 백그라운드 서비스와 알림을 담당합니다.

- `services/quest_candidate_generator.dart`
  - 서버 AI가 아닌 로컬 규칙 기반 퀘스트 후보 생성을 담당합니다.

### 프론트엔드 저장소 계층

주요 위치는 `frontend/lib/storage/`입니다.

- `auth_session_store.dart`
  - `SharedPreferences`에 로그인 세션을 저장합니다.
  - 서버 로그인 세션과 로컬 전용 세션을 구분합니다.

- `local_data_store.dart`
  - 로컬 모드 또는 오프라인 상태에서 앱 데이터를 저장합니다.
  - 완료 처리, Notion 데이터 병합/삭제, 로컬 데이터 정규화를 담당합니다.

- `app_settings_store.dart`
  - 알림, 진동, 축하 효과, 자동 저장, Notion 관련 설정을 저장합니다.

- `quest_image_store*`, `path_image_provider*`
  - 퀘스트 완료 증빙 이미지 저장과 플랫폼별 이미지 provider 처리를 담당합니다.

### 프론트엔드 AI 제안 흐름

AI 제안 기능은 프론트와 백엔드가 함께 동작합니다.

```text
AddQuestScreen
→ AddQuestScreenAiSuggestionRequest
→ AdFocusShell._createTaskCandidate()
→ TaskIntakeRepository.create()
→ POST /task-intake
→ TaskCandidateReviewScreen
→ confirm / revise / reject
→ TaskIntakeRepository.confirmCandidate()
→ POST /task-candidates/{id}/confirm
→ TaskResponse
→ questItemFromTaskResponse()
→ HomeScreen에 QuestItem으로 표시
```

이 흐름을 볼 때 프론트에서 우선 확인할 파일은 다음과 같습니다.

- `frontend/lib/pages/add_quest_screen.dart`
- `frontend/lib/app_shell.dart`
- `frontend/lib/pages/task_candidate_review_screen.dart`
- `frontend/lib/repositories/task_intake_repository.dart`
- `frontend/lib/models/task_intake_api_models.dart`
- `frontend/lib/models/task_quest_mapper.dart`

### 프론트엔드 테스트

`frontend/test/` 아래에 단위 테스트와 위젯 테스트가 있습니다.

주요 테스트 범위는 다음과 같습니다.

- API client
- 인증 repository
- 로컬 데이터 저장소
- Notion 설정/동기화
- 퀘스트 모델과 repository
- 퀘스트 타이머
- 랭킹 화면
- task candidate review 화면
- task intake 모델과 repository

## 백엔드 구조

백엔드는 `backend/` 아래의 FastAPI 서버입니다.

```text
backend/
├── app/
│   ├── main.py
│   ├── api/
│   ├── core/
│   ├── providers/
│   ├── repositories/
│   ├── schemas/
│   ├── services/
│   └── prompts/
├── tests/
├── migrations/
├── requirements.txt
└── .env.example
```

### 백엔드 진입점과 설정

- `app/main.py`
  - FastAPI 앱을 생성합니다.
  - CORS, 예외 핸들러, 라우터, 시작 시 Supabase 연결 확인을 설정합니다.
  - 루트 엔드포인트를 제공합니다.

- `app/api/router.py`
  - API v1 라우터를 설정합니다.
  - 기본 prefix는 설정값 기준 `/api/v1`입니다.

- `app/api/v1/router.py`
  - v1 하위 라우터들을 모읍니다.
  - 인증, 헬스체크, AI, 퀘스트, AI task intake, task candidate, 최종 task, 프로필, 통계, 랭킹, 던전, Notion integration 라우터를 연결합니다.

- `app/core/config.py`
  - `.env`와 환경변수를 읽어 `Settings`를 구성합니다.
  - `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ANON_KEY` 같은 외부 연결 값을 검증합니다.
  - `GEMINI_API_KEY`는 AI 기능에서 사용합니다.
  - `NOTION_TOKEN_ENCRYPTION_KEY`는 Notion 토큰 암호화에 사용합니다.

- `app/core/auth.py`
  - Bearer 토큰 인증을 처리합니다.
  - Supabase Auth로 토큰을 검증하고 현재 사용자 id를 가져옵니다.

- `app/core/supabase.py`
  - Supabase service-role client를 생성합니다.

### 백엔드 dependency 구조

주요 파일은 `backend/app/api/dependencies.py`입니다.

이 파일은 API route가 필요한 객체를 생성하고 주입합니다.

- 현재 사용자 인증
- Supabase client
- profile/stats/leaderboard/dungeon repository
- quest repository
- AI intake 관련 repository
- task candidate/task repository
- Notion repository/service
- Gemini provider
- mediator service
- task commit service
- task service

인증된 요청에서는 `get_current_user_id()`가 먼저 Supabase 토큰을 검증하고, 필요한 경우 사용자 기본 레코드를 bootstrap합니다.

### 백엔드 API 라우터

주요 위치는 `backend/app/api/v1/`입니다.

- `auth.py`
  - Supabase Auth REST API를 통해 이메일 회원가입, 로그인, refresh를 처리합니다.

- `health.py`
  - 서버 상태 확인 엔드포인트입니다.

- `debug.py`
  - 디버그용 엔드포인트입니다.

- `ai.py`
  - AI 관련 보조 엔드포인트입니다.

- `quests.py`
  - 기존 퀘스트 생성, OCR 텍스트 추출, 퀘스트 CRUD, 완료 처리를 담당합니다.

- `task_intake.py`
  - AI 제안 기능의 시작점입니다.
  - 사용자의 원본 입력을 받아 `raw_task_inputs`에 저장하고 mediator를 실행합니다.

- `task_candidates.py`
  - AI가 만든 후보 작업 조회, 수정 요청, 거절, 확정을 처리합니다.

- `tasks.py`
  - 확정된 task 목록 조회, 진행률 업데이트, 완료 처리를 담당합니다.

- `profile.py`
  - 사용자 프로필 조회/수정 API입니다.

- `stats.py`
  - 사용자 통계 API입니다.

- `leaderboard.py`
  - 랭킹 API입니다.

- `dungeons.py`
  - 던전 클리어 API입니다.

- `integrations_notion.py`
  - Notion 연결, 동기화, 상태 확인, 연결 해제를 담당합니다.

### 백엔드 서비스 계층

주요 위치는 `backend/app/services/`입니다.

- `intake_service.py`
  - AI 제안 원본 입력을 저장합니다.
  - `MediatorService`를 호출해 candidate 생성을 시작합니다.
  - 최종적으로 `TaskIntakeResponse`를 반환합니다.

- `mediator_service.py`
  - AI 제안 기능의 핵심 orchestration입니다.
  - raw input을 processing 상태로 바꿉니다.
  - 오늘의 작업 context를 조회합니다.
  - mediator run을 기록합니다.
  - `GeminiProvider`를 호출해 구조화된 후보 결과를 받습니다.
  - `TodayPlanningService`로 오늘 일정 과부하 여부를 보정합니다.
  - task candidate, subtask, reminder를 저장합니다.
  - 성공/실패 상태를 DB에 기록합니다.

- `task_commit_service.py`
  - 후보 작업을 최종 task로 확정합니다.
  - 선택된 subtask/reminder를 검증합니다.
  - `tasks`, `subtasks`, `reminders`에 저장합니다.
  - candidate 상태를 committed로 바꿉니다.
  - 프론트에서 넘긴 카테고리, EXP, 기본 소요 시간 같은 metadata를 보존합니다.

- `task_service.py`
  - 확정된 task-backed quest 목록을 조회합니다.
  - 진행률과 소요 시간을 업데이트합니다.
  - 완료 처리 시 완료 기록, 최근 활동, 스탯, 프로필 progression을 함께 갱신합니다.

- `task_candidate_review_service.py`
  - candidate 수정 요청과 거절 처리를 담당합니다.

- `today_planning_service.py`
  - 오늘 완료/예정 작업 context를 만들고, 하루 작업량 과부하를 판단합니다.

- `quest_service.py`
  - 기존 `quests` 테이블 기반 퀘스트 CRUD와 완료 처리를 담당합니다.

- `progression_service.py`
  - EXP, 레벨, 일일 스탯 리셋, 완료 보상 계산을 담당합니다.

- `notion_backend_service.py`, `notion_sync_service.py`, `notion_parser.py`
  - Notion 연결 정보, 동기화, Notion 페이지 parsing을 담당합니다.

- AI/퀘스트 보조 서비스
  - `ai_quest_service.py`
  - `quest_generation_service.py`
  - `quest_text_extraction_service.py`
  - `difficulty_rules.py`
  - `category_inference.py`

- 사용자/앱 기능 서비스
  - `dungeon_service.py`
  - `profile_service.py`
  - `stats_service.py`
  - `leaderboard_service.py`

### 백엔드 provider 계층

주요 위치는 `backend/app/providers/`입니다.

- `gemini_provider.py`
  - AI 제안 mediator가 사용하는 Gemini provider입니다.
  - prompt 파일은 `backend/app/prompts/adhd_mediator_v1.md`입니다.
  - 구조화된 JSON 결과를 `MediatorOutput` 형태로 반환합니다.

- `gemini_ocr_quest_generation.py`
  - 이미지/OCR 기반 퀘스트 생성을 위한 Gemini provider입니다.

- `rule_based_quest_generation.py`
  - LLM을 쓰지 않는 규칙 기반 퀘스트 생성 fallback입니다.

- `notion_client.py`
  - Notion API와 통신하는 provider입니다.

### 백엔드 repository 계층

주요 위치는 `backend/app/repositories/`입니다.

- `base.py`
  - 추상 repository 인터페이스와 공통 데이터 클래스를 정의합니다.

- Supabase repository들
  - `supabase_profile_repository.py`
  - `supabase_stats_repository.py`
  - `supabase_leaderboard_repository.py`
  - `supabase_dungeon_repository.py`
  - `supabase_quest_repository.py`
  - `supabase_completed_quest_repository.py`
  - `supabase_recent_activity_repository.py`
  - `supabase_raw_task_input_repository.py`
  - `supabase_mediator_run_repository.py`
  - `supabase_task_candidate_repository.py`
  - `supabase_task_final_repository.py`
  - `supabase_today_context_repository.py`
  - `supabase_user_bootstrap_repository.py`
  - `supabase_notion_repository.py`
  - `supabase_quest_generation_log_repository.py`

Repository 계층은 FastAPI route나 service가 Supabase SDK 세부 구현에 직접 묶이지 않게 분리합니다.

### 백엔드 schema 계층

주요 위치는 `backend/app/schemas/`입니다.

- `common.py`
  - 공통 API 응답 envelope, 에러 detail, 빈 payload 모델을 정의합니다.

- 인증/사용자/앱 모델
  - `auth.py`
  - `profile.py`
  - `stats.py`
  - `leaderboard.py`
  - `dungeon.py`

- 퀘스트/AI 모델
  - `quest.py`
  - `quest_generation.py`
  - `task_intake.py`
  - `mediator.py`
  - `task_candidate.py`
  - `task.py`
  - `reminder.py`
  - `feedback.py`
  - `ai.py`

- 외부 연동/상태 모델
  - `notion.py`
  - `health.py`

### 백엔드 AI 제안 요청 흐름

```text
Flutter AddQuestScreen
→ POST /api/v1/task-intake
→ task_intake.py
→ IntakeService
→ raw_task_inputs 저장
→ MediatorService
→ today context 조회
→ mediator_runs 생성
→ GeminiProvider.generate_mediator_result()
→ task_candidates / candidate_subtasks / candidate_reminders 저장
→ Flutter TaskCandidateReviewScreen
→ POST /api/v1/task-candidates/{id}/confirm
→ TaskCommitService
→ tasks / subtasks / reminders 저장
→ Flutter에서 QuestItem으로 매핑
```

AI 제안 기능 문제를 볼 때 백엔드에서 우선 확인할 파일은 다음과 같습니다.

- `backend/app/api/v1/task_intake.py`
- `backend/app/api/v1/task_candidates.py`
- `backend/app/services/intake_service.py`
- `backend/app/services/mediator_service.py`
- `backend/app/services/task_commit_service.py`
- `backend/app/providers/gemini_provider.py`
- `backend/app/prompts/adhd_mediator_v1.md`
- `backend/app/schemas/task_intake.py`
- `backend/app/schemas/mediator.py`
- `backend/app/schemas/task_candidate.py`

### 백엔드 테스트

`backend/tests/` 아래에 unittest 기반 테스트가 있습니다.

테스트 범위는 다음과 같습니다.

- 인증 API
- 퀘스트 API
- AI mediator/intake
- task candidate 확정/검토
- final task 완료
- Notion 연동
- progression 계산
- Supabase repository 동작

## Supabase 구조

Supabase 관련 원본은 `supabase/` 아래에 있습니다.

```text
supabase/
├── config.toml
└── migrations/
    ├── 0001_supabase_schema.sql
    ├── 0002_ai_mediator_intake_schema.sql
    ├── 0003_ai_candidate_schema.sql
    ├── 0004_final_task_schema.sql
    ├── 0005_notion_sync_stability.sql
    ├── 0006_completed_task_records.sql
    ├── 0007_quest_due_at.sql
    └── 0008_task_progress_and_completion_visibility.sql
```

### Supabase 로컬 설정

- `config.toml`
  - Supabase 로컬 프로젝트 id는 `start_on_backend`입니다.
  - 로컬 API 포트는 `54321`입니다.
  - 로컬 DB 포트는 `54322`입니다.
  - 로컬 Studio 포트는 `54323`입니다.
  - Auth, Storage, DB migration이 활성화되어 있습니다.
  - seed 경로는 `./seed.sql`로 설정되어 있지만, 현재 파일 목록 기준으로 seed 파일은 확인되지 않았습니다.

### Supabase 마이그레이션

- `0001_supabase_schema.sql`
  - 기본 앱 schema를 만듭니다.
  - `pgcrypto` 확장을 활성화합니다.
  - `set_updated_at()` trigger 함수를 정의합니다.
  - 주요 테이블:
    - `users_profile`
    - `user_stats`
    - `quests`
    - `completed_quests`
    - `recent_activities`
    - `dungeon_clears`
    - `notion_connections`
    - `quest_generation_logs`
  - index, trigger, RLS 활성화, 테이블/컬럼 comment를 포함합니다.

- `0002_ai_mediator_intake_schema.sql`
  - AI 제안 원본 입력과 mediator 실행 기록을 추가합니다.
  - 주요 테이블:
    - `raw_task_inputs`
    - `prompt_versions`
    - `mediator_runs`

- `0003_ai_candidate_schema.sql`
  - AI가 만든 후보 작업 구조를 추가합니다.
  - 주요 테이블:
    - `task_candidates`
    - `candidate_subtasks`
    - `candidate_reminders`

- `0004_final_task_schema.sql`
  - 후보를 확정했을 때 저장되는 최종 task 구조를 추가합니다.
  - 주요 테이블:
    - `tasks`
    - `subtasks`
    - `reminders`

- `0005_notion_sync_stability.sql`
  - Notion 동기화 안정성을 위한 컬럼과 index를 추가합니다.
  - 외부 Notion id, sync source, connection 상태 등을 보강합니다.

- `0006_completed_task_records.sql`
  - 완료 기록과 final task를 연결하기 위해 `completed_quests.task_id`를 추가합니다.

- `0007_quest_due_at.sql`
  - 기존 `quests` 테이블에 `due_at`을 추가합니다.

- `0008_task_progress_and_completion_visibility.sql`
  - final task 진행률과 완료 표시 문제를 보정합니다.
  - `tasks.elapsed_seconds`를 추가합니다.
  - 활성 task 조회 index를 추가합니다.
  - raw input metadata 기반으로 task metadata를 보정합니다.
  - 기존 완료 task/quest row의 표시 상태를 정리합니다.

### Supabase 테이블 그룹

현재 DB 구조는 크게 네 그룹으로 나뉩니다.

#### 사용자와 진행도

- `users_profile`
  - 사용자 표시 이름, 레벨, EXP, streak, 보스 HP 등 프로필/진행 상태를 저장합니다.

- `user_stats`
  - 날짜별 완료 수, 총 집중 시간, 획득 EXP 같은 통계를 저장합니다.

- `recent_activities`
  - 최근 활동 feed를 위한 이벤트 로그입니다.

- `dungeon_clears`
  - 던전 클리어 기록입니다.

#### 기존 퀘스트 구조

- `quests`
  - AI task 시스템 이전부터 쓰던 일반 퀘스트 테이블입니다.
  - 제목, 설명, 난이도, 카테고리, EXP, 상태, 마감일 등을 저장합니다.

- `completed_quests`
  - 완료된 퀘스트 기록입니다.
  - `quest_id` 또는 `task_id`와 연결될 수 있습니다.

#### AI 제안과 final task 구조

- `raw_task_inputs`
  - 사용자가 입력한 원본 요청을 저장합니다.

- `prompt_versions`
  - mediator prompt 버전 정보를 저장합니다.

- `mediator_runs`
  - AI mediator 실행 상태와 결과/오류를 기록합니다.

- `task_candidates`
  - AI가 만든 후보 작업입니다.

- `candidate_subtasks`
  - 후보 작업의 하위 작업입니다.

- `candidate_reminders`
  - 후보 작업의 리마인더입니다.

- `tasks`
  - 사용자가 확정한 최종 작업입니다.
  - 프론트에서는 이 데이터를 `QuestItem`으로 변환해 홈 화면 퀘스트처럼 보여줍니다.

- `subtasks`
  - 최종 task의 하위 작업입니다.

- `reminders`
  - 최종 task의 리마인더입니다.

#### 외부 연동과 로그

- `notion_connections`
  - 사용자별 Notion 연결 토큰, workspace, database 정보, sync 상태를 저장합니다.

- `quest_generation_logs`
  - 퀘스트 생성 요청/결과 로그를 저장합니다.

### Supabase와 백엔드 repository 연결

백엔드 service는 직접 SQL을 쓰기보다 Supabase repository를 통해 DB에 접근합니다.

```text
FastAPI route
→ service
→ supabase_*_repository.py
→ Supabase client
→ Supabase table
```

예를 들어 AI 제안 기능은 다음 테이블들을 순서대로 사용합니다.

```text
raw_task_inputs
→ mediator_runs
→ task_candidates
→ candidate_subtasks
→ candidate_reminders
→ tasks
→ subtasks
→ reminders
→ completed_quests
→ recent_activities
→ user_stats / users_profile
```

### 기존 quest와 final task의 차이

현재 앱에는 두 종류의 퀘스트성 데이터가 함께 존재합니다.

- 기존 quest
  - Supabase `quests` 테이블에 저장됩니다.
  - `QuestRepository`와 `QuestService`가 담당합니다.

- AI 제안으로 확정된 final task
  - Supabase `tasks`, `subtasks`, `reminders` 테이블에 저장됩니다.
  - `TaskIntakeRepository`, `TaskCommitService`, `TaskService`가 담당합니다.
  - 프론트에서는 `task_quest_mapper.dart`를 통해 `QuestItem`으로 변환되어 일반 퀘스트처럼 표시됩니다.

이 구분 때문에 "홈 화면에 보이는 퀘스트"가 DB에서는 `quests`가 아니라 `tasks`에서 온 데이터일 수 있습니다.

## 실행과 검증에 관련된 파일

- 프론트 의존성: `frontend/pubspec.yaml`
- 프론트 정적 분석 설정: `frontend/analysis_options.yaml`
- 백엔드 의존성: `backend/requirements.txt`
- 백엔드 환경변수 예시: `backend/.env.example`
- Supabase 로컬 설정: `supabase/config.toml`

자주 쓰는 검증 명령은 다음과 같습니다.

```bash
cd start_on/frontend
/home/qoranreh/development/flutter/bin/dart format lib
/home/qoranreh/development/flutter/bin/flutter analyze
/home/qoranreh/development/flutter/bin/flutter test
/home/qoranreh/development/flutter/bin/flutter build apk --dart-define=START_ON_API_BASE_URL=https://starton.onrender.com/api/v1
```

```bash
cd start_on/backend
.venv/bin/python -m unittest discover -s tests
```

```bash
cd start_on
supabase db lint --local --workdir supabase --fail-on warning
```

## 공유하거나 복사할 때 제외해도 되는 것

다른 사람에게 코드 분석용으로 넘길 때 다음은 보통 제외해도 됩니다.

- `frontend/build/`
- `frontend/.dart_tool/`
- `backend/.venv/`
- `backend/__pycache__/`
- `backend/.pytest_cache/`
- `starton-test.apk`
- `*.log`
- `.git/`
- `gpt_pro_ai_suggestion_context/` 안의 중복 복사본

반대로 AI 제안 기능을 분석하려면 최소한 다음은 포함하는 것이 좋습니다.

- `frontend/lib/app_shell.dart`
- `frontend/lib/pages/add_quest_screen.dart`
- `frontend/lib/pages/task_candidate_review_screen.dart`
- `frontend/lib/repositories/task_intake_repository.dart`
- `frontend/lib/models/task_intake_api_models.dart`
- `frontend/lib/models/task_quest_mapper.dart`
- `backend/app/api/v1/task_intake.py`
- `backend/app/api/v1/task_candidates.py`
- `backend/app/services/intake_service.py`
- `backend/app/services/mediator_service.py`
- `backend/app/services/task_commit_service.py`
- `backend/app/providers/gemini_provider.py`
- `backend/app/prompts/adhd_mediator_v1.md`
- `backend/app/schemas/task_intake.py`
- `backend/app/schemas/mediator.py`
- `backend/app/schemas/task_candidate.py`
- `supabase/migrations/0002_ai_mediator_intake_schema.sql`
- `supabase/migrations/0003_ai_candidate_schema.sql`
- `supabase/migrations/0004_final_task_schema.sql`
- `supabase/migrations/0008_task_progress_and_completion_visibility.sql`

