import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:start_on/app_shell.dart';
import 'package:start_on/models/auth_models.dart';
import 'package:start_on/models/dungeon_api_models.dart';
import 'package:start_on/models/profile_api_models.dart';
import 'package:start_on/models/quest_api_models.dart';
import 'package:start_on/models/quest_item.dart';
import 'package:start_on/models/stats_api_models.dart';
import 'package:start_on/models/task_intake_api_models.dart';
import 'package:start_on/repositories/auth_repository.dart';
import 'package:start_on/repositories/dungeon_repository.dart';
import 'package:start_on/repositories/profile_repository.dart';
import 'package:start_on/repositories/quest_repository.dart';
import 'package:start_on/repositories/stats_repository.dart';
import 'package:start_on/repositories/task_intake_repository.dart';
import 'package:start_on/services/api_client.dart';

void main() {
  testWidgets('renders login screen first', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const AdFocusApp());
    await tester.pumpAndSettle();

    expect(find.text('START ON'), findsOneWidget);
    expect(find.text('로그인'), findsWidgets);
    expect(find.text('게스트로 시작'), findsOneWidget);
  });

  testWidgets('renders home shell for saved session', (tester) async {
    SharedPreferences.setMockInitialValues({
      'auth.is_signed_in': true,
      'auth.user_id': 'user-1',
      'auth.email': 'tester@starton.local',
      'auth.display_name': 'Tester',
      'auth.access_token': 'access-token',
      'settings.notifications_enabled': false,
    });
    final repositories = _FakeServerRepositories();

    await tester.pumpWidget(
      AdFocusApp(
        profileRepository: repositories.profileRepository,
        questRepository: repositories.questRepository,
        statsRepository: repositories.statsRepository,
        dungeonRepository: repositories.dungeonRepository,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(repositories.profileRepository.getCallCount, 1);
    expect(repositories.questRepository.listCallCount, 1);
    expect(repositories.statsRepository.getCallCount, 1);
    expect(repositories.dungeonRepository.listCallCount, 1);
    expect(find.text('Tester 님'), findsOneWidget);
    expect(find.text('오늘의 퀘스트'), findsWidgets);
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
    expect(find.byIcon(Icons.bar_chart_rounded), findsOneWidget);
  });

  testWidgets(
    'shows server data loading while saved session initial data is pending',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'auth.is_signed_in': true,
        'auth.user_id': 'user-1',
        'auth.email': 'tester@starton.local',
        'auth.display_name': 'Tester',
        'auth.access_token': 'access-token',
        'settings.notifications_enabled': false,
      });
      final profileCompleter = Completer<ProfileResponse>();
      final profileRepository = _FakeProfileRepository(
        userName: 'Tester',
        responseCompleter: profileCompleter,
      );
      final questRepository = _FakeQuestRepository();
      final statsRepository = _FakeStatsRepository();
      final dungeonRepository = _FakeDungeonRepository();

      await tester.pumpWidget(
        AdFocusApp(
          profileRepository: profileRepository,
          questRepository: questRepository,
          statsRepository: statsRepository,
          dungeonRepository: dungeonRepository,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(profileRepository.getCallCount, 1);
      expect(find.text('서버 데이터 불러오는 중...'), findsOneWidget);
      expect(find.textContaining('서버 초기 데이터를 불러오지 못해'), findsNothing);

      profileCompleter.complete(_profileResponse('Tester'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Tester 님'), findsOneWidget);
    },
  );

  testWidgets(
    'does not show initial server load failure while startup falls back',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'auth.is_signed_in': true,
        'auth.user_id': 'user-1',
        'auth.email': 'tester@starton.local',
        'auth.display_name': 'Tester',
        'auth.access_token': 'access-token',
        'settings.notifications_enabled': false,
      });
      final profileRepository = _FakeProfileRepository(
        userName: 'Tester',
        error: Exception('offline'),
      );
      final questRepository = _FakeQuestRepository();
      final statsRepository = _FakeStatsRepository();
      final dungeonRepository = _FakeDungeonRepository();

      await tester.pumpWidget(
        AdFocusApp(
          profileRepository: profileRepository,
          questRepository: questRepository,
          statsRepository: statsRepository,
          dungeonRepository: dungeonRepository,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(profileRepository.getCallCount, 1);
      expect(find.text('서버 데이터 불러오는 중...'), findsNothing);
      expect(find.textContaining('서버 초기 데이터를 불러오지 못해'), findsNothing);
      expect(find.text('오늘의 퀘스트'), findsWidgets);
    },
  );

  testWidgets('guest start saves a local session', (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings.notifications_enabled': false,
    });

    await tester.pumpWidget(const AdFocusApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('게스트로 시작'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('auth.is_signed_in'), isTrue);
    expect(prefs.getString('auth.user_id'), 'local:guest@starton.local');
    expect(prefs.getString('auth.email'), 'guest@starton.local');
    expect(prefs.getString('auth.display_name'), '게스트');
    expect(prefs.getString('auth.access_token'), '');
    expect(prefs.getBool('auth.is_local_only'), isTrue);
    expect(find.text('게스트 님'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const AdFocusApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('START ON'), findsNothing);
    expect(find.text('게스트 님'), findsOneWidget);
  });

  testWidgets('server login saves auth repository session', (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings.notifications_enabled': false,
    });
    final repository = _FakeAuthRepository(
      response: const AuthSessionResponse(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        user: AuthUserResponse(id: 'user-1', email: 'tester@starton.local'),
      ),
    );
    final repositories = _FakeServerRepositories();

    await tester.pumpWidget(
      AdFocusApp(
        authRepository: repository,
        profileRepository: repositories.profileRepository,
        questRepository: repositories.questRepository,
        statsRepository: repositories.statsRepository,
        dungeonRepository: repositories.dungeonRepository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'tester@starton.local',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'secret123');
    await tester.tap(find.widgetWithText(FilledButton, '로그인'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final prefs = await SharedPreferences.getInstance();
    expect(repository.email, 'tester@starton.local');
    expect(repository.password, 'secret123');
    expect(prefs.getBool('auth.is_signed_in'), isTrue);
    expect(prefs.getString('auth.user_id'), 'user-1');
    expect(prefs.getString('auth.email'), 'tester@starton.local');
    expect(prefs.getString('auth.access_token'), 'access-token');
    expect(prefs.getString('auth.refresh_token'), 'refresh-token');
    expect(prefs.getBool('auth.is_local_only'), isFalse);
    expect(repositories.profileRepository.getCallCount, 1);
    expect(repositories.questRepository.listCallCount, 1);
    expect(repositories.statsRepository.getCallCount, 1);
    expect(repositories.dungeonRepository.listCallCount, 1);
    expect(find.text('Tester 님'), findsOneWidget);
  });

  testWidgets('server sign up saves auth repository session', (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings.notifications_enabled': false,
    });
    final repository = _FakeAuthRepository(
      response: const AuthSessionResponse(
        accessToken: 'new-access-token',
        refreshToken: 'new-refresh-token',
        user: AuthUserResponse(id: 'new-user-1', email: 'new@starton.local'),
      ),
    );
    final repositories = _FakeServerRepositories(userName: 'New');

    await tester.pumpWidget(
      AdFocusApp(
        authRepository: repository,
        profileRepository: repositories.profileRepository,
        questRepository: repositories.questRepository,
        statsRepository: repositories.statsRepository,
        dungeonRepository: repositories.dungeonRepository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('가입'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'new@starton.local',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'secret123');
    await tester.tap(find.widgetWithText(FilledButton, '회원가입'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final prefs = await SharedPreferences.getInstance();
    expect(repository.lastAuthAction, _AuthAction.signUp);
    expect(repository.email, 'new@starton.local');
    expect(repository.password, 'secret123');
    expect(prefs.getBool('auth.is_signed_in'), isTrue);
    expect(prefs.getString('auth.user_id'), 'new-user-1');
    expect(prefs.getString('auth.email'), 'new@starton.local');
    expect(prefs.getString('auth.access_token'), 'new-access-token');
    expect(prefs.getString('auth.refresh_token'), 'new-refresh-token');
    expect(repositories.profileRepository.getCallCount, 1);
    expect(repositories.questRepository.listCallCount, 1);
    expect(repositories.statsRepository.getCallCount, 1);
    expect(repositories.dungeonRepository.listCallCount, 1);
    expect(find.text('New 님'), findsOneWidget);
  });

  testWidgets('server login error keeps login screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repository = _FakeAuthRepository(
      error: const AuthRepositoryException(
        code: 'supabase_auth_failed',
        message: 'Invalid login credentials',
      ),
    );

    await tester.pumpWidget(AdFocusApp(authRepository: repository));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'tester@starton.local',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong-password');
    await tester.tap(find.widgetWithText(FilledButton, '로그인'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('auth.is_signed_in'), isNull);
    expect(find.text('이메일 또는 비밀번호를 확인해 주세요.'), findsOneWidget);
    expect(find.text('START ON'), findsOneWidget);
  });

  testWidgets('sign up confirmation error keeps login screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repository = _FakeAuthRepository(
      error: ApiClientException(
        statusCode: 400,
        code: 'signup_requires_confirmation',
        message: 'Email confirmation is required.',
      ),
    );

    await tester.pumpWidget(AdFocusApp(authRepository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('가입'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'new@starton.local',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'secret123');
    await tester.tap(find.widgetWithText(FilledButton, '회원가입'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final prefs = await SharedPreferences.getInstance();
    expect(repository.lastAuthAction, _AuthAction.signUp);
    expect(prefs.getBool('auth.is_signed_in'), isNull);
    expect(
      find.text('가입은 접수됐지만 이메일 확인이 필요해요. 메일 확인 후 로그인해 주세요.'),
      findsOneWidget,
    );
    expect(find.text('이메일을 확인하시오'), findsOneWidget);
    expect(find.text('가입한 이메일로 전송된 인증 메일을 확인한 뒤 로그인해 주세요.'), findsOneWidget);
    expect(find.text('START ON'), findsOneWidget);
  });

  testWidgets('sign up rate limit error explains retry later', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repository = _FakeAuthRepository(
      error: ApiClientException(
        statusCode: 429,
        code: 'supabase_auth_rate_limited',
        message: 'Too many requests.',
      ),
    );

    await tester.pumpWidget(AdFocusApp(authRepository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('가입'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'new@starton.local',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'secret123');
    await tester.tap(find.widgetWithText(FilledButton, '회원가입'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final prefs = await SharedPreferences.getInstance();
    expect(repository.lastAuthAction, _AuthAction.signUp);
    expect(prefs.getBool('auth.is_signed_in'), isNull);
    expect(find.text('회원가입 요청이 너무 많아요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
    expect(find.text('START ON'), findsOneWidget);
  });

  testWidgets('server add quest reviews candidate and confirms task', (
    tester,
  ) async {
    await _setTallTestSurface(tester);
    SharedPreferences.setMockInitialValues({
      'auth.is_signed_in': true,
      'auth.user_id': 'user-1',
      'auth.email': 'tester@starton.local',
      'auth.display_name': 'Tester',
      'auth.access_token': 'access-token',
      'settings.notifications_enabled': false,
    });
    final taskIntakeRepository = _FakeTaskIntakeRepository(
      intakeCandidate: _taskCandidate(),
      commitResult: _taskCommitResult(),
    );
    final repositories = _FakeServerRepositories(
      taskIntakeRepository: taskIntakeRepository,
    );

    await tester.pumpWidget(
      AdFocusApp(
        profileRepository: repositories.profileRepository,
        questRepository: repositories.questRepository,
        statsRepository: repositories.statsRepository,
        dungeonRepository: repositories.dungeonRepository,
        taskIntakeRepository: repositories.taskIntakeRepository,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    expect(find.text('AI 제안 페이지로 이동'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '컴비전 과제');
    await tester.tap(find.text('AI 제안 페이지로 이동'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();

    expect(taskIntakeRepository.createRequests.single.text, '컴비전 과제');
    expect(find.text('AI 제안 확인'), findsOneWidget);
    expect(find.text('컴퓨터비전 과제 제출 준비'), findsOneWidget);

    await tester.tap(find.text('이대로 저장'));
    await tester.pumpAndSettle();

    expect(
      taskIntakeRepository.confirmRequests.single.candidateId,
      'candidate-1',
    );
    expect(
      taskIntakeRepository.confirmRequests.single.request.selectedSubtaskIds,
      ['subtask-1', 'subtask-2'],
    );
    expect(find.text('컴퓨터비전 과제 제출 준비'), findsOneWidget);

    Future<Map<String, dynamic>> readSavedQuest() async {
      final prefs = await SharedPreferences.getInstance();
      final rawLocalData = prefs.getString('ad_focus.local_data');
      final localData = jsonDecode(rawLocalData!) as Map<String, dynamic>;
      final quests = localData['quests'] as List<Object?>;
      return quests.cast<Map<String, dynamic>>().firstWhere(
        (quest) => quest['id'] == 'task-1',
      );
    }

    final savedQuest = await readSavedQuest();
    expect(savedQuest['syncTarget'], questSyncTargetTask);
    final savedSubtasks = savedQuest['subtasks'] as List<Object?>;
    expect(savedSubtasks, hasLength(2));
    expect(
      savedSubtasks.cast<Map<String, dynamic>>().map((item) => item['title']),
      ['과제 파일 열기', '요구사항 체크리스트 만들기'],
    );
    expect(repositories.questRepository.updateCallCount, 0);

    await tester.tap(find.text('컴퓨터비전 과제 제출 준비').first);
    await tester.pumpAndSettle();

    expect(find.text('세부 단계'), findsOneWidget);
    expect(find.text('과제 파일 열기'), findsOneWidget);
    expect(find.text('요구사항 체크리스트 만들기'), findsOneWidget);
    expect(find.text('진행 중 · 0:00/5:00 · 낮은 에너지'), findsOneWidget);

    await tester.tap(find.text('요구사항 체크리스트 만들기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('다음 행동 · 0:00/5:00 · 낮은 에너지'), findsOneWidget);
    expect(find.text('진행 중 · 0:00/10:00 · 보통 에너지'), findsOneWidget);
    final activePlayIcons = tester
        .widgetList<Icon>(find.byIcon(Icons.play_circle_fill_rounded))
        .where((icon) => icon.color == const Color(0xFF6F63FF));
    expect(activePlayIcons, hasLength(1));
    final savedAfterSecondSelected = await readSavedQuest();
    expect(savedAfterSecondSelected['activeSubtaskId'], 'task-subtask-2');
    final subtaskAfterSecondSelected =
        (savedAfterSecondSelected['subtasks'] as List<Object?>)
            .cast<Map<String, dynamic>>()
            .firstWhere((item) => item['id'] == 'task-subtask-1');
    expect(subtaskAfterSecondSelected['status'], 'todo');
    expect(subtaskAfterSecondSelected['completedAt'], isNull);
    expect(subtaskAfterSecondSelected['elapsedSeconds'], 0);
    expect(repositories.questRepository.updateCallCount, 0);

    await tester.tap(find.text('과제 파일 열기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('진행 중 · 0:00/5:00 · 낮은 에너지'), findsOneWidget);
    final savedAfterReopen = await readSavedQuest();
    expect(savedAfterReopen['activeSubtaskId'], 'task-subtask-1');
    final subtaskAfterReopen = (savedAfterReopen['subtasks'] as List<Object?>)
        .cast<Map<String, dynamic>>()
        .firstWhere((item) => item['id'] == 'task-subtask-1');
    expect(subtaskAfterReopen['status'], 'todo');
    expect(subtaskAfterReopen['completedAt'], isNull);
    expect(subtaskAfterReopen['elapsedSeconds'], 0);
    expect(repositories.questRepository.updateCallCount, 0);
  });

  testWidgets('server add quest creates regular quest without AI candidate', (
    tester,
  ) async {
    await _setTallTestSurface(tester);
    SharedPreferences.setMockInitialValues({
      'auth.is_signed_in': true,
      'auth.user_id': 'user-1',
      'auth.email': 'tester@starton.local',
      'auth.display_name': 'Tester',
      'auth.access_token': 'access-token',
      'settings.notifications_enabled': false,
    });
    final taskIntakeRepository = _FakeTaskIntakeRepository();
    final repositories = _FakeServerRepositories(
      taskIntakeRepository: taskIntakeRepository,
    );

    await tester.pumpWidget(
      AdFocusApp(
        profileRepository: repositories.profileRepository,
        questRepository: repositories.questRepository,
        statsRepository: repositories.statsRepository,
        dungeonRepository: repositories.dungeonRepository,
        taskIntakeRepository: repositories.taskIntakeRepository,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '일반 과제');
    await tester.tap(find.text('Create task'));
    await tester.pumpAndSettle();

    expect(taskIntakeRepository.createRequests, isEmpty);
    expect(repositories.questRepository.createRequests.single.title, '일반 과제');
    expect(find.text('AI 제안 확인'), findsNothing);
    expect(find.text('일반 과제'), findsOneWidget);
  });

  testWidgets('server add quest can save manually entered subtasks locally', (
    tester,
  ) async {
    await _setTallTestSurface(tester);
    SharedPreferences.setMockInitialValues({
      'auth.is_signed_in': true,
      'auth.user_id': 'user-1',
      'auth.email': 'tester@starton.local',
      'auth.display_name': 'Tester',
      'auth.access_token': 'access-token',
      'settings.notifications_enabled': false,
    });
    final taskIntakeRepository = _FakeTaskIntakeRepository(
      intakeCandidate: _taskCandidate(),
      commitResult: _taskCommitResult(),
    );
    final repositories = _FakeServerRepositories(
      taskIntakeRepository: taskIntakeRepository,
    );

    await tester.pumpWidget(
      AdFocusApp(
        profileRepository: repositories.profileRepository,
        questRepository: repositories.questRepository,
        statsRepository: repositories.statsRepository,
        dungeonRepository: repositories.dungeonRepository,
        taskIntakeRepository: repositories.taskIntakeRepository,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '직접 과제');
    await tester.tap(find.text('직접 입력'));
    await tester.pump();
    await tester.enterText(
      find.byType(TextField).at(1),
      '자료 열기 / 10분\n정리하기 / 15분',
    );
    await tester.tap(find.text('Create task'));
    await tester.pumpAndSettle();

    expect(taskIntakeRepository.createRequests, isEmpty);
    expect(find.text('AI 제안 확인'), findsNothing);
    expect(find.text('직접 과제'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    final rawLocalData = prefs.getString('ad_focus.local_data');
    final localData = jsonDecode(rawLocalData!) as Map<String, dynamic>;
    final quests = localData['quests'] as List<Object?>;
    final savedQuest = quests.cast<Map<String, dynamic>>().firstWhere(
      (quest) => quest['title'] == '직접 과제',
    );

    expect(savedQuest['syncTarget'], questSyncTargetLocal);
    expect(savedQuest['activeSubtaskId'], isA<String>());
    final savedSubtasks = (savedQuest['subtasks'] as List<Object?>)
        .cast<Map<String, dynamic>>();
    expect(savedSubtasks.map((item) => item['title']), ['자료 열기', '정리하기']);
    expect(savedSubtasks.map((item) => item['estimatedMinutes']), [10, 15]);
    expect(savedSubtasks.first['id'], savedQuest['activeSubtaskId']);
    expect(savedSubtasks.first['isNextAction'], isTrue);
  });

  testWidgets('server add quest shows AI creation loading before review', (
    tester,
  ) async {
    await _setTallTestSurface(tester);
    SharedPreferences.setMockInitialValues({
      'auth.is_signed_in': true,
      'auth.user_id': 'user-1',
      'auth.email': 'tester@starton.local',
      'auth.display_name': 'Tester',
      'auth.access_token': 'access-token',
      'settings.notifications_enabled': false,
    });
    final createCompleter = Completer<TaskIntakeResponse>();
    final candidate = _taskCandidate();
    final taskIntakeRepository = _FakeTaskIntakeRepository(
      intakeCandidate: candidate,
      createIntakeCompleter: createCompleter,
    );
    final repositories = _FakeServerRepositories(
      taskIntakeRepository: taskIntakeRepository,
    );

    await tester.pumpWidget(
      AdFocusApp(
        profileRepository: repositories.profileRepository,
        questRepository: repositories.questRepository,
        statsRepository: repositories.statsRepository,
        dungeonRepository: repositories.dungeonRepository,
        taskIntakeRepository: repositories.taskIntakeRepository,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '컴비전 과제');
    await tester.tap(find.text('AI 제안 페이지로 이동'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다음'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(taskIntakeRepository.createRequests.single.text, '컴비전 과제');
    expect(find.text('AI 퀘스트 생성 중...'), findsOneWidget);
    expect(find.text('AI 제안 페이지를 준비하고 있어요.'), findsOneWidget);
    expect(find.textContaining('%'), findsOneWidget);
    expect(find.text('AI 제안 확인'), findsNothing);

    createCompleter.complete(
      TaskIntakeResponse(
        rawInputId: candidate.rawInputId,
        candidateId: candidate.id,
        status: 'candidate_ready',
        candidate: candidate,
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('AI 퀘스트 생성 중...'), findsNothing);
    expect(find.text('AI 제안 확인'), findsOneWidget);
    expect(find.text('컴퓨터비전 과제 제출 준비'), findsOneWidget);
  });

  testWidgets('server add quest shows shimmer while saving AI quest', (
    tester,
  ) async {
    await _setTallTestSurface(tester);
    SharedPreferences.setMockInitialValues({
      'auth.is_signed_in': true,
      'auth.user_id': 'user-1',
      'auth.email': 'tester@starton.local',
      'auth.display_name': 'Tester',
      'auth.access_token': 'access-token',
      'settings.notifications_enabled': false,
    });
    final confirmCompleter = Completer<TaskCommitResultResponse>();
    final taskIntakeRepository = _FakeTaskIntakeRepository(
      intakeCandidate: _taskCandidate(),
      confirmCompleter: confirmCompleter,
    );
    final repositories = _FakeServerRepositories(
      taskIntakeRepository: taskIntakeRepository,
    );

    await tester.pumpWidget(
      AdFocusApp(
        profileRepository: repositories.profileRepository,
        questRepository: repositories.questRepository,
        statsRepository: repositories.statsRepository,
        dungeonRepository: repositories.dungeonRepository,
        taskIntakeRepository: repositories.taskIntakeRepository,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '컴비전 과제');
    await tester.tap(find.text('AI 제안 페이지로 이동'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('이대로 저장'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      taskIntakeRepository.confirmRequests.single.candidateId,
      'candidate-1',
    );
    expect(find.text('AI 퀘스트 저장 중...'), findsOneWidget);

    confirmCompleter.complete(_taskCommitResult());
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('AI 퀘스트 저장 중...'), findsNothing);
    expect(find.text('컴퓨터비전 과제 제출 준비'), findsOneWidget);
  });

  testWidgets('server add quest cancel rejects candidate without adding task', (
    tester,
  ) async {
    await _setTallTestSurface(tester);
    SharedPreferences.setMockInitialValues({
      'auth.is_signed_in': true,
      'auth.user_id': 'user-1',
      'auth.email': 'tester@starton.local',
      'auth.display_name': 'Tester',
      'auth.access_token': 'access-token',
      'settings.notifications_enabled': false,
    });
    final taskIntakeRepository = _FakeTaskIntakeRepository(
      intakeCandidate: _taskCandidate(),
      commitResult: _taskCommitResult(),
    );
    final repositories = _FakeServerRepositories(
      taskIntakeRepository: taskIntakeRepository,
    );

    await tester.pumpWidget(
      AdFocusApp(
        profileRepository: repositories.profileRepository,
        questRepository: repositories.questRepository,
        statsRepository: repositories.statsRepository,
        dungeonRepository: repositories.dungeonRepository,
        taskIntakeRepository: repositories.taskIntakeRepository,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '취소할 과제');
    await tester.tap(find.text('AI 제안 페이지로 이동'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(
      taskIntakeRepository.rejectRequests.single.reason,
      'cancelled_from_review',
    );
    expect(taskIntakeRepository.confirmRequests, isEmpty);
    expect(find.text('컴퓨터비전 과제 제출 준비'), findsNothing);
  });

  testWidgets('guest add quest keeps local creation flow', (tester) async {
    await _setTallTestSurface(tester);
    SharedPreferences.setMockInitialValues({
      'settings.notifications_enabled': false,
    });

    await tester.pumpWidget(const AdFocusApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('게스트로 시작'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '로컬 퀘스트');
    await tester.tap(find.text('Create task'));
    await tester.pumpAndSettle();

    expect(find.text('AI 제안 확인'), findsNothing);
    expect(find.text('로컬 퀘스트'), findsOneWidget);
  });
}

Future<void> _setTallTestSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

enum _AuthAction { signIn, signUp }

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({this.response, this.error})
    : super(apiClient: _UnusedApiClient());

  final AuthSessionResponse? response;
  final Object? error;
  String? email;
  String? password;
  _AuthAction? lastAuthAction;

  @override
  Future<AuthSessionResponse> signIn({
    required String email,
    required String password,
  }) async {
    lastAuthAction = _AuthAction.signIn;
    this.email = email;
    this.password = password;

    final error = this.error;
    if (error != null) {
      throw error;
    }

    return response!;
  }

  @override
  Future<AuthSessionResponse> signUp({
    required String email,
    required String password,
  }) async {
    lastAuthAction = _AuthAction.signUp;
    this.email = email;
    this.password = password;

    final error = this.error;
    if (error != null) {
      throw error;
    }

    return response!;
  }

  @override
  void close() {}
}

class _FakeServerRepositories {
  _FakeServerRepositories({
    String userName = 'Tester',
    _FakeTaskIntakeRepository? taskIntakeRepository,
  }) : profileRepository = _FakeProfileRepository(userName: userName),
       questRepository = _FakeQuestRepository(),
       statsRepository = _FakeStatsRepository(),
       dungeonRepository = _FakeDungeonRepository(),
       taskIntakeRepository =
           taskIntakeRepository ?? _FakeTaskIntakeRepository();

  final _FakeProfileRepository profileRepository;
  final _FakeQuestRepository questRepository;
  final _FakeStatsRepository statsRepository;
  final _FakeDungeonRepository dungeonRepository;
  final _FakeTaskIntakeRepository taskIntakeRepository;
}

class _FakeProfileRepository extends ProfileRepository {
  _FakeProfileRepository({
    required this.userName,
    this.responseCompleter,
    this.error,
  }) : super(apiClient: _UnusedApiClient());

  final String userName;
  final Completer<ProfileResponse>? responseCompleter;
  final Object? error;
  int getCallCount = 0;

  @override
  Future<ProfileResponse> getProfile() async {
    getCallCount += 1;
    final error = this.error;
    if (error != null) {
      throw error;
    }

    final responseCompleter = this.responseCompleter;
    if (responseCompleter != null) {
      return responseCompleter.future;
    }

    return _profileResponse(userName);
  }

  @override
  void close() {}
}

ProfileResponse _profileResponse(String userName) {
  return ProfileResponse(
    userName: userName,
    userRole: 'Beginner',
    level: 0,
    currentExp: 0,
    maxExp: 500,
    credits: 0,
    completedQuestCount: 0,
    earnedExp: 0,
  );
}

class _FakeQuestRepository extends QuestRepository {
  _FakeQuestRepository({List<QuestItemResponse>? quests})
    : quests = quests ?? const [],
      super(apiClient: _UnusedApiClient());

  final List<QuestItemResponse> quests;
  final List<QuestCreateRequest> createRequests = [];
  int listCallCount = 0;
  int updateCallCount = 0;

  @override
  Future<List<QuestItemResponse>> listQuests() async {
    listCallCount += 1;
    return quests;
  }

  @override
  Future<QuestItemResponse> createQuest(QuestCreateRequest request) async {
    createRequests.add(request);
    return QuestItemResponse(
      id: 'created-quest',
      title: request.title,
      exp: request.exp,
      difficulty: request.difficulty,
      category: request.category,
      elapsedSeconds: 0,
      defaultDurationSeconds: request.defaultDurationSeconds,
      dueAt: request.dueAt,
    );
  }

  @override
  Future<QuestItemResponse> updateQuest(
    String questId,
    QuestUpdateRequest request,
  ) async {
    updateCallCount += 1;
    return QuestItemResponse(
      id: questId,
      title: request.title,
      exp: request.exp,
      difficulty: request.difficulty,
      category: request.category,
      elapsedSeconds: request.elapsedSeconds,
      defaultDurationSeconds: request.defaultDurationSeconds,
    );
  }

  @override
  void close() {}
}

class _FakeStatsRepository extends StatsRepository {
  _FakeStatsRepository() : super(apiClient: _UnusedApiClient());

  int getCallCount = 0;

  @override
  Future<StatsSummaryResponse> getSummary() async {
    getCallCount += 1;
    return const StatsSummaryResponse(
      dailyRewardCount: 0,
      dailyRewardTarget: 3,
      weeklyRewardCount: 0,
      weeklyRewardTarget: 7,
      monthlyRewardCount: 0,
      monthlyRewardTarget: 30,
      weeklyCompletedCount: 0,
      weeklyCompletionRate: 0,
      weeklyRateDelta: 0,
      diligenceStat: 0,
      orderStat: 0,
      intelligenceStat: 0,
      healthStat: 0,
    );
  }

  @override
  void close() {}
}

class _FakeDungeonRepository extends DungeonRepository {
  _FakeDungeonRepository() : super(apiClient: _UnusedApiClient());

  int listCallCount = 0;

  @override
  Future<DungeonListResponse> listDungeons() async {
    listCallCount += 1;
    return const DungeonListResponse(dungeons: []);
  }

  @override
  void close() {}
}

class _FakeTaskIntakeRepository extends TaskIntakeRepository {
  _FakeTaskIntakeRepository({
    TaskCandidateResponse? intakeCandidate,
    TaskCommitResultResponse? commitResult,
    TaskCandidateResponse? revisedCandidate,
    this.createIntakeCompleter,
    this.confirmCompleter,
  }) : intakeCandidate = intakeCandidate ?? _taskCandidate(),
       commitResult = commitResult ?? _taskCommitResult(),
       revisedCandidate =
           revisedCandidate ?? intakeCandidate ?? _taskCandidate(),
       super(apiClient: _UnusedApiClient());

  final TaskCandidateResponse intakeCandidate;
  final TaskCommitResultResponse commitResult;
  final TaskCandidateResponse revisedCandidate;
  final Completer<TaskIntakeResponse>? createIntakeCompleter;
  final Completer<TaskCommitResultResponse>? confirmCompleter;
  final List<TaskIntakeRequest> createRequests = [];
  final List<String> getCandidateRequests = [];
  final List<_ConfirmCandidateCall> confirmRequests = [];
  final List<_ReviseCandidateCall> reviseRequests = [];
  final List<_RejectCandidateCall> rejectRequests = [];

  @override
  Future<TaskIntakeResponse> createIntake(TaskIntakeRequest request) async {
    createRequests.add(request);
    final createIntakeCompleter = this.createIntakeCompleter;
    if (createIntakeCompleter != null) {
      return createIntakeCompleter.future;
    }

    return TaskIntakeResponse(
      rawInputId: intakeCandidate.rawInputId,
      candidateId: intakeCandidate.id,
      status: 'candidate_ready',
      candidate: intakeCandidate,
    );
  }

  @override
  Future<TaskCandidateResponse> getCandidate(String candidateId) async {
    getCandidateRequests.add(candidateId);
    return intakeCandidate;
  }

  @override
  Future<TaskCommitResultResponse> confirmCandidate(
    String candidateId,
    TaskConfirmRequest request,
  ) async {
    confirmRequests.add(
      _ConfirmCandidateCall(candidateId: candidateId, request: request),
    );
    final confirmCompleter = this.confirmCompleter;
    if (confirmCompleter != null) {
      return confirmCompleter.future;
    }

    return commitResult;
  }

  @override
  Future<TaskCandidateResponse> reviseCandidate(
    String candidateId,
    TaskCandidateReviseRequest request,
  ) async {
    reviseRequests.add(
      _ReviseCandidateCall(candidateId: candidateId, request: request),
    );
    return revisedCandidate;
  }

  @override
  Future<TaskCandidateResponse> rejectCandidate(
    String candidateId,
    TaskCandidateRejectRequest request,
  ) async {
    rejectRequests.add(
      _RejectCandidateCall(candidateId: candidateId, request: request),
    );
    return intakeCandidate;
  }

  @override
  void close() {}
}

class _ConfirmCandidateCall {
  const _ConfirmCandidateCall({
    required this.candidateId,
    required this.request,
  });

  final String candidateId;
  final TaskConfirmRequest request;
}

class _ReviseCandidateCall {
  const _ReviseCandidateCall({
    required this.candidateId,
    required this.request,
  });

  final String candidateId;
  final TaskCandidateReviseRequest request;
}

class _RejectCandidateCall {
  const _RejectCandidateCall({
    required this.candidateId,
    required this.request,
  });

  final String candidateId;
  final TaskCandidateRejectRequest request;

  String? get reason => request.reason;
}

TaskCandidateResponse _taskCandidate() {
  return TaskCandidateResponse(
    id: 'candidate-1',
    userId: 'user-1',
    rawInputId: 'raw-1',
    mediatorRunId: 'run-1',
    title: '컴퓨터비전 과제 제출 준비',
    description: '과제 요구사항 확인부터 시작',
    dueAt: DateTime.parse('2026-05-15T20:00:00+09:00'),
    priority: 'high',
    estimatedMinutes: 120,
    energyRequired: 'medium',
    difficulty: 'high',
    nextAction: '과제 파일을 열고 요구사항만 확인하기',
    recommendedToday: true,
    todayReason: '오늘은 첫 단계만 진행',
    overloadWarning: null,
    confidence: 0.82,
    status: 'draft',
    modelPayload: const <String, dynamic>{},
    subtasks: const [
      CandidateSubtaskResponse(
        id: 'subtask-1',
        candidateId: 'candidate-1',
        title: '과제 파일 열기',
        orderIndex: 0,
        estimatedMinutes: 5,
        isNextAction: true,
        energyRequired: 'low',
        createdAt: null,
        updatedAt: null,
      ),
      CandidateSubtaskResponse(
        id: 'subtask-2',
        candidateId: 'candidate-1',
        title: '요구사항 체크리스트 만들기',
        orderIndex: 1,
        estimatedMinutes: 10,
        isNextAction: false,
        energyRequired: 'medium',
        createdAt: null,
        updatedAt: null,
      ),
    ],
    reminders: const <CandidateReminderResponse>[],
    createdAt: null,
    updatedAt: null,
  );
}

TaskCommitResultResponse _taskCommitResult() {
  return const TaskCommitResultResponse(
    candidateId: 'candidate-1',
    task: TaskResponse(
      id: 'task-1',
      userId: 'user-1',
      candidateId: 'candidate-1',
      rawInputId: 'raw-1',
      mediatorRunId: 'run-1',
      title: '컴퓨터비전 과제 제출 준비',
      description: '과제 요구사항 확인부터 시작',
      status: 'todo',
      priority: 'high',
      dueAt: null,
      estimatedMinutes: 120,
      energyRequired: 'medium',
      difficulty: 'high',
      nextAction: '과제 파일 열기',
      source: 'ai',
      metadata: <String, dynamic>{},
      subtasks: <SubtaskResponse>[
        SubtaskResponse(
          id: 'task-subtask-1',
          taskId: 'task-1',
          userId: 'user-1',
          candidateSubtaskId: 'subtask-1',
          title: '과제 파일 열기',
          orderIndex: 0,
          estimatedMinutes: 5,
          status: 'todo',
          isNextAction: true,
          energyRequired: 'low',
          createdAt: null,
          updatedAt: null,
          completedAt: null,
        ),
        SubtaskResponse(
          id: 'task-subtask-2',
          taskId: 'task-1',
          userId: 'user-1',
          candidateSubtaskId: 'subtask-2',
          title: '요구사항 체크리스트 만들기',
          orderIndex: 1,
          estimatedMinutes: 10,
          status: 'todo',
          isNextAction: false,
          energyRequired: 'medium',
          createdAt: null,
          updatedAt: null,
          completedAt: null,
        ),
      ],
      reminders: <ReminderResponse>[],
      createdAt: null,
      updatedAt: null,
      completedAt: null,
    ),
  );
}

class _UnusedApiClient extends ApiClient {
  _UnusedApiClient() : super(baseUrl: 'http://localhost');
}
