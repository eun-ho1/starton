import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:start_on/services/notion_sync_service.dart';
import 'package:start_on/storage/app_settings_store.dart';
import 'package:start_on/storage/local_data_store.dart';
import 'package:start_on/widgets/common.dart';

class SettingsScreenResult {
  const SettingsScreenResult._({
    this.shouldChangeAccount = false,
    this.didSyncNotion = false,
  });

  static const requestAccountChange = SettingsScreenResult._(
    shouldChangeAccount: true,
  );
  static const syncedNotion = SettingsScreenResult._(didSyncNotion: true);

  final bool shouldChangeAccount;
  final bool didSyncNotion;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.userName,
    this.userEmail,
    AppSettingsStore? settingsStore,
    LocalDataStore? localDataStore,
    NotionSyncService? notionSyncService,
  }) : _settingsStore = settingsStore,
       _localDataStore = localDataStore,
       _notionSyncService = notionSyncService;

  final String? userName;
  final String? userEmail;
  final AppSettingsStore? _settingsStore;
  final LocalDataStore? _localDataStore;
  final NotionSyncService? _notionSyncService;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final AppSettingsStore _settingsStore =
      widget._settingsStore ?? const AppSettingsStore();
  late final LocalDataStore _localDataStore =
      widget._localDataStore ?? const LocalDataStore();
  late final NotionSyncService _notionSyncService =
      widget._notionSyncService ?? NotionSyncService();
  final TextEditingController _notionTokenController = TextEditingController();
  final TextEditingController _notionDatabaseController =
      TextEditingController();

  bool _notificationsEnabled = true;
  bool _vibrationEnabled = true;
  bool _celebrationEffectEnabled = true;
  bool _autoSaveEnabled = true;
  bool _isNotionSyncEnabled = false;
  bool _isNotionSyncBusy = false;
  bool _isCheckingNotionStatus = true;
  bool _isNotionTokenVisible = false;
  String? _notionStatusErrorMessage;
  String _notionDatabaseId = '';
  String _notionDatabaseTitle = '';
  bool _didSyncNotionThisSession = false;

  bool get _canInteractWithNotionControls =>
      !_isNotionSyncBusy &&
      !_isCheckingNotionStatus &&
      _notionStatusErrorMessage == null;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _notionTokenController.dispose();
    _notionDatabaseController.dispose();
    _notionSyncService.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF8EF), Color(0xFFF7FBFF), Color(0xFFFFF0F3)],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 32),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: _closeSettings,
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    '설정',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1C2940),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              RoundedCard(
                padding: const EdgeInsets.all(20),
                child: _AccountSummaryCard(
                  userName: widget.userName ?? '사용자',
                  userEmail: widget.userEmail ?? '',
                  onChangeAccount: _requestAccountChange,
                ),
              ),
              const SizedBox(height: 18),
              RoundedCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeading(
                      icon: Icons.tune_rounded,
                      title: '환경 설정',
                    ),
                    const SizedBox(height: 14),
                    _SettingsSwitchTile(
                      icon: Icons.calendar_today_outlined,
                      switchKey: const Key('settings.notion.switch'),
                      title: 'Notion 연동',
                      subtitle: _notionSwitchSubtitle,
                      value: _isNotionSyncEnabled,
                      onChanged: !_canInteractWithNotionControls
                          ? null
                          : _handleNotionCalendarToggle,
                    ),
                    const SizedBox(height: 10),
                    const _SettingsSetupGuide(
                      title: '빠른 설정 안내',
                      steps: [
                        'Notion Dev Page에서 connection을 생성하세요.',
                        '생성된 내부 연동 시크릿 토큰을 복사하세요.',
                        '연동하려는 데이터베이스에 생성한 connection을 연결하세요.',
                        '데이터베이스 ID는 데이터베이스를 새 창으로 연 뒤 URL의 /p/와 ?v 사이에 있는 값을 복사하면 됩니다.',
                      ],
                    ),
                    const SizedBox(height: 10),
                    _NotionCredentialFields(
                      tokenController: _notionTokenController,
                      databaseController: _notionDatabaseController,
                      isBusy: _isNotionSyncBusy || _isCheckingNotionStatus,
                      isTokenVisible: _isNotionTokenVisible,
                      onTokenChanged: _handleNotionTokenChanged,
                      onDatabaseChanged: _handleNotionDatabaseChanged,
                      onToggleTokenVisibility: () {
                        setState(
                          () => _isNotionTokenVisible = !_isNotionTokenVisible,
                        );
                      },
                    ),
                    if (_isCheckingNotionStatus) ...[
                      const SizedBox(height: 10),
                      const _SettingsStatusTile(
                        icon: Icons.hourglass_top_rounded,
                        title: 'Notion 연결 상태 확인 중',
                        subtitle: '서버에 저장된 Notion 연결 상태를 확인하고 있어요.',
                        buttonLabel: '확인 중...',
                      ),
                    ] else if (_notionStatusErrorMessage != null) ...[
                      const SizedBox(height: 10),
                      _SettingsStatusTile(
                        icon: Icons.error_outline_rounded,
                        title: 'Notion 연결 상태를 확인할 수 없어요',
                        subtitle: _notionStatusErrorMessage!,
                        buttonLabel: '다시 시도',
                        buttonKey: const Key('settings.notion.retry'),
                        onPressed: _isNotionSyncBusy
                            ? null
                            : _refreshNotionStatus,
                      ),
                    ] else if (_isNotionSyncEnabled) ...[
                      const SizedBox(height: 10),
                      _SettingsActionTile(
                        icon: Icons.sync_rounded,
                        title: _notionDatabaseTitle.isEmpty
                            ? 'Notion 연결됨'
                            : _notionDatabaseTitle,
                        subtitle: _notionDatabaseId.isEmpty
                            ? '선택된 데이터베이스가 없어요'
                            : _notionDatabaseId,
                        buttonLabel: _isNotionSyncBusy ? '동기화 중...' : '지금 동기화',
                        onPressed: _isNotionSyncBusy ? null : _syncNotionTasks,
                        secondaryButtonLabel: '연결 해제',
                        onSecondaryPressed: _isNotionSyncBusy
                            ? null
                            : _disconnectNotion,
                        primaryButtonKey: const Key('settings.notion.sync'),
                        secondaryButtonKey: const Key(
                          'settings.notion.disconnect',
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 10),
                      _SettingsStatusTile(
                        icon: Icons.link_rounded,
                        title: 'Notion 연동 준비 완료',
                        subtitle: '토큰과 데이터베이스 정보를 입력한 뒤 연동 버튼을 눌러 주세요.',
                        buttonLabel: _isNotionSyncBusy ? '연동 중...' : '연동하기',
                        buttonKey: const Key('settings.notion.connect'),
                        onPressed: _isNotionSyncBusy ? null : _connectNotion,
                      ),
                    ],
                    const SizedBox(height: 14),
                    _SettingsSwitchTile(
                      icon: Icons.notifications_none_rounded,
                      title: '알림',
                      subtitle: '진행 중인 할 일을 잊지 않도록 알림을 받아요.',
                      value: _notificationsEnabled,
                      onChanged: _updateNotificationsEnabled,
                    ),
                    const SizedBox(height: 10),
                    _SettingsSwitchTile(
                      icon: Icons.vibration_rounded,
                      title: '진동',
                      subtitle: '주요 동작에서 진동 피드백을 사용해요.',
                      value: _vibrationEnabled,
                      onChanged: (value) => _updateSetting(
                        (settings) =>
                            settings.copyWith(vibrationEnabled: value),
                        () => _vibrationEnabled = value,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _SettingsSwitchTile(
                      icon: Icons.auto_awesome_rounded,
                      title: '완료 효과',
                      subtitle: '퀘스트 완료 시 간단한 연출을 보여줘요.',
                      value: _celebrationEffectEnabled,
                      onChanged: (value) => _updateSetting(
                        (settings) =>
                            settings.copyWith(celebrationEffectEnabled: value),
                        () => _celebrationEffectEnabled = value,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _SettingsSwitchTile(
                      icon: Icons.save_outlined,
                      title: '자동 저장',
                      subtitle: '진행 중인 상태를 기기에 자동 저장해요.',
                      value: _autoSaveEnabled,
                      onChanged: (value) => _updateSetting(
                        (settings) => settings.copyWith(autoSaveEnabled: value),
                        () => _autoSaveEnabled = value,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              RoundedCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SectionHeading(
                      icon: Icons.timer_outlined,
                      title: '기본 퀘스트 시간',
                    ),
                    SizedBox(height: 16),
                    _SettingsInfoRow(label: '쉬움', value: '25분'),
                    SizedBox(height: 12),
                    _SettingsInfoRow(label: '보통', value: '45분'),
                    SizedBox(height: 12),
                    _SettingsInfoRow(label: '어려움', value: '90분'),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              RoundedCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SectionHeading(
                      icon: Icons.info_outline_rounded,
                      title: '앱 정보',
                    ),
                    SizedBox(height: 16),
                    _SettingsInfoRow(label: '버전', value: '1.0.0+1'),
                    SizedBox(height: 12),
                    _SettingsInfoRow(label: '테마', value: '라이트'),
                    SizedBox(height: 12),
                    _SettingsInfoRow(label: '저장소', value: '로컬 저장소'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleNotionCalendarToggle(bool newValue) async {
    if (!_canInteractWithNotionControls) {
      return;
    }
    if (newValue) {
      final success = await _connectNotion();
      if (!mounted) {
        return;
      }
      setState(() => _isNotionSyncEnabled = success);
      return;
    }

    await _disconnectNotion();
    if (!mounted) {
      return;
    }
    setState(() => _isNotionSyncEnabled = false);
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsStore.load();
    if (!mounted) {
      return;
    }

    _notionTokenController.text = settings.notionApiToken;
    _notionDatabaseController.text = settings.notionDatabaseId;

    setState(() {
      _notificationsEnabled = settings.notificationsEnabled;
      _vibrationEnabled = settings.vibrationEnabled;
      _celebrationEffectEnabled = settings.celebrationEffectEnabled;
      _autoSaveEnabled = settings.autoSaveEnabled;
      _isNotionSyncEnabled = false;
      _isCheckingNotionStatus = true;
      _notionStatusErrorMessage = null;
      _notionDatabaseId = '';
      _notionDatabaseTitle = '';
    });

    await _refreshNotionStatus(fallbackSettings: settings);
  }

  Future<void> _refreshNotionStatus({AppSettings? fallbackSettings}) async {
    final settings = fallbackSettings ?? await _settingsStore.load();
    if (mounted) {
      setState(() {
        _isCheckingNotionStatus = true;
        _notionStatusErrorMessage = null;
        _isNotionSyncEnabled = false;
        _notionDatabaseId = '';
        _notionDatabaseTitle = '';
      });
    }

    try {
      final status = await _notionSyncService.fetchStatus();
      await _applyServerNotionStatus(status, fallbackSettings: settings);
    } on NotionSyncException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isCheckingNotionStatus = false;
        _isNotionSyncEnabled = false;
        _notionDatabaseId = '';
        _notionDatabaseTitle = '';
        _notionStatusErrorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isCheckingNotionStatus = false;
        _isNotionSyncEnabled = false;
        _notionDatabaseId = '';
        _notionDatabaseTitle = '';
        _notionStatusErrorMessage = 'Notion 연결 상태를 확인하지 못했어요. 다시 시도해 주세요.';
      });
    }
  }

  Future<void> _applyServerNotionStatus(
    NotionConnectionStatus status, {
    required AppSettings fallbackSettings,
  }) async {
    final isConnected = status.connected;
    final databaseId = isConnected ? (status.databaseId ?? '') : '';
    final databaseTitle = isConnected ? (status.databaseTitle ?? '') : '';
    final preservedInput = fallbackSettings.notionDatabaseId;

    final nextSettings = fallbackSettings.copyWith(
      notionSyncEnabled: isConnected,
      notionApiToken: fallbackSettings.notionApiToken,
      notionDatabaseId: isConnected ? databaseId : preservedInput,
      notionDatabaseTitle: isConnected ? databaseTitle : '',
    );
    await _settingsStore.save(nextSettings);

    if (!mounted) {
      return;
    }

    _notionTokenController.text = fallbackSettings.notionApiToken;
    _notionDatabaseController.text = isConnected ? databaseId : preservedInput;

    setState(() {
      _isCheckingNotionStatus = false;
      _notionStatusErrorMessage = null;
      _isNotionSyncEnabled = isConnected;
      _notionDatabaseId = databaseId;
      _notionDatabaseTitle = databaseTitle;
    });
  }

  Future<bool> _connectNotion() async {
    if (!mounted || !_canInteractWithNotionControls) {
      return false;
    }
    return _syncNotionTasks(
      input: _NotionConnectionInput(
        apiToken: _notionTokenController.text,
        databaseInput: _notionDatabaseController.text,
      ),
      enableSync: true,
    );
  }

  Future<void> _disconnectNotion() async {
    if (!mounted || _isNotionSyncBusy || _isCheckingNotionStatus) {
      return;
    }
    setState(() => _isNotionSyncBusy = true);

    try {
      await _notionSyncService.disconnectConnection();
      final currentSettings = await _settingsStore.load();
      await _settingsStore.save(
        currentSettings.copyWith(
          notionSyncEnabled: false,
          notionApiToken: _notionTokenController.text.trim(),
          notionDatabaseId: _notionDatabaseController.text.trim(),
          notionDatabaseTitle: '',
        ),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isNotionSyncEnabled = false;
        _notionDatabaseId = '';
        _notionDatabaseTitle = '';
        _notionStatusErrorMessage = null;
      });
      _showMessage('Notion 연결을 해제했어요.');
    } on NotionSyncException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('Notion 연결 해제에 실패했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) {
        setState(() => _isNotionSyncBusy = false);
      }
    }
  }

  Future<bool> _syncNotionTasks({
    _NotionConnectionInput? input,
    bool enableSync = false,
  }) async {
    if (_isNotionSyncBusy || _isCheckingNotionStatus) {
      return false;
    }

    final settings = await _settingsStore.load();
    final apiToken = (input?.apiToken ?? settings.notionApiToken).trim();
    final databaseInput = (input?.databaseInput ?? settings.notionDatabaseId)
        .trim();
    final isConnecting = input != null;

    if (isConnecting && (apiToken.isEmpty || databaseInput.isEmpty)) {
      _showMessage('Notion 토큰과 데이터베이스 URL 또는 ID를 모두 입력해 주세요.');
      return false;
    }
    if (!isConnecting && !settings.notionSyncEnabled) {
      _showMessage('동기화 전에 먼저 Notion을 다시 연결해 주세요.');
      return false;
    }

    if (!mounted) {
      return false;
    }
    setState(() => _isNotionSyncBusy = true);

    try {
      final result = isConnecting
          ? await _notionSyncService.syncDatabase(
              NotionSyncConfig(
                apiToken: apiToken,
                databaseInput: databaseInput,
              ),
            )
          : await _notionSyncService.syncSavedConnection();

      await _settingsStore.save(
        settings.copyWith(
          notionSyncEnabled: true,
          notionApiToken: apiToken.isEmpty ? settings.notionApiToken : apiToken,
          notionDatabaseId: result.databaseId,
          notionDatabaseTitle: result.databaseTitle,
        ),
      );

      final currentData = await _localDataStore.load();
      await _localDataStore.save(
        _localDataStore.replaceNotionQuests(currentData, result.quests),
      );

      if (!mounted) {
        return true;
      }

      _notionTokenController.text = apiToken.isEmpty
          ? settings.notionApiToken
          : apiToken;
      _notionDatabaseController.text = result.databaseId;

      setState(() {
        _isNotionSyncEnabled = true;
        _notionDatabaseId = result.databaseId;
        _notionDatabaseTitle = result.databaseTitle;
        _notionStatusErrorMessage = null;
        _didSyncNotionThisSession = true;
      });
      _showMessage(
        enableSync
            ? 'Notion 퀘스트 ${result.quests.length}개를 가져왔어요.'
            : 'Notion 퀘스트 ${result.quests.length}개를 동기화했어요.',
      );
      return true;
    } on NotionSyncException catch (error) {
      _showMessage(error.message);
      return false;
    } catch (_) {
      _showMessage('Notion 동기화에 실패했어요. 다시 시도해 주세요.');
      return false;
    } finally {
      if (mounted) {
        setState(() => _isNotionSyncBusy = false);
      }
    }
  }

  Future<void> _updateNotificationsEnabled(bool value) async {
    var nextValue = value;
    if (value) {
      final status = await Permission.notification.request();
      nextValue = status.isGranted;
    }

    await _updateSetting(
      (settings) => settings.copyWith(notificationsEnabled: nextValue),
      () => _notificationsEnabled = nextValue,
    );

    if (!value || nextValue || !mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('알림을 켜려면 알림 권한이 필요해요.')));
  }

  Future<void> _updateSetting(
    AppSettings Function(AppSettings current) transformer,
    VoidCallback applyState,
  ) async {
    final current = await _settingsStore.load();
    final next = transformer(current);
    await _settingsStore.save(next);
    if (!mounted) {
      return;
    }
    setState(applyState);
  }

  void _handleNotionTokenChanged(String value) {
    unawaited(_persistNotionDraft(apiToken: value));
  }

  void _handleNotionDatabaseChanged(String value) {
    unawaited(_persistNotionDraft(databaseInput: value));
  }

  Future<void> _persistNotionDraft({
    String? apiToken,
    String? databaseInput,
  }) async {
    final current = await _settingsStore.load();
    await _settingsStore.save(
      current.copyWith(
        notionApiToken: apiToken ?? _notionTokenController.text.trim(),
        notionDatabaseId:
            databaseInput ?? _notionDatabaseController.text.trim(),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _requestAccountChange() {
    Navigator.of(context).pop(SettingsScreenResult.requestAccountChange);
  }

  void _closeSettings() {
    Navigator.of(context).pop(
      _didSyncNotionThisSession ? SettingsScreenResult.syncedNotion : null,
    );
  }

  String get _notionSwitchSubtitle {
    if (_isCheckingNotionStatus) {
      return '저장된 Notion 연결 상태를 확인하고 있어요.';
    }
    if (_notionStatusErrorMessage != null) {
      return '연결 상태를 확인할 수 없어요. 다시 시도해 주세요.';
    }
    return 'Notion의 미완료 작업을 퀘스트로 동기화해요.';
  }
}

class _AccountSummaryCard extends StatelessWidget {
  const _AccountSummaryCard({
    required this.userName,
    required this.userEmail,
    required this.onChangeAccount,
  });

  final String userName;
  final String userEmail;
  final VoidCallback onChangeAccount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFFE9E7FF),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.person_rounded,
            color: Color(0xFF6F63FF),
            size: 28,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                userName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1C2940),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                userEmail.isEmpty ? '로컬 계정' : userEmail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF7E899D),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: onChangeAccount,
          icon: const Icon(Icons.manage_accounts_rounded, size: 18),
          label: const Text('변경'),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFFF5E6B),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  const _SettingsSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.switchKey,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Key? switchKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FBFF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFFFEEF0),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFFFF8B93), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF33415C),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF7E899D),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            key: switchKey,
            value: value,
            activeThumbColor: const Color(0xFFFF8B93),
            activeTrackColor: const Color(0xFFFFD2D7),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SettingsActionTile extends StatelessWidget {
  const _SettingsActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onPressed,
    this.secondaryButtonLabel,
    this.onSecondaryPressed,
    this.primaryButtonKey,
    this.secondaryButtonKey,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback? onPressed;
  final String? secondaryButtonLabel;
  final VoidCallback? onSecondaryPressed;
  final Key? primaryButtonKey;
  final Key? secondaryButtonKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFE1E6)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFFFEEF0),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFFFF8B93), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF33415C),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF7E899D),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(
                key: primaryButtonKey,
                onPressed: onPressed,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF8B93),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(buttonLabel),
              ),
              if (secondaryButtonLabel != null) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  key: secondaryButtonKey,
                  onPressed: onSecondaryPressed,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF5E6B),
                    side: const BorderSide(color: Color(0xFFFFC2CA)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(secondaryButtonLabel!),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsSetupGuide extends StatelessWidget {
  const _SettingsSetupGuide({required this.title, required this.steps});

  final String title;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF7EE),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF6DFC2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.tips_and_updates_outlined,
                color: Color(0xFFCA8A2D),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF5A4421),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final step in steps) ...[
            Text(
              '• $step',
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: Color(0xFF6D5730),
                fontWeight: FontWeight.w500,
              ),
            ),
            if (step != steps.last) const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

class _SettingsStatusTile extends StatelessWidget {
  const _SettingsStatusTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    this.buttonKey,
    this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final Key? buttonKey;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return _SettingsActionTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      buttonLabel: buttonLabel,
      onPressed: onPressed,
      primaryButtonKey: buttonKey,
    );
  }
}

class _NotionCredentialFields extends StatelessWidget {
  const _NotionCredentialFields({
    required this.tokenController,
    required this.databaseController,
    required this.isBusy,
    required this.isTokenVisible,
    required this.onTokenChanged,
    required this.onDatabaseChanged,
    required this.onToggleTokenVisibility,
  });

  final TextEditingController tokenController;
  final TextEditingController databaseController;
  final bool isBusy;
  final bool isTokenVisible;
  final ValueChanged<String> onTokenChanged;
  final ValueChanged<String> onDatabaseChanged;
  final VoidCallback onToggleTokenVisibility;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FBFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4ECF7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Notion 연동 정보',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF33415C),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('settings.notion.token'),
            controller: tokenController,
            enabled: !isBusy,
            obscureText: !isTokenVisible,
            onChanged: onTokenChanged,
            decoration: InputDecoration(
              labelText: 'Notion 토큰',
              hintText: 'secret_xxx 또는 ntn_xxx',
              helperText: 'Notion Integration Secret을 입력해 주세요.',
              suffixIcon: IconButton(
                onPressed: isBusy ? null : onToggleTokenVisibility,
                icon: Icon(
                  isTokenVisible
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('settings.notion.database'),
            controller: databaseController,
            enabled: !isBusy,
            onChanged: onDatabaseChanged,
            decoration: const InputDecoration(
              labelText: '데이터베이스 URL 또는 ID',
              hintText: 'https://www.notion.so/... 또는 UUID',
              helperText: '데이터 소스 ID도 그대로 입력할 수 있어요.',
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsInfoRow extends StatelessWidget {
  const _SettingsInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            color: Color(0xFF667085),
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            color: Color(0xFF33415C),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _NotionConnectionInput {
  const _NotionConnectionInput({
    required this.apiToken,
    required this.databaseInput,
  });

  final String apiToken;
  final String databaseInput;
}
