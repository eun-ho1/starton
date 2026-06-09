import 'dart:async';

import 'package:start_on/models/app_local_data.dart';
import 'package:start_on/models/dungeon_api_models.dart';
import 'package:start_on/models/leaderboard_api_models.dart';
import 'package:start_on/models/profile_api_models.dart';
import 'package:start_on/models/quest_api_models.dart';
import 'package:start_on/models/stats_api_models.dart';
import 'package:start_on/models/task_intake_api_models.dart';
import 'package:start_on/models/task_quest_mapper.dart';
import 'package:start_on/pages/add_quest_screen.dart';
import 'package:start_on/pages/home_screen.dart';
import 'package:start_on/pages/login_screen.dart';
import 'package:start_on/pages/quest_timer/quest_timer_bottom_sheet.dart';
import 'package:start_on/pages/quest_timer_screen.dart';
import 'package:start_on/pages/ranking_screen.dart';
import 'package:start_on/pages/record_screen.dart';
import 'package:start_on/pages/retry_screen.dart';
import 'package:start_on/pages/settings_screen.dart';
import 'package:start_on/pages/task_candidate_review_screen.dart';
import 'package:start_on/repositories/auth_repository.dart';
import 'package:start_on/repositories/dungeon_repository.dart';
import 'package:start_on/repositories/leaderboard_repository.dart';
import 'package:start_on/repositories/profile_repository.dart';
import 'package:start_on/repositories/quest_repository.dart';
import 'package:start_on/repositories/stats_repository.dart';
import 'package:start_on/repositories/task_intake_repository.dart';
import 'package:start_on/services/api_client.dart';
import 'package:start_on/services/quest_timer_background_service.dart';
import 'package:start_on/storage/app_settings_store.dart';
import 'package:start_on/storage/auth_session_store.dart';
import 'package:start_on/storage/local_data_store.dart';
import 'package:start_on/widgets/ai_quest_creation_progress_overlay.dart';
import 'package:start_on/widgets/common.dart';
import 'package:start_on/widgets/quest_completion_celebration.dart';
import 'package:start_on/widgets/loading_cat_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

const _systemUiOverlayStyle = SystemUiOverlayStyle(
  systemNavigationBarColor: Color(0xFFF1F3F8),
  systemNavigationBarIconBrightness: Brightness.dark,
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
);
const Duration _questAutoAdvanceRestDuration = Duration(seconds: 15);

enum _CompletionAfterAction {
  saveOnly,
  undo,
  continueRemaining,
  postponeRemaining,
}

class AdFocusApp extends StatelessWidget {
  const AdFocusApp({
    super.key,
    AuthRepository? authRepository,
    ProfileRepository? profileRepository,
    QuestRepository? questRepository,
    StatsRepository? statsRepository,
    DungeonRepository? dungeonRepository,
    LeaderboardRepository? leaderboardRepository,
    TaskIntakeRepository? taskIntakeRepository,
  }) : _authRepository = authRepository,
       _profileRepository = profileRepository,
       _questRepository = questRepository,
       _statsRepository = statsRepository,
       _dungeonRepository = dungeonRepository,
       _leaderboardRepository = leaderboardRepository,
       _taskIntakeRepository = taskIntakeRepository;

  final AuthRepository? _authRepository;
  final ProfileRepository? _profileRepository;
  final QuestRepository? _questRepository;
  final StatsRepository? _statsRepository;
  final DungeonRepository? _dungeonRepository;
  final LeaderboardRepository? _leaderboardRepository;
  final TaskIntakeRepository? _taskIntakeRepository;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _systemUiOverlayStyle,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Start On',
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF1F3F8),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6F63FF),
            brightness: Brightness.light,
          ),
          fontFamily: 'Pretendard',
        ),
        home: _AuthGate(
          authRepository: _authRepository,
          profileRepository: _profileRepository,
          questRepository: _questRepository,
          statsRepository: _statsRepository,
          dungeonRepository: _dungeonRepository,
          leaderboardRepository: _leaderboardRepository,
          taskIntakeRepository: _taskIntakeRepository,
        ),
      ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate({
    this.authRepository,
    this.profileRepository,
    this.questRepository,
    this.statsRepository,
    this.dungeonRepository,
    this.leaderboardRepository,
    this.taskIntakeRepository,
  });

  final AuthRepository? authRepository;
  final ProfileRepository? profileRepository;
  final QuestRepository? questRepository;
  final StatsRepository? statsRepository;
  final DungeonRepository? dungeonRepository;
  final LeaderboardRepository? leaderboardRepository;
  final TaskIntakeRepository? taskIntakeRepository;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  final AuthSessionStore _authStore = const AuthSessionStore();

  late final AuthRepository _authRepository;
  late final bool _ownsAuthRepository;
  AuthSession? _session;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? AuthRepository();
    _ownsAuthRepository = widget.authRepository == null;
    unawaited(_loadSession());
  }

  @override
  void dispose() {
    if (_ownsAuthRepository) {
      _authRepository.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(color: Color(0xFFF1F3F8)),
          child: const Center(child: LoadingCatIndicator()),
        ),
      );
    }

    final session = _session;
    if (session == null) {
      return LoginScreen(
        onSignIn: _handleServerSignIn,
        onSignUp: _handleServerSignUp,
        onGuestStart: _handleGuestStart,
      );
    }

    return AdFocusShell(
      session: session,
      onChangeAccount: _handleAccountChange,
      profileRepository: widget.profileRepository,
      questRepository: widget.questRepository,
      statsRepository: widget.statsRepository,
      dungeonRepository: widget.dungeonRepository,
      leaderboardRepository: widget.leaderboardRepository,
      taskIntakeRepository: widget.taskIntakeRepository,
    );
  }

  Future<void> _loadSession() async {
    final session = await _authStore.load();
    if (!mounted) {
      return;
    }

    setState(() {
      _session = session;
      _isLoading = false;
    });
  }

  Future<void> _handleServerSignIn({
    required String email,
    required String password,
  }) async {
    final response = await _authRepository.signIn(
      email: email,
      password: password,
    );
    await _saveSession(AuthSession.fromAuthResponse(response));
  }

  Future<void> _handleServerSignUp({
    required String email,
    required String password,
  }) async {
    final response = await _authRepository.signUp(
      email: email,
      password: password,
    );
    await _saveSession(AuthSession.fromAuthResponse(response));
  }

  Future<void> _handleGuestStart() {
    return _saveSession(
      AuthSession.local(email: 'guest@starton.local', displayName: '게스트'),
    );
  }

  Future<void> _saveSession(AuthSession session) async {
    await _authStore.save(session);

    if (!mounted) {
      return;
    }
    setState(() => _session = session);
  }

  Future<void> _handleAccountChange() async {
    await _authStore.clear();
    if (!mounted) {
      return;
    }
    setState(() => _session = null);
  }
}

class _BottomNavCenterFabLocation extends FloatingActionButtonLocation {
  const _BottomNavCenterFabLocation();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final fabSize = scaffoldGeometry.floatingActionButtonSize;
    final bottomBarHeight =
        scaffoldGeometry.scaffoldSize.height - scaffoldGeometry.contentBottom;

    return Offset(
      (scaffoldGeometry.scaffoldSize.width - fabSize.width) / 2,
      scaffoldGeometry.contentBottom +
          (bottomBarHeight - fabSize.height) / 2 -
          18,
    );
  }
}

class AdFocusShell extends StatefulWidget {
  const AdFocusShell({
    required this.session,
    required this.onChangeAccount,
    this.profileRepository,
    this.questRepository,
    this.statsRepository,
    this.dungeonRepository,
    this.leaderboardRepository,
    this.taskIntakeRepository,
    super.key,
  });

  final AuthSession session;
  final Future<void> Function() onChangeAccount;
  final ProfileRepository? profileRepository;
  final QuestRepository? questRepository;
  final StatsRepository? statsRepository;
  final DungeonRepository? dungeonRepository;
  final LeaderboardRepository? leaderboardRepository;
  final TaskIntakeRepository? taskIntakeRepository;

  @override
  State<AdFocusShell> createState() => _AdFocusShellState();
}

class _AdFocusShellState extends State<AdFocusShell>
    with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AppSettingsStore _settingsStore = const AppSettingsStore();
  final LocalDataStore _store = const LocalDataStore();
  final QuestTimerBackgroundService _questTimerService =
      QuestTimerBackgroundService.instance;

  late final ProfileRepository? _profileRepository;
  late final QuestRepository? _questRepository;
  late final StatsRepository? _statsRepository;
  late final DungeonRepository? _dungeonRepository;
  late final LeaderboardRepository? _leaderboardRepository;
  late final TaskIntakeRepository? _taskIntakeRepository;
  late final bool _usesServerData;
  late final bool _ownsProfileRepository;
  late final bool _ownsQuestRepository;
  late final bool _ownsStatsRepository;
  late final bool _ownsDungeonRepository;
  late final bool _ownsLeaderboardRepository;
  late final bool _ownsTaskIntakeRepository;
  int _currentIndex = 0;
  int _celebrationSeed = 0;
  bool _isLoading = true;
  bool _isCreatingAiQuest = false;
  bool _isSavingAiQuest = false;
  bool _isSavingCompletedQuest = false;
  bool _isDeletingQuests = false;
  bool _isOpeningQuestTimer = false;
  bool _isQuestTimerRouteOpen = false;
  bool _isQuestTimerBottomSheetOpen = false;
  bool _didShowLaunchQuestTimerSheet = false;
  bool _notificationsEnabled = true;
  bool _showQuestCelebration = false;
  int _deletingQuestCount = 0;
  int _questAutoAdvanceRemainingSeconds = 0;
  AppLocalData _localData = AppLocalData.initial();
  final Set<String> _skippedRetryQuestIds = <String>{};
  LeaderboardResponse? _leaderboard;
  Timer? _questAutoAdvanceTimer;
  String? _questAutoAdvanceQuestId;
  PersistentBottomSheetController? _questTimerBottomSheetController;
  StreamSubscription<QuestTimerSnapshot>? _questTimerTickSubscription;
  late final AnimationController _fabPopController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _fabPopScale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1,
        end: 1.16,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 42,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1.16,
        end: 0.94,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 28,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 0.94,
        end: 1,
      ).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 30,
    ),
  ]).animate(_fabPopController);

  @override
  void initState() {
    super.initState();
    _usesServerData =
        !widget.session.isLocalOnly && widget.session.hasBearerToken;

    final hasInjectedServerRepository =
        widget.profileRepository != null ||
        widget.questRepository != null ||
        widget.statsRepository != null ||
        widget.dungeonRepository != null ||
        widget.leaderboardRepository != null ||
        widget.taskIntakeRepository != null;
    final shouldCreateDefaultServerRepositories =
        _usesServerData && !hasInjectedServerRepository;

    _profileRepository = _usesServerData
        ? widget.profileRepository ??
              (shouldCreateDefaultServerRepositories ? ProfileRepository() : null)
        : null;
    _questRepository = _usesServerData
        ? widget.questRepository ??
              (shouldCreateDefaultServerRepositories ? QuestRepository() : null)
        : null;
    _statsRepository = _usesServerData
        ? widget.statsRepository ??
              (shouldCreateDefaultServerRepositories ? StatsRepository() : null)
        : null;
    _dungeonRepository = _usesServerData
        ? widget.dungeonRepository ??
              (shouldCreateDefaultServerRepositories ? DungeonRepository() : null)
        : null;
    _leaderboardRepository = _usesServerData
        ? widget.leaderboardRepository ??
              (shouldCreateDefaultServerRepositories
                  ? LeaderboardRepository()
                  : null)
        : null;
    _taskIntakeRepository = _usesServerData
        ? widget.taskIntakeRepository ??
              (shouldCreateDefaultServerRepositories
                  ? TaskIntakeRepository()
                  : null)
        : null;
    _ownsProfileRepository =
        shouldCreateDefaultServerRepositories && widget.profileRepository == null;
    _ownsQuestRepository =
        shouldCreateDefaultServerRepositories && widget.questRepository == null;
    _ownsStatsRepository =
        shouldCreateDefaultServerRepositories && widget.statsRepository == null;
    _ownsDungeonRepository =
        shouldCreateDefaultServerRepositories && widget.dungeonRepository == null;
    _ownsLeaderboardRepository =
        shouldCreateDefaultServerRepositories && widget.leaderboardRepository == null;
    _ownsTaskIntakeRepository =
        shouldCreateDefaultServerRepositories && widget.taskIntakeRepository == null;
    _listenToQuestTimerTicks();
    unawaited(_initializeAppState());
  }

  @override
  void dispose() {
    _lifecycleObserver.dispose();
    _questAutoAdvanceTimer?.cancel();
    _questTimerTickSubscription?.cancel();
    _fabPopController.dispose();
    if (_ownsProfileRepository) {
      _profileRepository?.close();
    }
    if (_ownsQuestRepository) {
      _questRepository?.close();
    }
    if (_ownsStatsRepository) {
      _statsRepository?.close();
    }
    if (_ownsDungeonRepository) {
      _dungeonRepository?.close();
    }
    if (_ownsLeaderboardRepository) {
      _leaderboardRepository?.close();
    }
    if (_ownsTaskIntakeRepository) {
      _taskIntakeRepository?.close();
    }
    super.dispose();
  }

  late final AppLifecycleListener _lifecycleObserver = AppLifecycleListener(
    onResume: _handleAppResumed,
  );

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      final loadingMessage = _usesServerData
          ? '서버 데이터 불러오는 중...'
          : '앱 데이터 불러오는 중...';
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(color: Color(0xFFF1F3F8)),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_usesServerData)
                  const LoadingCatIndicator()
                else
                  const CircularProgressIndicator(color: Color(0xFF6F63FF)),
                const SizedBox(height: 16),
                Text(
                  loadingMessage,
                  style: const TextStyle(
                    color: Color(0xFF495063),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final screens = [
      HomeScreen(
        data: _homeData,
        userName: _homeUserName,
        onAddQuest: _openAddQuest,
        onAddQuestForCategory: _openAddQuestForCategory,
        onQuestTap: _openQuestTimer,
        onDeleteQuest: _deleteQuest,
        onDeleteQuests: _deleteQuests,
        onUserEnergyChanged: _updateUserEnergy,
        onOpenSettings: _openSettings,
        onTabChange: _changeTab,
      ),
      RetryScreen(
        quests: _retryQuests,
        onQuestStart: _openRetryQuest,
        onSkipToday: _skipRetryToday,
      ),
      RankingScreen(data: _localData, leaderboard: _leaderboard),
      RecordScreen(
        data: _recordSummaryData,
        onUndoCompletedQuest: _undoCompletedQuest,
      ),
    ];

    final isAiQuestBusy = _isCreatingAiQuest || _isSavingAiQuest;
    final isPrimaryActionBlocked = isAiQuestBusy || _isDeletingQuests;

    return Scaffold(
      key: _scaffoldKey,
      extendBody: true,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(color: Color(0xFFF1F3F8)),
            child: SafeArea(child: screens[_currentIndex]),
          ),
          if (_showQuestCelebration)
            Positioned(
              left: 0,
              right: 0,
              bottom: 46,
              height: 220,
              child: QuestCompletionCelebration(
                key: ValueKey(_celebrationSeed),
                seed: _celebrationSeed,
                onComplete: _hideQuestCelebration,
              ),
            ),
          if (_isCreatingAiQuest) _buildAiQuestCreationOverlay(),
          if (_isSavingAiQuest) const _AiQuestSavingShimmerOverlay(),
          if (_isSavingCompletedQuest)
            const _QuestCompletionSavingShimmerOverlay(),
          if (_isDeletingQuests)
            _QuestDeletingShimmerOverlay(count: _deletingQuestCount),
          if (_questAutoAdvanceQuestId != null &&
              _questAutoAdvanceRemainingSeconds > 0)
            _QuestAutoAdvanceOverlay(
              remainingSeconds: _questAutoAdvanceRemainingSeconds,
              onCancel: _cancelQuestAutoAdvance,
            ),
        ],
      ),
      floatingActionButtonLocation: const _BottomNavCenterFabLocation(),
      floatingActionButton: ScaleTransition(
        scale: _fabPopScale,
        child: NeumorphicRoundedCard(
          padding: EdgeInsets.zero,
          color: const Color(0xFFD0CBFF),
          borderRadius: 18,
          child: SizedBox(
            width: 56,
            height: 42,
            child: FloatingActionButton(
              onPressed: isPrimaryActionBlocked ? null : _openAddQuest,
              backgroundColor: const Color(0xFFD0CBFF),
              foregroundColor: const Color(0xFF6358FF),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.add_rounded, size: 23),
            ),
          ),
        ),
      ),
      bottomNavigationBar: AbsorbPointer(
        absorbing: isPrimaryActionBlocked,
        child: AppBottomNavBar(currentIndex: _currentIndex, onTap: _changeTab),
      ),
    );
  }

  Widget _buildAiQuestCreationOverlay() {
    return const AiQuestCreationProgressOverlay();
  }

  void _changeTab(int index) {
    _cancelQuestAutoAdvance();
    setState(() => _currentIndex = index);
  }

  String get _homeUserName {
    if (_usesServerData && _localData.userName.trim().isNotEmpty) {
      return _localData.userName;
    }
    return widget.session.displayName;
  }

  AppLocalData get _homeData {
    return _localData.copyWith(
      completedQuests: const <CompletedQuestRecord>[],
      recentActivities: const <RecentActivity>[],
    );
  }

  AppLocalData get _recordSummaryData {
    return _localData;
  }

  Future<void> _openAddQuest() async {
    await _openAddQuestScreen();
  }

  Future<void> _openAddQuestForCategory(String category) async {
    await _openAddQuestScreen(initialCategory: category);
  }

  Future<void> _openAddQuestScreen({String? initialCategory}) async {
    _cancelQuestAutoAdvance();
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (context) => AddQuestScreen(
          initialCategory: initialCategory,
          returnAiSuggestionRequest: true,
        ),
      ),
    );

    if (result == null) {
      return;
    }

    final QuestItem? createdQuest;
    if (result case AddQuestScreenAiSuggestionRequest request) {
      createdQuest = await _createQuestFromAiSuggestion(request.draft);
    } else if (result case QuestItem quest) {
      createdQuest = await _createQuestFromDraft(quest);
    } else {
      return;
    }
    if (!mounted || createdQuest == null) {
      return;
    }

    _setLocalData(
      _localData.copyWith(quests: [createdQuest, ..._localData.quests]),
    );
  }

  Future<QuestItem?> _createQuestFromDraft(QuestItem draft) async {
    if (draft.subtasks.isNotEmpty) {
      return draft.copyWith(
        activeSubtaskId: draft.effectiveActiveSubtaskId,
        syncTarget: questSyncTargetLocal,
      );
    }

    return _createQuest(draft);
  }

  Future<QuestItem?> _createQuestFromAiSuggestion(QuestItem draft) async {
    final taskIntakeRepository = _taskIntakeRepository;
    if (taskIntakeRepository == null) {
      return _createQuest(draft);
    }

    if (mounted) {
      setState(() => _isCreatingAiQuest = true);
    }

    final TaskCandidateResponse? candidate;
    try {
      candidate = await _createTaskCandidate(
        draft,
        repository: taskIntakeRepository,
      );
    } finally {
      if (mounted) {
        setState(() => _isCreatingAiQuest = false);
      }
    }

    if (!mounted || candidate == null) {
      return null;
    }

    return _reviewAndCommitCandidate(
      candidate,
      draft: draft,
      repository: taskIntakeRepository,
    );
  }

  Future<QuestItem?> _handleQuestEditAiSuggestion({
    required QuestItem originalQuest,
    required QuestItem draft,
    ValueChanged<bool>? onCreationLoadingChanged,
  }) async {
    final taskIntakeRepository = _taskIntakeRepository;
    if (taskIntakeRepository == null) {
      _showStyledSnackBar('AI 제안을 사용할 수 없어요.');
      return null;
    }

    if (mounted) {
      setState(() => _isCreatingAiQuest = true);
    }
    onCreationLoadingChanged?.call(true);

    final TaskCandidateResponse? candidate;
    try {
      candidate = await _createTaskCandidate(
        draft,
        repository: taskIntakeRepository,
      );
    } finally {
      if (mounted) {
        setState(() => _isCreatingAiQuest = false);
      }
      onCreationLoadingChanged?.call(false);
    }

    if (!mounted || candidate == null) {
      return null;
    }

    final suggestedQuest = await _reviewAndCommitCandidate(
      candidate,
      draft: draft,
      repository: taskIntakeRepository,
    );
    if (!mounted || suggestedQuest == null) {
      return null;
    }

    final updatedQuest = suggestedQuest.copyWith(
      elapsedSeconds: originalQuest.elapsedSeconds,
    );
    _setLocalData(
      _replaceQuestById(_localData, originalQuest.id, updatedQuest),
    );
    unawaited(_deleteServerQuestAfterAiReplacement(originalQuest));
    return updatedQuest;
  }

  Future<void> _deleteServerQuestAfterAiReplacement(QuestItem quest) async {
    final questRepository = _questRepository;
    if (questRepository == null || !quest.syncsWithQuestApi) {
      return;
    }

    try {
      await questRepository.deleteQuest(quest.id);
    } catch (error) {
      _showQuestSyncError('기존 퀘스트를 서버에서 정리하지 못했어요.', error);
    }
  }

  Future<TaskCandidateResponse?> _createTaskCandidate(
    QuestItem draft, {
    required TaskIntakeRepository repository,
  }) async {
    try {
      final response = await repository.createIntake(
        TaskIntakeRequest(
          text: _taskIntakeTextFromDraft(draft),
          source: 'manual',
          clientTimezone: 'Asia/Seoul',
          userContext: _taskIntakeUserContextForDraft(draft),
          clientMetadata: _taskIntakeMetadataFromDraft(draft),
        ),
      );

      final candidate = response.candidate;
      if (candidate != null) {
        return candidate;
      }

      final candidateId = response.candidateId;
      if (candidateId != null) {
        return repository.getCandidate(candidateId);
      }

      throw const TaskIntakeRepositoryException(
        code: 'missing_task_candidate',
        message: 'Server response did not include a task candidate.',
      );
    } catch (error) {
      _showQuestSyncError('AI 제안을 만들지 못했어요.', error);
      return null;
    }
  }

  Map<String, dynamic> _taskIntakeMetadataFromDraft(QuestItem draft) {
    return {
      'entry_point': 'add_quest_screen',
      'category': normalizeQuestCategory(draft.category),
      'difficulty': draft.difficulty,
      'due_date': draft.dueDate?.toIso8601String(),
      'exp': draft.exp,
      'default_duration_seconds': draft.defaultDurationSeconds,
      if (draft.aiSubtaskPrompt != null)
        'subtask_generation_prompt': draft.aiSubtaskPrompt,
    };
  }

  TaskIntakeUserContext _taskIntakeUserContextForDraft(QuestItem draft) {
    final todayCompletedCount = _todayCompletedRecords().length;
    final totalTaskCount = _localData.quests.length + todayCompletedCount;
    final remainingSeconds = _localData.quests.fold<int>(0, (total, quest) {
      final remaining = quest.effectiveDurationSeconds - quest.elapsedSeconds;
      return total + (remaining > 0 ? remaining : 0);
    });

    return TaskIntakeUserContext(
      energyNow: _localData.userEnergy,
      availableMinutesToday: remainingSeconds <= 0
          ? null
          : (remainingSeconds / 60).ceil(),
      extra: {
        'home_total_task_count': totalTaskCount,
        'home_completed_today_count': todayCompletedCount,
        'home_pending_task_count': _localData.quests.length,
        'draft_default_duration_seconds': draft.defaultDurationSeconds,
      },
    );
  }

  List<CompletedQuestRecord> _todayCompletedRecords() {
    final now = DateTime.now();
    return _localData.completedQuests.where((record) {
      final completedAt = DateTime.tryParse(record.completedAt)?.toLocal();
      return completedAt != null &&
          completedAt.year == now.year &&
          completedAt.month == now.month &&
          completedAt.day == now.day;
    }).toList();
  }

  String _taskIntakeTextFromDraft(QuestItem draft) {
    return draft.title;
  }

  Future<QuestItem?> _reviewAndCommitCandidate(
    TaskCandidateResponse initialCandidate, {
    required QuestItem draft,
    required TaskIntakeRepository repository,
  }) async {
    var candidate = initialCandidate;

    while (true) {
      if (!mounted) {
        return null;
      }

      final navigator = Navigator.of(context);
      final result = await navigator.push<TaskCandidateReviewResult>(
        MaterialPageRoute<TaskCandidateReviewResult>(
          builder: (_) => TaskCandidateReviewScreen(candidate: candidate),
        ),
      );

      if (!mounted || result == null) {
        return null;
      }

      switch (result.action) {
        case TaskCandidateReviewAction.saveAsIs:
          return _confirmCandidate(
            candidate,
            result: result,
            draft: draft,
            repository: repository,
          );
        case TaskCandidateReviewAction.saveTodayOnly:
          return _confirmCandidate(
            candidate,
            result: result,
            draft: draft,
            repository: repository,
            todayOnly: true,
          );
        case TaskCandidateReviewAction.makeSmaller:
          final revised = await _reviseCandidate(
            result,
            repository: repository,
            revisionType: 'make_smaller',
          );
          if (revised == null) {
            return null;
          }
          candidate = revised;
          continue;
        case TaskCandidateReviewAction.reduceReminders:
          final revised = await _reviseCandidate(
            result,
            repository: repository,
            revisionType: 'adjust_reminders',
          );
          if (revised == null) {
            return null;
          }
          candidate = revised;
          continue;
        case TaskCandidateReviewAction.cancel:
          await _rejectCandidate(result, repository: repository);
          return null;
      }
    }
  }

  Future<QuestItem?> _confirmCandidate(
    TaskCandidateResponse candidate, {
    required TaskCandidateReviewResult result,
    required QuestItem draft,
    required TaskIntakeRepository repository,
    bool todayOnly = false,
  }) async {
    try {
      if (mounted) {
        setState(() => _isSavingAiQuest = true);
      }

      final commitResult = await repository.confirmCandidate(
        result.candidateId,
        TaskConfirmRequest(
          editedFields: result.editedFields,
          selectedSubtaskIds: todayOnly
              ? _todayOnlySubtaskIds(candidate, result.selectedSubtaskIds)
              : result.selectedSubtaskIds,
          selectedReminderIds: result.selectedReminderIds,
        ),
      );
      return questItemFromTaskResponse(commitResult.task, fallbackDraft: draft);
    } catch (error) {
      _showQuestSyncError('AI 제안을 저장하지 못했어요.', error);
      return null;
    } finally {
      if (mounted) {
        setState(() => _isSavingAiQuest = false);
      }
    }
  }

  Future<TaskCandidateResponse?> _reviseCandidate(
    TaskCandidateReviewResult result, {
    required TaskIntakeRepository repository,
    required String revisionType,
  }) async {
    try {
      return repository.reviseCandidate(
        result.candidateId,
        TaskCandidateReviseRequest(
          revisionType: revisionType,
          editedFields: result.editedFields,
        ),
      );
    } catch (error) {
      _showQuestSyncError('AI 제안을 다시 만들지 못했어요.', error);
      return null;
    }
  }

  Future<void> _rejectCandidate(
    TaskCandidateReviewResult result, {
    required TaskIntakeRepository repository,
  }) async {
    try {
      await repository.rejectCandidate(
        result.candidateId,
        const TaskCandidateRejectRequest(reason: 'cancelled_from_review'),
      );
    } catch (error) {
      _showQuestSyncError('AI 제안을 취소하지 못했어요.', error);
    }
  }

  List<String> _todayOnlySubtaskIds(
    TaskCandidateResponse candidate,
    List<String> selectedSubtaskIds,
  ) {
    final selectedIds = selectedSubtaskIds.toSet();
    final selectedSubtasks = candidate.subtasks
        .where((subtask) => selectedIds.contains(subtask.id))
        .toList();

    for (final subtask in selectedSubtasks) {
      if (subtask.isNextAction) {
        return [subtask.id];
      }
    }

    if (selectedSubtasks.isNotEmpty) {
      return [selectedSubtasks.first.id];
    }
    return <String>[];
  }

  Future<void> _openQuestTimer(
    QuestItem quest, {
    bool autoStartOnOpen = false,
  }) async {
    _cancelQuestAutoAdvance();
    _isOpeningQuestTimer = true;
    _isQuestTimerRouteOpen = true;
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => QuestTimerScreen(
          quest: quest,
          notificationsEnabled: _notificationsEnabled,
          autoStartOnOpen: autoStartOnOpen,
          onQuestChanged: (updatedQuest) =>
              _updateQuest(updatedQuest, syncServer: false),
          onAiSuggestionRequested: _handleQuestEditAiSuggestion,
        ),
      ),
    );
    _isOpeningQuestTimer = false;
    _isQuestTimerRouteOpen = false;

    if (result == null) {
      return;
    }

    await _handleQuestTimerResult(result);
  }

  Future<void> _handleQuestTimerResult(Object? result) async {
    if (result == null) {
      return;
    }

    if (result case QuestTimerDeleteResult deleteResult) {
      await _deleteQuestAsync(deleteResult.quest);
      return;
    }

    if (result case CompletedQuestRecord completedRecord) {
      final originalQuest = _findQuest(completedRecord.questId);
      final completionAction = await _showCompletionActionDialog(
        completedRecord,
        originalQuest: originalQuest,
      );
      if (!mounted || completionAction == null) {
        _updateQuest(_copyQuestWithElapsed(completedRecord), syncServer: false);
        return;
      }
      if (completionAction == _CompletionAfterAction.undo) {
        _updateQuest(_copyQuestWithElapsed(completedRecord), syncServer: false);
        _showStyledSnackBar('완료를 취소하고 진행 상태로 돌렸어요.', centerText: true);
        return;
      }

      final continuationQuest = _continuationQuestFromRemaining(
        originalQuest: originalQuest,
        completedRecord: completedRecord,
        postponeUntilTomorrow:
            completionAction == _CompletionAfterAction.postponeRemaining,
      );
      final nextQuest = continuationQuest ?? _nextQuestAfter(completedRecord.questId);
      final savedRecord = await _completeQuest(completedRecord);
      if (!mounted || savedRecord == null) {
        return;
      }

      var nextData = _store.completeQuest(_localData, savedRecord);
      if (continuationQuest != null) {
        nextData = nextData.copyWith(quests: [continuationQuest, ...nextData.quests]);
      }
      _setLocalData(nextData);
      unawaited(_refreshServerProgressData());
      _triggerQuestCelebration();
      _scheduleQuestAutoAdvance(nextQuest?.id);
      return;
    }

    if (result case QuestTimerScreenResult timerResult) {
      _updateQuest(timerResult.quest);
      if (timerResult.didPauseTimer) {
        _showStyledSnackBar('타이머 일시중지됨', centerText: true, compact: true);
      }
      return;
    }

    if (result case QuestItem updatedQuest) {
      _updateQuest(updatedQuest);
    }
  }

  Future<_CompletionAfterAction?> _showCompletionActionDialog(
    CompletedQuestRecord record, {
    required QuestItem? originalQuest,
  }) {
    final remainingCount = _remainingSubtasks(originalQuest, record).length;
    return showDialog<_CompletionAfterAction>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFF1F3F8),
        title: const Text('퀘스트 완료'),
        content: Text(
          remainingCount == 0
              ? '완료로 저장할까요?'
              : '아직 남은 subtask $remainingCount개가 있어요. 완료 저장 후 남은 단계만 새 퀘스트로 이어갈 수 있어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_CompletionAfterAction.undo),
            child: const Text('완료 취소하기'),
          ),
          if (remainingCount > 0)
            TextButton(
              onPressed: () => Navigator.of(context).pop(
                _CompletionAfterAction.continueRemaining,
              ),
              child: const Text('쉬고 이어서 하기'),
            ),
          if (remainingCount > 0)
            TextButton(
              onPressed: () => Navigator.of(context).pop(
                _CompletionAfterAction.postponeRemaining,
              ),
              child: const Text('내일로 미루기'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_CompletionAfterAction.saveOnly),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6F63FF),
              foregroundColor: Colors.white,
            ),
            child: const Text('완료 저장'),
          ),
        ],
      ),
    );
  }

  QuestItem? _continuationQuestFromRemaining({
    required QuestItem? originalQuest,
    required CompletedQuestRecord completedRecord,
    required bool postponeUntilTomorrow,
  }) {
    final remaining = _remainingSubtasks(originalQuest, completedRecord);
    if (remaining.isEmpty) {
      return null;
    }

    final now = DateTime.now();
    final normalizedSubtasks = [
      for (var index = 0; index < remaining.length; index += 1)
        remaining[index].copyWith(
          id: 'continued-${now.microsecondsSinceEpoch}-$index',
          orderIndex: index,
          status: 'todo',
          isNextAction: index == 0,
          completedAt: null,
          elapsedSeconds: 0,
        ),
    ];
    final durationSeconds = normalizedSubtasks.fold<int>(
      0,
      (total, subtask) => total + subtask.plannedDurationSeconds,
    );

    return QuestItem(
      id: 'continued-${now.microsecondsSinceEpoch}',
      title: originalQuest?.title ?? completedRecord.title,
      exp: originalQuest?.exp ?? completedRecord.earnedExp,
      difficulty: originalQuest?.difficulty ?? completedRecord.difficulty,
      category: originalQuest?.category ?? completedRecord.category,
      elapsedSeconds: 0,
      defaultDurationSeconds: durationSeconds,
      dueDate: postponeUntilTomorrow
          ? normalizeQuestDueDate(now.add(const Duration(days: 1)))
          : originalQuest?.dueDate,
      subtasks: normalizedSubtasks,
      activeSubtaskId: normalizedSubtasks.first.id,
      syncTarget: questSyncTargetLocal,
    );
  }

  List<QuestSubtask> _remainingSubtasks(
    QuestItem? originalQuest,
    CompletedQuestRecord record,
  ) {
    final sourceSubtasks = originalQuest?.subtasks.isNotEmpty == true
        ? originalQuest!.subtasks
        : record.subtasks;
    return sourceSubtasks.where((subtask) => !subtask.isDone).toList();
  }

  Future<void> _openSettings() async {
    _cancelQuestAutoAdvance();
    final result = await Navigator.of(context).push<SettingsScreenResult>(
      MaterialPageRoute<SettingsScreenResult>(
        builder: (_) => SettingsScreen(
          userName: widget.session.displayName,
          userEmail: widget.session.email,
        ),
      ),
    );

    if (result?.shouldChangeAccount == true) {
      await widget.onChangeAccount();
      return;
    }

    await _reloadSettingsAfterSettingsScreen();
    await _reloadLocalDataAfterSettingsScreen(
      skipServerRefresh: result?.didSyncNotion == true,
    );
  }

  void _deleteQuest(QuestItem quest) {
    unawaited(_deleteQuestAsync(quest));
  }

  Future<void> _deleteQuestAsync(QuestItem quest) async {
    await _stopQuestTimerIfActive(quest.id);

    final questRepository = _questRepository;
    final taskIntakeRepository = _taskIntakeRepository;
    if (quest.isTaskBacked && taskIntakeRepository != null) {
      try {
        await taskIntakeRepository.deleteTask(quest.id);
      } catch (error) {
        _showQuestSyncError('Task를 삭제하지 못했어요.', error);
        return;
      }
    }

    if (questRepository != null && quest.syncsWithQuestApi) {
      try {
        await questRepository.deleteQuest(quest.id);
      } catch (error) {
        _showQuestSyncError('퀘스트를 삭제하지 못했어요.', error);
        return;
      }
    }

    if (!mounted) {
      return;
    }

    _setLocalData(
      _localData.copyWith(
        quests: _localData.quests.where((item) => item.id != quest.id).toList(),
      ),
    );
  }

  void _deleteQuests(List<QuestItem> quests) {
    unawaited(_deleteQuestsAsync(quests));
  }

  Future<void> _deleteQuestsAsync(List<QuestItem> quests) async {
    if (quests.isEmpty || _isDeletingQuests || !mounted) {
      return;
    }

    setState(() {
      _isDeletingQuests = true;
      _deletingQuestCount = quests.length;
    });

    final questIdsToRemove = <String>{};

    try {
      for (final quest in quests) {
        await _stopQuestTimerIfActive(quest.id);

        final taskIntakeRepository = _taskIntakeRepository;
        if (quest.isTaskBacked && taskIntakeRepository != null) {
          try {
            await taskIntakeRepository.deleteTask(quest.id);
          } catch (error) {
            _showQuestSyncError('일부 Task를 삭제하지 못했어요.', error);
            continue;
          }
        }

        final questRepository = _questRepository;
        if (questRepository != null && quest.syncsWithQuestApi) {
          try {
            await questRepository.deleteQuest(quest.id);
          } catch (error) {
            _showQuestSyncError('일부 퀘스트를 삭제하지 못했어요.', error);
            continue;
          }
        }
        questIdsToRemove.add(quest.id);
      }

      if (!mounted || questIdsToRemove.isEmpty) {
        return;
      }

      _setLocalData(
        _localData.copyWith(
          quests: _localData.quests
              .where((quest) => !questIdsToRemove.contains(quest.id))
              .toList(),
        ),
      );
      _showStyledSnackBar(
        '${questIdsToRemove.length}개 퀘스트를 삭제했어요.',
        centerText: true,
        compact: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDeletingQuests = false;
          _deletingQuestCount = 0;
        });
      }
    }
  }

  void _updateUserEnergy(String energy) {
    _setLocalData(_localData.copyWith(userEnergy: energy));
  }

  void _updateQuest(
    QuestItem updatedQuest, {
    bool syncServer = true,
    bool persist = true,
  }) {
    _setLocalData(_replaceQuest(_localData, updatedQuest), persist: persist);

    if (syncServer) {
      unawaited(_syncQuestUpdate(updatedQuest));
    }
  }

  void _openRetryQuest(QuestItem quest) {
    unawaited(_openQuestTimer(quest, autoStartOnOpen: true));
  }

  void _skipRetryToday() {
    final skippedQuestIds = _retryQuests.map((quest) => quest.id).toSet();
    if (skippedQuestIds.isEmpty) {
      return;
    }

    setState(() => _skippedRetryQuestIds.addAll(skippedQuestIds));
    _showStyledSnackBar(
      '오늘은 리도전 퀘스트를 건너뛰었어요.',
      centerText: true,
      compact: true,
    );
  }

  Future<void> _loadLocalData() async {
    final data = await _buildLoadedLocalData();
    final activeSnapshot = await _questTimerService.currentState();

    if (!mounted) {
      return;
    }

    setState(() {
      _localData = data;
      _isLoading = false;
    });

    if (_notificationsEnabled && activeSnapshot?.isRunning == true) {
      unawaited(
        _openActiveQuestTimerIfNeeded(questId: activeSnapshot!.questId),
      );
      return;
    }

    _scheduleLaunchQuestTimerBottomSheet();
  }

  void _setLocalData(AppLocalData data, {bool persist = true}) {
    setState(() => _localData = data);
    if (persist) {
      unawaited(_store.save(data));
    }
  }

  void _scheduleLaunchQuestTimerBottomSheet() {
    if (_didShowLaunchQuestTimerSheet || _localData.quests.isEmpty) {
      return;
    }

    _didShowLaunchQuestTimerSheet = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _currentIndex != 0 || _localData.quests.isEmpty) {
        return;
      }

      unawaited(_openQuestTimerBottomSheet(_localData.quests.first));
    });
  }

  Future<void> _openQuestTimerBottomSheet(QuestItem quest) async {
    _cancelQuestAutoAdvance();
    if (!mounted ||
        _isOpeningQuestTimer ||
        _isQuestTimerRouteOpen ||
        _isQuestTimerBottomSheetOpen) {
      return;
    }

    final scaffoldState = _scaffoldKey.currentState;
    if (scaffoldState == null) {
      return;
    }

    _isQuestTimerBottomSheetOpen = true;
    QuestItem? fullTimerQuest;
    CompletedQuestRecord? completedRecord;

    late final PersistentBottomSheetController controller;
    controller = scaffoldState.showBottomSheet(
      (context) => SizedBox(
        width: double.infinity,
        height: MediaQuery.sizeOf(context).height * 0.34,
        child: QuestTimerBottomSheet(
          quest: quest,
          notificationsEnabled: _notificationsEnabled,
          onQuestChanged: (updatedQuest) =>
              _updateQuest(updatedQuest, syncServer: false, persist: false),
          onOpenFullTimer: (updatedQuest) {
            fullTimerQuest = updatedQuest;
            controller.close();
          },
          onQuestCompleted: (record) {
            completedRecord = record;
            controller.close();
          },
          onClose: () => controller.close(),
        ),
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      enableDrag: false,
      sheetAnimationStyle: const AnimationStyle(
        curve: Curves.easeOutCubic,
        duration: Duration(milliseconds: 360),
        reverseCurve: Curves.easeInCubic,
        reverseDuration: Duration(milliseconds: 260),
      ),
    );
    _questTimerBottomSheetController = controller;

    await controller.closed;

    if (!mounted) {
      return;
    }

    _isQuestTimerBottomSheetOpen = false;
    if (identical(_questTimerBottomSheetController, controller)) {
      _questTimerBottomSheetController = null;
    }

    final completedQuestRecord = completedRecord;
    if (completedQuestRecord != null) {
      await _handleQuestTimerResult(completedQuestRecord);
      return;
    }

    final questForFullTimer = fullTimerQuest;
    if (questForFullTimer != null) {
      await _openQuestTimer(questForFullTimer);
      return;
    }

    var questToPersist = _findQuest(quest.id) ?? quest;
    if (_notificationsEnabled) {
      final snapshot = await _questTimerService.currentState();
      if (snapshot?.questId == quest.id && snapshot?.isRunning == true) {
        final elapsedSeconds =
            snapshot!.elapsedSeconds > questToPersist.elapsedSeconds
            ? snapshot.elapsedSeconds
            : questToPersist.elapsedSeconds;
        await _questTimerService.pauseTimer(
          questId: snapshot.questId,
          questTitle: snapshot.questTitle,
          elapsedSeconds: elapsedSeconds,
          defaultDurationSeconds: snapshot.defaultDurationSeconds,
        );
        questToPersist = questToPersist.copyWith(
          elapsedSeconds: elapsedSeconds,
        );
      }
    }

    if (questToPersist.elapsedSeconds != quest.elapsedSeconds) {
      _updateQuest(questToPersist);
    }
  }

  void _showStyledSnackBar(
    String message, {
    bool centerText = false,
    bool compact = false,
  }) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final textStyle =
        theme.snackBarTheme.contentTextStyle ??
        theme.textTheme.bodyMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ) ??
        const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        );

    final compactWidth = compact
        ? (() {
            final textPainter = TextPainter(
              text: TextSpan(text: message, style: textStyle),
              maxLines: 1,
              textDirection: Directionality.of(context),
            )..layout(maxWidth: mediaQuery.size.width - 72);
            return (textPainter.width + 32).clamp(
              120.0,
              mediaQuery.size.width - 40,
            );
          })()
        : null;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            textAlign: centerText ? TextAlign.center : null,
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFFF8B93),
          margin: compact ? null : const EdgeInsets.fromLTRB(20, 0, 20, 20),
          width: compact ? compactWidth : null,
          padding: compact
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 14)
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          duration: const Duration(seconds: 2),
        ),
        snackBarAnimationStyle: const AnimationStyle(
          curve: Curves.easeOutCubic,
          duration: Duration(milliseconds: 420),
          reverseCurve: Curves.easeInCubic,
          reverseDuration: Duration(milliseconds: 320),
        ),
      );
  }

  QuestItem? _nextQuestAfter(String questId) {
    final currentIndex = _localData.quests.indexWhere(
      (quest) => quest.id == questId,
    );
    if (currentIndex == -1) {
      return null;
    }

    final nextIndex = currentIndex + 1;
    if (nextIndex >= _localData.quests.length) {
      return null;
    }

    return _localData.quests[nextIndex];
  }

  void _scheduleQuestAutoAdvance(String? questId) {
    _cancelQuestAutoAdvance();
    if (questId == null) {
      return;
    }

    _showStyledSnackBar('15초 휴식 후 다음 퀘스트로 이동할게요.', centerText: true);
    setState(() {
      _questAutoAdvanceQuestId = questId;
      _questAutoAdvanceRemainingSeconds =
          _questAutoAdvanceRestDuration.inSeconds;
    });
    _questAutoAdvanceTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_questAutoAdvanceRemainingSeconds <= 1) {
        timer.cancel();
        final nextQuest = _findQuest(questId);
        setState(() {
          _questAutoAdvanceTimer = null;
          _questAutoAdvanceQuestId = null;
          _questAutoAdvanceRemainingSeconds = 0;
        });
        if (nextQuest == null) {
          return;
        }

        unawaited(_openQuestTimer(nextQuest, autoStartOnOpen: true));
        return;
      }

      setState(() {
        _questAutoAdvanceRemainingSeconds -= 1;
      });
    });
  }

  void _cancelQuestAutoAdvance() {
    _questAutoAdvanceTimer?.cancel();
    _questAutoAdvanceTimer = null;
    if (!mounted) {
      _questAutoAdvanceQuestId = null;
      _questAutoAdvanceRemainingSeconds = 0;
      return;
    }

    if (_questAutoAdvanceQuestId == null &&
        _questAutoAdvanceRemainingSeconds == 0) {
      return;
    }

    setState(() {
      _questAutoAdvanceQuestId = null;
      _questAutoAdvanceRemainingSeconds = 0;
    });
  }

  void _listenToQuestTimerTicks() {
    _questTimerTickSubscription = _questTimerService.timerTicks.listen((tick) {
      if (!mounted) {
        return;
      }

      setState(() {
        _localData = _copyWithQuestElapsed(
          _localData,
          questId: tick.questId,
          elapsedSeconds: tick.elapsedSeconds,
        );
      });
    });
  }

  AppLocalData _copyWithQuestElapsed(
    AppLocalData data, {
    required String questId,
    required int elapsedSeconds,
  }) {
    final nextQuests = data.quests
        .map(
          (item) => item.id == questId
              ? item.copyWith(
                  elapsedSeconds: elapsedSeconds > item.elapsedSeconds
                      ? elapsedSeconds
                      : item.elapsedSeconds,
                )
              : item,
        )
        .toList();
    return data.copyWith(quests: nextQuests);
  }

  Future<void> _stopQuestTimerIfActive(String questId) async {
    final snapshot = await _questTimerService.currentState();
    if (snapshot?.questId == questId && snapshot?.isRunning == true) {
      await _questTimerService.stopTimer();
    }
  }

  Future<void> _handleAppResumed() async {
    if (!_notificationsEnabled) {
      return;
    }

    final activeSnapshot = await _questTimerService.currentState();
    if (activeSnapshot?.isRunning != true) {
      return;
    }

    await _openActiveQuestTimerIfNeeded(questId: activeSnapshot!.questId);
  }

  Future<void> _openActiveQuestTimerIfNeeded({required String questId}) async {
    if (!mounted ||
        _isLoading ||
        _isOpeningQuestTimer ||
        _isQuestTimerRouteOpen) {
      return;
    }

    final quest = _findQuest(questId);
    if (quest == null) {
      return;
    }

    await _openQuestTimer(quest);
  }

  Future<void> _requestNotificationPermissionOnLaunch() async {
    if (!_notificationsEnabled) {
      return;
    }

    final status = await Permission.notification.status;
    if (status.isGranted || status.isPermanentlyDenied) {
      return;
    }

    await Permission.notification.request();
  }

  Future<void> _initializeAppState() async {
    await _loadNotificationSetting();
    await _requestNotificationPermissionOnLaunch();
    await _loadLocalData();
  }

  Future<void> _loadNotificationSetting() async {
    final settings = await _settingsStore.load();
    if (!mounted) {
      return;
    }

    setState(() => _notificationsEnabled = settings.notificationsEnabled);
  }

  Future<void> _reloadSettingsAfterSettingsScreen() async {
    final previousValue = _notificationsEnabled;
    final settings = await _settingsStore.load();
    if (!mounted) {
      return;
    }

    setState(() => _notificationsEnabled = settings.notificationsEnabled);

    if (previousValue && !settings.notificationsEnabled) {
      final activeSnapshot = await _questTimerService.currentState();
      if (activeSnapshot?.isRunning == true) {
        await _questTimerService.pauseTimer(
          questId: activeSnapshot!.questId,
          questTitle: activeSnapshot.questTitle,
          elapsedSeconds: activeSnapshot.elapsedSeconds,
          defaultDurationSeconds: activeSnapshot.defaultDurationSeconds,
        );
      }
    }
  }

  Future<void> _reloadLocalDataAfterSettingsScreen({
    bool skipServerRefresh = false,
  }) async {
    final data = await _buildLoadedLocalData(
      skipServerRefresh: skipServerRefresh,
    );
    if (!mounted) {
      return;
    }
    setState(() => _localData = data);
  }

  Future<AppLocalData> _buildLoadedLocalData({
    bool skipServerRefresh = false,
  }) async {
    var data = await _store.load();
    if (!skipServerRefresh) {
      data = await _loadServerInitialData(data);
    }

    final activeSnapshot = await _questTimerService.currentState();
    if (activeSnapshot != null) {
      data = _copyWithQuestElapsed(
        data,
        questId: activeSnapshot.questId,
        elapsedSeconds: activeSnapshot.elapsedSeconds,
      );
    }
    return data;
  }

  Future<AppLocalData> _loadServerInitialData(AppLocalData fallbackData) async {
    final profileRepository = _profileRepository;
    final questRepository = _questRepository;
    final statsRepository = _statsRepository;
    final dungeonRepository = _dungeonRepository;
    final leaderboardRepository = _leaderboardRepository;
    final taskIntakeRepository = _taskIntakeRepository;
    if (profileRepository == null ||
        questRepository == null ||
        statsRepository == null ||
        dungeonRepository == null) {
      return fallbackData;
    }

    try {
      final profileFuture = profileRepository.getProfile();
      final questsFuture = questRepository.listQuests();
      final tasksFuture = taskIntakeRepository == null
          ? Future.value(<TaskResponse>[])
          : _loadTaskListForInitialData(taskIntakeRepository);
      final statsFuture = statsRepository.getSummary();
      final dungeonsFuture = dungeonRepository.listDungeons();
      final leaderboardFuture = leaderboardRepository == null
          ? Future.value(null)
          : _loadLeaderboardForInitialData(leaderboardRepository);

      await Future.wait<Object?>([
        profileFuture,
        questsFuture,
        tasksFuture,
        statsFuture,
        dungeonsFuture,
        leaderboardFuture,
      ]);

      final dungeonList = await dungeonsFuture;
      final leaderboard = await leaderboardFuture;
      final data = _copyWithServerInitialData(
        fallbackData,
        profile: await profileFuture,
        quests: await questsFuture,
        tasks: await tasksFuture,
        stats: await statsFuture,
        dungeonList: dungeonList,
      );
      if (leaderboard != null) {
        _leaderboard = leaderboard;
      }
      await _store.save(data);
      return data;
    } catch (error) {
      if (!_isLoading) {
        _scheduleQuestSyncError('서버 초기 데이터를 불러오지 못해 저장된 데이터를 표시합니다.', error);
      }
      return fallbackData;
    }
  }

  Future<LeaderboardResponse?> _loadLeaderboardForInitialData(
    LeaderboardRepository repository,
  ) async {
    try {
      return await repository.getLeaderboard();
    } catch (error) {
      _logQuestSyncError(
        '서버 leaderboard를 불러오지 못해 랭킹 정보만 건너뜁니다.',
        error,
      );
      return null;
    }
  }

  Future<List<TaskResponse>> _loadTaskListForInitialData(
    TaskIntakeRepository repository,
  ) async {
    try {
      final tasks = await repository.listTasks();
      return tasks.where((task) => !task.isCompleted).toList();
    } catch (error) {
      _logQuestSyncError('서버 task 목록을 불러오지 못해 기존 퀘스트 목록만 표시합니다.', error);
      return const <TaskResponse>[];
    }
  }

  Future<void> _refreshServerProgressData() async {
    final profileRepository = _profileRepository;
    final statsRepository = _statsRepository;
    final dungeonRepository = _dungeonRepository;
    final leaderboardRepository = _leaderboardRepository;
    if (profileRepository == null ||
        statsRepository == null ||
        dungeonRepository == null) {
      return;
    }

    try {
      final profileFuture = profileRepository.getProfile();
      final statsFuture = statsRepository.getSummary();
      final dungeonsFuture = dungeonRepository.listDungeons();
      final leaderboardFuture = leaderboardRepository == null
          ? Future.value(null)
          : _loadLeaderboardForInitialData(leaderboardRepository);

      await Future.wait<Object?>([
        profileFuture,
        statsFuture,
        dungeonsFuture,
        leaderboardFuture,
      ]);

      if (!mounted) {
        return;
      }

      final dungeonList = await dungeonsFuture;
      final leaderboard = await leaderboardFuture;
      final nextData = _applyServerProgressData(
        _localData,
        profile: await profileFuture,
        stats: await statsFuture,
        dungeonList: dungeonList,
      );

      setState(() {
        _localData = nextData;
        if (leaderboard != null) {
          _leaderboard = leaderboard;
        }
      });
      unawaited(_store.save(nextData));
    } catch (_) {
      // Keep the locally updated state when the refresh fails.
    }
  }

  AppLocalData _copyWithServerInitialData(
    AppLocalData data, {
    required ProfileResponse profile,
    required List<QuestItemResponse> quests,
    required List<TaskResponse> tasks,
    required StatsSummaryResponse stats,
    required DungeonListResponse dungeonList,
  }) {
    final localQuestsById = {for (final quest in data.quests) quest.id: quest};
    final completedQuestIds = data.completedQuests
        .map((record) => record.questId.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final serverQuestItems = quests.map(QuestItem.fromApiResponse).toList();
    final serverTaskItems = tasks
        .map(
          (task) => questItemFromTaskResponse(
            task,
            fallbackDraft:
                localQuestsById[task.id] ?? _fallbackQuestForTask(task),
          ),
        )
        .toList();

    return _applyServerProgressData(
      data,
      profile: profile,
      stats: stats,
      dungeonList: dungeonList,
    ).copyWith(
      quests: _mergeServerQuestsWithLocalOnlyItems(
        serverQuests: [...serverQuestItems, ...serverTaskItems],
        localQuests: data.quests,
        completedQuestIds: completedQuestIds,
      ),
    );
  }

  AppLocalData _applyServerProgressData(
    AppLocalData data, {
    required ProfileResponse profile,
    required StatsSummaryResponse stats,
    required DungeonListResponse dungeonList,
  }) {
    return data.copyWith(
      userName: profile.userName,
      userRole: profile.userRole,
      level: profile.level,
      currentExp: profile.currentExp,
      maxExp: profile.maxExp,
      credits: profile.credits,
      completedQuestCount: profile.completedQuestCount,
      earnedExp: profile.earnedExp,
      dailyRewardCount: stats.dailyRewardCount,
      dailyRewardTarget: stats.dailyRewardTarget,
      weeklyRewardCount: stats.weeklyRewardCount,
      weeklyRewardTarget: stats.weeklyRewardTarget,
      monthlyRewardCount: stats.monthlyRewardCount,
      monthlyRewardTarget: stats.monthlyRewardTarget,
      weeklyCompletedCount: stats.weeklyCompletedCount,
      weeklyCompletionRate: stats.weeklyCompletionRate,
      weeklyRateDelta: stats.weeklyRateDelta,
      diligenceStat: stats.diligenceStat,
      orderStat: stats.orderStat,
      intelligenceStat: stats.intelligenceStat,
      healthStat: stats.healthStat,
      clearedDungeonIds: dungeonList.dungeons
          .where((dungeon) => dungeon.cleared)
          .map((dungeon) => dungeon.dungeonId)
          .toList(),
    );
  }

  List<QuestItem> get _retryQuests {
    return _localData.quests.where((quest) {
      if (_skippedRetryQuestIds.contains(quest.id)) {
        return false;
      }
      if (quest.elapsedSeconds <= 0) {
        return false;
      }
      final duration = quest.effectiveDurationSeconds;
      if (duration <= 0) {
        return false;
      }
      return quest.elapsedSeconds < duration;
    }).toList();
  }

  List<QuestItem> _mergeServerQuestsWithLocalOnlyItems({
    required List<QuestItem> serverQuests,
    required List<QuestItem> localQuests,
    required Set<String> completedQuestIds,
  }) {
    final localQuestsById = {for (final quest in localQuests) quest.id: quest};
    final serverIds = <String>{};
    final mergedServerQuests = <QuestItem>[];

    for (final serverQuest in serverQuests) {
      if (completedQuestIds.contains(serverQuest.id.trim())) {
        continue;
      }
      if (!serverIds.add(serverQuest.id)) {
        continue;
      }
      mergedServerQuests.add(
        _mergeServerQuestWithLocalState(
          serverQuest,
          localQuestsById[serverQuest.id],
        ),
      );
    }

    final localOnlyQuests = localQuests
        .where(
          (quest) =>
              !quest.syncsWithQuestApi &&
              !quest.isTaskBacked &&
              !serverIds.contains(quest.id) &&
              !completedQuestIds.contains(quest.id.trim()),
        )
        .toList();
    return [...mergedServerQuests, ...localOnlyQuests];
  }

  QuestItem _mergeServerQuestWithLocalState(
    QuestItem serverQuest,
    QuestItem? localQuest,
  ) {
    if (localQuest == null) {
      return serverQuest;
    }

    final mergedSubtasks = _mergeServerSubtasksWithLocalState(
      serverQuest.subtasks,
      localQuest.subtasks,
    );

    return serverQuest.copyWith(
      elapsedSeconds: localQuest.elapsedSeconds > serverQuest.elapsedSeconds
          ? localQuest.elapsedSeconds
          : serverQuest.elapsedSeconds,
      subtasks: mergedSubtasks,
      activeSubtaskId: _mergedActiveSubtaskId(
        serverQuest: serverQuest,
        localQuest: localQuest,
        mergedSubtasks: mergedSubtasks,
      ),
      aiSubtaskPrompt: localQuest.aiSubtaskPrompt,
    );
  }

  List<QuestSubtask> _mergeServerSubtasksWithLocalState(
    List<QuestSubtask> serverSubtasks,
    List<QuestSubtask> localSubtasks,
  ) {
    if (serverSubtasks.isEmpty) {
      return localSubtasks;
    }

    final localSubtasksById = {
      for (final subtask in localSubtasks) subtask.id: subtask,
    };

    return serverSubtasks.map((serverSubtask) {
      final localSubtask = localSubtasksById[serverSubtask.id];
      if (localSubtask == null) {
        return serverSubtask;
      }
      return _mergeServerSubtaskWithLocalState(serverSubtask, localSubtask);
    }).toList();
  }

  QuestSubtask _mergeServerSubtaskWithLocalState(
    QuestSubtask serverSubtask,
    QuestSubtask localSubtask,
  ) {
    final elapsedSeconds =
        localSubtask.elapsedSeconds > serverSubtask.elapsedSeconds
        ? localSubtask.elapsedSeconds
        : serverSubtask.elapsedSeconds;
    final useLocalStatus =
        !serverSubtask.isDone &&
        (localSubtask.isDone ||
            localSubtask.elapsedSeconds > serverSubtask.elapsedSeconds);

    return serverSubtask.copyWith(
      status: useLocalStatus ? localSubtask.status : serverSubtask.status,
      completedAt: serverSubtask.completedAt ?? localSubtask.completedAt,
      elapsedSeconds: elapsedSeconds,
    );
  }

  String? _mergedActiveSubtaskId({
    required QuestItem serverQuest,
    required QuestItem localQuest,
    required List<QuestSubtask> mergedSubtasks,
  }) {
    for (final candidate in [
      localQuest.activeSubtaskId,
      serverQuest.activeSubtaskId,
    ]) {
      if (_isValidActiveSubtaskId(mergedSubtasks, candidate)) {
        return candidate;
      }
    }

    for (final subtask in mergedSubtasks) {
      if (!subtask.isDone) {
        return subtask.id;
      }
    }
    return null;
  }

  bool _isValidActiveSubtaskId(
    List<QuestSubtask> subtasks,
    String? activeSubtaskId,
  ) {
    if (activeSubtaskId == null) {
      return false;
    }
    for (final subtask in subtasks) {
      if (subtask.id == activeSubtaskId && !subtask.isDone) {
        return true;
      }
    }
    return false;
  }

  QuestItem _fallbackQuestForTask(TaskResponse task) {
    return QuestItem(
      id: task.id,
      title: task.title,
      exp: 0,
      difficulty: '보통',
      category: 'work',
      elapsedSeconds: task.elapsedSeconds ?? 0,
      defaultDurationSeconds: task.estimatedMinutes == null
          ? 0
          : task.estimatedMinutes! * 60,
      dueDate: task.dueAt,
      syncTarget: questSyncTargetTask,
    );
  }

  Future<QuestItem?> _createQuest(QuestItem quest) async {
    final questRepository = _questRepository;
    if (questRepository == null) {
      return quest;
    }

    try {
      final createdQuest = await questRepository.createQuest(
        quest.toCreateRequest(),
      );
      return QuestItem.fromApiResponse(createdQuest);
    } catch (error) {
      _showQuestSyncError('퀘스트를 서버에 저장하지 못했어요.', error);
      return null;
    }
  }

  Future<void> _syncQuestUpdate(QuestItem quest) async {
    if (quest.isTaskBacked) {
      final taskIntakeRepository = _taskIntakeRepository;
      if (taskIntakeRepository == null) {
        return;
      }

      try {
        final updatedTask = await taskIntakeRepository.updateTaskProgress(
          quest.id,
          elapsedSeconds: quest.elapsedSeconds,
        );
        if (!mounted || updatedTask.isCompleted) {
          return;
        }

        final updatedQuest = questItemFromTaskResponse(
          updatedTask,
          fallbackDraft: quest,
        );
        _setLocalData(_replaceQuest(_localData, updatedQuest));
      } catch (error) {
        _showQuestSyncError('Task 진행 시간을 서버에 저장하지 못했어요.', error);
      }
      return;
    }

    final questRepository = _questRepository;
    if (questRepository == null || !quest.syncsWithQuestApi) {
      return;
    }

    try {
      final updatedQuest = await questRepository.updateQuest(
        quest.id,
        quest.toUpdateRequest(),
      );
      if (!mounted) {
        return;
      }
      _setLocalData(
        _replaceQuest(_localData, QuestItem.fromApiResponse(updatedQuest)),
      );
    } catch (error) {
      _showQuestSyncError('퀘스트 변경사항을 서버에 저장하지 못했어요.', error);
    }
  }

  Future<CompletedQuestRecord?> _completeQuest(
    CompletedQuestRecord completedRecord,
  ) async {
    final questRepository = _questRepository;
    final taskIntakeRepository = _taskIntakeRepository;
    final quest = _findQuest(completedRecord.questId);
    if (quest?.isTaskBacked == true) {
      if (taskIntakeRepository == null) {
        return completedRecord;
      }

      try {
        final savedRecord = await _runWithCompletedQuestSavingOverlay(
          () => taskIntakeRepository.completeTask(
            completedRecord.questId,
            elapsedSeconds: completedRecord.elapsedSeconds,
            proofImagePath: completedRecord.proofImagePath,
          ),
        );
        return CompletedQuestRecord.fromApiResponse(savedRecord).copyWith(
          subtasks: completedRecord.subtasks,
          syncTarget: completedRecord.syncTarget,
        );
      } catch (error) {
        _showQuestSyncError(
          'Task completion could not be saved to the server.',
          error,
        );
        _updateQuest(_copyQuestWithElapsed(completedRecord), syncServer: false);
        return null;
      }
    }

    if (questRepository == null || quest?.syncsWithQuestApi != true) {
      return completedRecord;
    }

    try {
      final savedRecord = await _runWithCompletedQuestSavingOverlay(
        () => questRepository.completeQuest(
          completedRecord.questId,
          elapsedSeconds: completedRecord.elapsedSeconds,
          proofImagePath: completedRecord.proofImagePath,
        ),
      );
      return CompletedQuestRecord.fromApiResponse(savedRecord).copyWith(
        subtasks: completedRecord.subtasks,
        syncTarget: completedRecord.syncTarget,
      );
    } catch (error) {
      _showQuestSyncError('퀘스트 완료를 서버에 저장하지 못했어요.', error);
      _updateQuest(_copyQuestWithElapsed(completedRecord), syncServer: false);
      return null;
    }
  }

  Future<T> _runWithCompletedQuestSavingOverlay<T>(
    Future<T> Function() action,
  ) async {
    if (mounted) {
      setState(() => _isSavingCompletedQuest = true);
    }

    try {
      return await action();
    } finally {
      if (mounted) {
        setState(() => _isSavingCompletedQuest = false);
      }
    }
  }

  QuestItem _copyQuestWithElapsed(CompletedQuestRecord completedRecord) {
    final quest = _findQuest(completedRecord.questId);
    if (quest != null) {
      return quest.copyWith(elapsedSeconds: completedRecord.elapsedSeconds);
    }
    return QuestItem(
      id: completedRecord.questId,
      title: completedRecord.title,
      exp: completedRecord.earnedExp,
      difficulty: completedRecord.difficulty,
      category: completedRecord.category,
      elapsedSeconds: completedRecord.elapsedSeconds,
      defaultDurationSeconds: defaultQuestDurationSecondsForDifficulty(
        completedRecord.difficulty,
      ),
    );
  }

  QuestItem? _findQuest(String questId) {
    for (final quest in _localData.quests) {
      if (quest.id == questId) {
        return quest;
      }
    }
    return null;
  }

  AppLocalData _replaceQuest(AppLocalData data, QuestItem updatedQuest) {
    return _replaceQuestById(data, updatedQuest.id, updatedQuest);
  }

  AppLocalData _replaceQuestById(
    AppLocalData data,
    String questId,
    QuestItem updatedQuest,
  ) {
    return data.copyWith(
      quests: data.quests
          .map((item) => item.id == questId ? updatedQuest : item)
          .toList(),
    );
  }

  void _scheduleQuestSyncError(String fallbackMessage, Object error) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showQuestSyncError(fallbackMessage, error);
    });
  }

  void _showQuestSyncError(String fallbackMessage, Object error) {
    if (!mounted) {
      return;
    }
    _logQuestSyncError(fallbackMessage, error);
    _showStyledSnackBar(_questSyncErrorMessage(fallbackMessage, error));
  }

  String _questSyncErrorMessage(String fallbackMessage, Object error) {
    if (error is ApiClientException && error.statusCode == 401) {
      return '로그인이 만료됐어요. 다시 로그인해 주세요.';
    }
    if (error is ApiClientException && error.statusCode == 429) {
      return 'AI 요청 한도에 도달했어요. 잠시 후 다시 시도해 주세요.';
    }
    if (error is ApiClientException && error.code == 'request_timeout') {
      return 'AI 제안 생성 시간이 길어지고 있어요. 네트워크를 확인한 뒤 다시 시도해 주세요.';
    }
    if (error is ApiClientException && error.statusCode == 504) {
      return 'AI 서버 응답 시간이 초과됐어요. 잠시 후 다시 시도해 주세요.';
    }
    if (error is ApiClientException &&
        error.code == 'task_storage_unavailable') {
      return 'AI 제안 저장용 DB 테이블이 아직 적용되지 않았어요. Supabase 마이그레이션 0004~0008 적용을 확인해 주세요.';
    }
    if (error is TaskIntakeRepositoryException &&
        error.code == 'task_storage_unavailable') {
      return 'AI 제안 저장용 DB 테이블이 아직 적용되지 않았어요. Supabase 마이그레이션 0004~0008 적용을 확인해 주세요.';
    }
    if (error is ApiClientException &&
        error.code == 'ai_provider_unavailable') {
      return 'AI 서버 설정 문제가 있어요. 배포 환경변수를 확인해 주세요.';
    }
    if (error is QuestRepositoryException && error.code == 'quest_not_found') {
      return '서버에서 퀘스트를 찾지 못했어요.';
    }
    return fallbackMessage;
  }

  void _logQuestSyncError(String fallbackMessage, Object error) {
    final buffer = StringBuffer('[QuestSyncError] $fallbackMessage')
      ..write('\n  type: ${error.runtimeType}');

    if (error is ApiClientException) {
      buffer
        ..write('\n  status: ${error.statusCode}')
        ..write('\n  code: ${error.code}')
        ..write('\n  message: ${error.message}');
      if (error.requestUri != null) {
        buffer.write('\n  uri: ${error.requestUri}');
      }
      if (error.responseBody != null) {
        buffer.write('\n  responseBody: ${error.responseBody}');
      }
    } else {
      buffer.write('\n  error: $error');
    }

    debugPrint(buffer.toString());
  }

  Future<void> _undoCompletedQuest(CompletedQuestRecord record) async {
    final shouldUndo = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFF1F3F8),
        title: const Text('완료 취소'),
        content: Text('${record.title} 완료를 취소하고 진행중 퀘스트로 되돌릴까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6F63FF),
              foregroundColor: Colors.white,
            ),
            child: const Text('완료 취소'),
          ),
        ],
      ),
    );
    if (!mounted || shouldUndo != true) {
      return;
    }

    final undone = await _undoCompletedQuestOnServer(record);
    if (!mounted || !undone) {
      return;
    }

    _setLocalData(_store.undoCompleteQuest(_localData, record));
    unawaited(_refreshServerProgressData());
    _showStyledSnackBar('완료를 취소하고 진행중으로 되돌렸어요.', centerText: true);
  }

  Future<bool> _undoCompletedQuestOnServer(CompletedQuestRecord record) async {
    if (!_usesServerData) {
      return true;
    }

    final syncTarget = record.syncTarget;
    if (syncTarget == questSyncTargetTask) {
      return _undoCompletedTaskOnServer(record.questId);
    }
    if (syncTarget == questSyncTargetQuest) {
      return _undoCompletedLegacyQuestOnServer(record.questId);
    }

    final taskUndone = await _undoCompletedTaskOnServer(record.questId, quiet: true);
    if (taskUndone) {
      return true;
    }
    return _undoCompletedLegacyQuestOnServer(record.questId);
  }

  Future<bool> _undoCompletedTaskOnServer(
    String taskId, {
    bool quiet = false,
  }) async {
    final repository = _taskIntakeRepository;
    if (repository == null) {
      return !_usesServerData;
    }
    try {
      await repository.undoCompleteTask(taskId);
      return true;
    } catch (error) {
      if (!quiet) {
        _showQuestSyncError('Task 완료 취소를 서버에 저장하지 못했어요.', error);
      }
      return false;
    }
  }

  Future<bool> _undoCompletedLegacyQuestOnServer(String questId) async {
    final repository = _questRepository;
    if (repository == null) {
      return !_usesServerData;
    }
    try {
      await repository.undoCompleteQuest(questId);
      return true;
    } catch (error) {
      _showQuestSyncError('퀘스트 완료 취소를 서버에 저장하지 못했어요.', error);
      return false;
    }
  }

  void _triggerQuestCelebration() {
    _fabPopController.forward(from: 0);
    setState(() {
      _celebrationSeed += 1;
      _showQuestCelebration = true;
    });
  }

  void _hideQuestCelebration() {
    if (!mounted) {
      return;
    }
    setState(() => _showQuestCelebration = false);
  }
}

class _QuestAutoAdvanceOverlay extends StatelessWidget {
  const _QuestAutoAdvanceOverlay({
    required this.remainingSeconds,
    required this.onCancel,
  });

  final int remainingSeconds;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.18),
          ),
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F8FC),
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x24000000),
                    blurRadius: 28,
                    offset: Offset(0, 18),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFE3E7FF),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$remainingSeconds',
                      style: const TextStyle(
                        color: Color(0xFF5C56E8),
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '다음 퀘스트 준비 중',
                    style: TextStyle(
                      color: Color(0xFF151A24),
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '15초 휴식이 끝나면 다음 퀘스트 타이머가 자동으로 시작돼요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF5B6374),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: onCancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF5C56E8),
                        side: const BorderSide(color: Color(0xFFCACFFF)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Text(
                        '자동 진행 취소',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuestCompletionSavingShimmerOverlay extends StatelessWidget {
  const _QuestCompletionSavingShimmerOverlay();

  @override
  Widget build(BuildContext context) {
    return const _SavingShimmerOverlay(title: '완료 기록 저장 중...');
  }
}

class _AiQuestSavingShimmerOverlay extends StatelessWidget {
  const _AiQuestSavingShimmerOverlay();

  @override
  Widget build(BuildContext context) {
    return const _SavingShimmerOverlay(title: 'AI 퀘스트 저장 중...');
  }
}

class _QuestDeletingShimmerOverlay extends StatelessWidget {
  const _QuestDeletingShimmerOverlay({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final title = count > 1 ? '$count개 퀘스트 삭제 중...' : '퀘스트 삭제 중...';
    return _SavingShimmerOverlay(title: title);
  }
}

class _SavingShimmerOverlay extends StatefulWidget {
  const _SavingShimmerOverlay({required this.title});

  final String title;

  @override
  State<_SavingShimmerOverlay> createState() => _SavingShimmerOverlayState();
}

class _SavingShimmerOverlayState extends State<_SavingShimmerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AbsorbPointer(
        child: Container(
          color: const Color(0x66171B2A),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x24171B2A),
                  blurRadius: 28,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF252B3A),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Center(
                    child: LoadingCatIndicator(size: 82, floatDistance: 6),
                  ),
                  const SizedBox(height: 18),
                  _ShimmerBlock(
                    animation: _shimmerController,
                    height: 16,
                    widthFactor: 0.74,
                    borderRadius: 999,
                  ),
                  const SizedBox(height: 12),
                  _ShimmerBlock(
                    animation: _shimmerController,
                    height: 12,
                    widthFactor: 1,
                    borderRadius: 999,
                  ),
                  const SizedBox(height: 8),
                  _ShimmerBlock(
                    animation: _shimmerController,
                    height: 12,
                    widthFactor: 0.86,
                    borderRadius: 999,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _ShimmerBlock(
                          animation: _shimmerController,
                          height: 34,
                          widthFactor: 1,
                          borderRadius: 12,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ShimmerBlock(
                          animation: _shimmerController,
                          height: 34,
                          widthFactor: 1,
                          borderRadius: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShimmerBlock extends StatelessWidget {
  const _ShimmerBlock({
    required this.animation,
    required this.height,
    required this.widthFactor,
    required this.borderRadius,
  });

  final Animation<double> animation;
  final double height;
  final double widthFactor;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final offset = -1.4 + (animation.value * 2.8);
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) {
              return LinearGradient(
                begin: Alignment(offset, -0.6),
                end: Alignment(offset + 1.2, 0.6),
                colors: const [
                  Color(0xFFE5E9F2),
                  Color(0xFFF8FAFF),
                  Color(0xFFE5E9F2),
                ],
                stops: const [0.24, 0.5, 0.76],
              ).createShader(bounds);
            },
            child: child,
          );
        },
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: const Color(0xFFE5E9F2),
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
      ),
    );
  }
}
