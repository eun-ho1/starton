import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:start_on/storage/app_settings_store.dart';

const String _androidQuestTimerOngoingChannelId =
    'start_on_quest_timer_ongoing_v2';
const String _androidQuestTimerCompleteChannelId =
    'start_on_quest_timer_complete';
const int _questTimerOngoingNotificationId = 9042;
const int _questTimerCompleteNotificationId = 9043;
const String _questTimerNotificationIcon = 'ic_bg_service_small';

const String _questTimerTickEvent = 'quest_timer_tick';
const String _questTimerResumeAction = 'quest_timer_resume';
const String _questTimerPauseAction = 'quest_timer_pause';
const String _questTimerStopAction = 'quest_timer_stop';

const String _prefsQuestIdKey = 'quest_timer.quest_id';
const String _prefsQuestTitleKey = 'quest_timer.quest_title';
const String _prefsElapsedSecondsKey = 'quest_timer.elapsed_seconds';
const String _prefsDefaultDurationKey = 'quest_timer.default_duration_seconds';
const String _prefsIsRunningKey = 'quest_timer.is_running';

final FlutterLocalNotificationsPlugin _questTimerNotifications =
    FlutterLocalNotificationsPlugin();
bool _questTimerNotificationsInitialized = false;

bool get _supportsBackgroundService {
  if (kIsWeb) {
    return false;
  }

  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

bool _isUnsupportedBackgroundServiceError(Object error) {
  return error.toString().contains(
    'FlutterBackgroundService is currently supported',
  );
}

Future<void> _ensureQuestTimerNotificationChannels() async {
  if (kIsWeb) {
    return;
  }

  try {
    if (!_questTimerNotificationsInitialized) {
      await _questTimerNotifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(_questTimerNotificationIcon),
          iOS: DarwinInitializationSettings(),
        ),
      );
      _questTimerNotificationsInitialized = true;
    }

    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    final androidNotifications = _questTimerNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidNotifications?.createNotificationChannel(
      const AndroidNotificationChannel(
        _androidQuestTimerOngoingChannelId,
        '퀘스트 진행 알림',
        description: '타이머가 실행 중일 때 남은 시간을 표시합니다.',
        importance: Importance.high,
        showBadge: false,
      ),
    );
    await androidNotifications?.createNotificationChannel(
      const AndroidNotificationChannel(
        _androidQuestTimerCompleteChannelId,
        '퀘스트 완료 알림',
        description: '퀘스트 타이머 완료 알림',
        importance: Importance.high,
      ),
    );
  } on MissingPluginException {
    return;
  } on PlatformException {
    return;
  }
}

Future<void> _showQuestTimerCompleteNotification(
  QuestTimerSnapshot snapshot,
) async {
  if (kIsWeb) {
    return;
  }

  try {
    await _ensureQuestTimerNotificationChannels();
    await _questTimerNotifications.show(
      id: _questTimerCompleteNotificationId,
      title: '퀘스트 타이머 완료',
      body: snapshot.questTitle.isEmpty
          ? '설정한 시간이 끝났어요.'
          : '${snapshot.questTitle} 시간이 끝났어요.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _androidQuestTimerCompleteChannelId,
          '퀘스트 완료 알림',
          channelDescription: '퀘스트 타이머 완료 알림',
          icon: _questTimerNotificationIcon,
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.public,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  } on MissingPluginException {
    return;
  } on PlatformException {
    return;
  }
}

int _questTimerEndTimeMillis(QuestTimerSnapshot snapshot) {
  final remainingSeconds =
      snapshot.defaultDurationSeconds - snapshot.elapsedSeconds;
  final clampedRemainingSeconds = remainingSeconds > 0 ? remainingSeconds : 0;
  return DateTime.now()
      .add(Duration(seconds: clampedRemainingSeconds))
      .millisecondsSinceEpoch;
}

Future<void> _showQuestTimerOngoingNotification(
  QuestTimerSnapshot snapshot,
) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return;
  }

  try {
    await _ensureQuestTimerNotificationChannels();
    await _questTimerNotifications.show(
      id: _questTimerOngoingNotificationId,
      title: '퀘스트 진행 중',
      body: snapshot.questTitle.isEmpty ? '남은 시간을 확인하세요.' : snapshot.questTitle,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _androidQuestTimerOngoingChannelId,
          '퀘스트 진행 알림',
          channelDescription: '타이머가 실행 중일 때 남은 시간을 표시합니다.',
          icon: _questTimerNotificationIcon,
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.public,
          category: AndroidNotificationCategory.alarm,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          showWhen: true,
          when: _questTimerEndTimeMillis(snapshot),
          usesChronometer: true,
          chronometerCountDown: true,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  } on MissingPluginException {
    return;
  } on PlatformException {
    return;
  }
}

Future<void> _cancelQuestTimerOngoingNotification() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return;
  }

  try {
    await _ensureQuestTimerNotificationChannels();
    await _questTimerNotifications.cancel(id: _questTimerOngoingNotificationId);
  } on MissingPluginException {
    return;
  } on PlatformException {
    return;
  }
}

class QuestTimerSnapshot {
  const QuestTimerSnapshot({
    required this.questId,
    required this.questTitle,
    required this.elapsedSeconds,
    required this.defaultDurationSeconds,
    required this.isRunning,
  });

  final String questId;
  final String questTitle;
  final int elapsedSeconds;
  final int defaultDurationSeconds;
  final bool isRunning;

  QuestTimerSnapshot copyWith({
    String? questId,
    String? questTitle,
    int? elapsedSeconds,
    int? defaultDurationSeconds,
    bool? isRunning,
  }) {
    return QuestTimerSnapshot(
      questId: questId ?? this.questId,
      questTitle: questTitle ?? this.questTitle,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      defaultDurationSeconds:
          defaultDurationSeconds ?? this.defaultDurationSeconds,
      isRunning: isRunning ?? this.isRunning,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'questId': questId,
      'questTitle': questTitle,
      'elapsedSeconds': elapsedSeconds,
      'defaultDurationSeconds': defaultDurationSeconds,
      'isRunning': isRunning,
    };
  }

  static QuestTimerSnapshot? fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return null;
    }

    final questId = map['questId'] as String?;
    if (questId == null || questId.isEmpty) {
      return null;
    }

    return QuestTimerSnapshot(
      questId: questId,
      questTitle: map['questTitle'] as String? ?? '',
      elapsedSeconds: (map['elapsedSeconds'] as num?)?.toInt() ?? 0,
      defaultDurationSeconds:
          (map['defaultDurationSeconds'] as num?)?.toInt() ?? 0,
      isRunning: map['isRunning'] as bool? ?? false,
    );
  }
}

class QuestTimerBackgroundService {
  QuestTimerBackgroundService._();

  static final QuestTimerBackgroundService instance =
      QuestTimerBackgroundService._();

  final FlutterBackgroundService _service = FlutterBackgroundService();

  Stream<QuestTimerSnapshot> get timerTicks {
    if (!_supportsBackgroundService) {
      return const Stream<QuestTimerSnapshot>.empty();
    }

    try {
      return _service
          .on(_questTimerTickEvent)
          .map((data) {
            final normalized = data == null
                ? null
                : Map<String, dynamic>.from(data);
            return QuestTimerSnapshot.fromMap(normalized);
          })
          .where((snapshot) => snapshot != null)
          .cast<QuestTimerSnapshot>();
    } catch (error) {
      if (_isUnsupportedBackgroundServiceError(error)) {
        return const Stream<QuestTimerSnapshot>.empty();
      }
      rethrow;
    }
  }

  Future<void> initialize() async {
    if (!_supportsBackgroundService) {
      return;
    }

    try {
      await _ensureQuestTimerNotificationChannels();
      await _service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: questTimerBackgroundOnStart,
          autoStart: false,
          autoStartOnBoot: false,
          isForegroundMode: true,
          initialNotificationTitle: '퀘스트 진행 중',
          initialNotificationContent: '타이머가 백그라운드에서 실행 중입니다.',
          notificationChannelId: _androidQuestTimerOngoingChannelId,
          foregroundServiceNotificationId: _questTimerOngoingNotificationId,
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: questTimerBackgroundOnStart,
          onBackground: questTimerBackgroundOnIosBackground,
        ),
      );
    } catch (error) {
      if (_isUnsupportedBackgroundServiceError(error)) {
        return;
      }
      rethrow;
    }

    final settings = await const AppSettingsStore().load();
    final snapshot = await currentState();
    if (!settings.notificationsEnabled) {
      if (snapshot?.isRunning == true) {
        await pauseTimer(
          questId: snapshot!.questId,
          questTitle: snapshot.questTitle,
          elapsedSeconds: snapshot.elapsedSeconds,
          defaultDurationSeconds: snapshot.defaultDurationSeconds,
        );
      }
      return;
    }

    if (snapshot?.isRunning != true) {
      return;
    }

    if (!await _isServiceRunning()) {
      await _startServiceIfSupported();
    }
  }

  Future<void> startOrResumeTimer({
    required String questId,
    required String questTitle,
    required int elapsedSeconds,
    required int defaultDurationSeconds,
  }) async {
    final snapshot = QuestTimerSnapshot(
      questId: questId,
      questTitle: questTitle,
      elapsedSeconds: elapsedSeconds,
      defaultDurationSeconds: defaultDurationSeconds,
      isRunning: true,
    );

    await _persistSnapshot(snapshot);

    if (!_supportsBackgroundService) {
      return;
    }

    if (await _isServiceRunning()) {
      _service.invoke(_questTimerResumeAction, snapshot.toMap());
      return;
    }

    await _startServiceIfSupported();
  }

  Future<void> pauseTimer({
    required String questId,
    required String questTitle,
    required int elapsedSeconds,
    required int defaultDurationSeconds,
  }) async {
    final snapshot = QuestTimerSnapshot(
      questId: questId,
      questTitle: questTitle,
      elapsedSeconds: elapsedSeconds,
      defaultDurationSeconds: defaultDurationSeconds,
      isRunning: false,
    );

    await _persistSnapshot(snapshot);

    if (!_supportsBackgroundService) {
      return;
    }

    if (await _isServiceRunning()) {
      _service.invoke(_questTimerPauseAction, snapshot.toMap());
    } else {
      await _cancelQuestTimerOngoingNotification();
    }
  }

  Future<void> stopTimer() async {
    await _clearSnapshot();

    if (!_supportsBackgroundService) {
      return;
    }

    if (await _isServiceRunning()) {
      _service.invoke(_questTimerStopAction);
    } else {
      await _cancelQuestTimerOngoingNotification();
    }
  }

  Future<QuestTimerSnapshot?> currentState() async {
    final prefs = await SharedPreferences.getInstance();
    final questId = prefs.getString(_prefsQuestIdKey);
    if (questId == null || questId.isEmpty) {
      return null;
    }

    return QuestTimerSnapshot(
      questId: questId,
      questTitle: prefs.getString(_prefsQuestTitleKey) ?? '',
      elapsedSeconds: prefs.getInt(_prefsElapsedSecondsKey) ?? 0,
      defaultDurationSeconds: prefs.getInt(_prefsDefaultDurationKey) ?? 0,
      isRunning: prefs.getBool(_prefsIsRunningKey) ?? false,
    );
  }

  Future<void> _persistSnapshot(QuestTimerSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsQuestIdKey, snapshot.questId);
    await prefs.setString(_prefsQuestTitleKey, snapshot.questTitle);
    await prefs.setInt(_prefsElapsedSecondsKey, snapshot.elapsedSeconds);
    await prefs.setInt(
      _prefsDefaultDurationKey,
      snapshot.defaultDurationSeconds,
    );
    await prefs.setBool(_prefsIsRunningKey, snapshot.isRunning);
  }

  Future<void> _clearSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsQuestIdKey);
    await prefs.remove(_prefsQuestTitleKey);
    await prefs.remove(_prefsElapsedSecondsKey);
    await prefs.remove(_prefsDefaultDurationKey);
    await prefs.remove(_prefsIsRunningKey);
  }

  Future<bool> _isServiceRunning() async {
    try {
      return await _service.isRunning();
    } catch (error) {
      if (_isUnsupportedBackgroundServiceError(error)) {
        return false;
      }
      rethrow;
    }
  }

  Future<void> _startServiceIfSupported() async {
    try {
      await _service.startService();
    } catch (error) {
      if (_isUnsupportedBackgroundServiceError(error)) {
        return;
      }
      rethrow;
    }
  }
}

@pragma('vm:entry-point')
Future<bool> questTimerBackgroundOnIosBackground(
  ServiceInstance service,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void questTimerBackgroundOnStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  Timer? ticker;

  Future<QuestTimerSnapshot?> loadSnapshot() async {
    final questId = prefs.getString(_prefsQuestIdKey);
    if (questId == null || questId.isEmpty) {
      return null;
    }

    return QuestTimerSnapshot(
      questId: questId,
      questTitle: prefs.getString(_prefsQuestTitleKey) ?? '',
      elapsedSeconds: prefs.getInt(_prefsElapsedSecondsKey) ?? 0,
      defaultDurationSeconds: prefs.getInt(_prefsDefaultDurationKey) ?? 0,
      isRunning: prefs.getBool(_prefsIsRunningKey) ?? false,
    );
  }

  Future<void> persistSnapshot(QuestTimerSnapshot snapshot) async {
    await prefs.setString(_prefsQuestIdKey, snapshot.questId);
    await prefs.setString(_prefsQuestTitleKey, snapshot.questTitle);
    await prefs.setInt(_prefsElapsedSecondsKey, snapshot.elapsedSeconds);
    await prefs.setInt(
      _prefsDefaultDurationKey,
      snapshot.defaultDurationSeconds,
    );
    await prefs.setBool(_prefsIsRunningKey, snapshot.isRunning);
  }

  Future<void> clearSnapshot() async {
    await prefs.remove(_prefsQuestIdKey);
    await prefs.remove(_prefsQuestTitleKey);
    await prefs.remove(_prefsElapsedSecondsKey);
    await prefs.remove(_prefsDefaultDurationKey);
    await prefs.remove(_prefsIsRunningKey);
  }

  Future<void> emitSnapshot(QuestTimerSnapshot snapshot) async {
    service.invoke(_questTimerTickEvent, snapshot.toMap());
  }

  void stopTicker() {
    ticker?.cancel();
    ticker = null;
  }

  Future<void> startTicker(QuestTimerSnapshot snapshot) async {
    stopTicker();
    await _showQuestTimerOngoingNotification(snapshot);
    await emitSnapshot(snapshot);

    ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      final current = await loadSnapshot();
      if (current == null || !current.isRunning) {
        return;
      }

      final wasBeforeComplete =
          current.defaultDurationSeconds > 0 &&
          current.elapsedSeconds < current.defaultDurationSeconds;
      final nextSnapshot = current.copyWith(
        elapsedSeconds: current.elapsedSeconds + 1,
      );
      await persistSnapshot(nextSnapshot);
      await emitSnapshot(nextSnapshot);

      if (wasBeforeComplete &&
          nextSnapshot.elapsedSeconds >= nextSnapshot.defaultDurationSeconds) {
        await _showQuestTimerCompleteNotification(nextSnapshot);
      }
    });
  }

  final initialSnapshot = await loadSnapshot();
  if (initialSnapshot == null || !initialSnapshot.isRunning) {
    service.stopSelf();
    return;
  }

  await startTicker(initialSnapshot);

  service.on(_questTimerResumeAction).listen((data) async {
    final snapshot = QuestTimerSnapshot.fromMap(
      data == null ? null : Map<String, dynamic>.from(data),
    );
    if (snapshot == null) {
      return;
    }

    await persistSnapshot(snapshot.copyWith(isRunning: true));
    await startTicker(snapshot.copyWith(isRunning: true));
  });

  service.on(_questTimerPauseAction).listen((data) async {
    final snapshot = QuestTimerSnapshot.fromMap(
      data == null ? null : Map<String, dynamic>.from(data),
    );
    if (snapshot == null) {
      stopTicker();
      service.stopSelf();
      return;
    }

    final pausedSnapshot = snapshot.copyWith(isRunning: false);
    await persistSnapshot(pausedSnapshot);
    await emitSnapshot(pausedSnapshot);
    stopTicker();
    await _cancelQuestTimerOngoingNotification();
    service.stopSelf();
  });

  service.on(_questTimerStopAction).listen((_) async {
    stopTicker();
    await clearSnapshot();
    await _cancelQuestTimerOngoingNotification();
    service.stopSelf();
  });
}
