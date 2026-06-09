import 'dart:convert';
import 'dart:math' as math;

import 'package:start_on/models/app_local_data.dart';
import 'package:start_on/storage/local_data_store_support.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalDataStore {
  const LocalDataStore();

  static const _storageKey = 'ad_focus.local_data';

  Future<AppLocalData> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);

    if (raw == null || raw.isEmpty) {
      final initialData = normalizeLocalDataForDate(AppLocalData.initial());
      await prefs.setString(_storageKey, jsonEncode(initialData.toJson()));
      return initialData;
    }

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final normalized = _sanitizeLoadedData(
        normalizeLocalDataForDate(AppLocalData.fromJson(decoded)),
      );
      final normalizedRaw = jsonEncode(normalized.toJson());
      if (normalizedRaw != raw) {
        await prefs.setString(_storageKey, normalizedRaw);
      }
      return normalized;
    } catch (_) {
      final fallback = normalizeLocalDataForDate(AppLocalData.initial());
      await prefs.setString(_storageKey, jsonEncode(fallback.toJson()));
      return fallback;
    }
  }

  Future<void> save(AppLocalData data) async {
    final prefs = await SharedPreferences.getInstance();
    final sanitized = _sanitizeLoadedData(data);
    await prefs.setString(_storageKey, jsonEncode(sanitized.toJson()));
  }

  AppLocalData replaceNotionQuests(
    AppLocalData currentData,
    List<QuestItem> notionQuests,
  ) {
    final existingById = {
      for (final quest in currentData.quests) quest.id: quest,
    };
    final mergedNotionQuests = notionQuests.map((quest) {
      final existing = existingById[quest.id];
      if (existing == null) {
        return quest;
      }

      return quest.copyWith(elapsedSeconds: existing.elapsedSeconds);
    }).toList();
    final manualQuests = currentData.quests
        .where((quest) => !quest.id.startsWith('notion:'))
        .toList();

    return currentData.copyWith(
      quests: [...mergedNotionQuests, ...manualQuests],
    );
  }

  AppLocalData removeNotionQuests(AppLocalData currentData) {
    return currentData.copyWith(
      quests: currentData.quests
          .where((quest) => !quest.id.startsWith('notion:'))
          .toList(),
    );
  }

  AppLocalData completeQuest(
    AppLocalData currentData,
    CompletedQuestRecord record,
  ) {
    final now = DateTime.now();
    final completedAt = DateTime.tryParse(record.completedAt)?.toLocal() ?? now;
    final normalized = normalizeLocalDataForDate(currentData, now: now);
    final sameDay = _isSameDate(completedAt, now);
    final sameWeek = _isSameWeek(completedAt, now);
    final sameMonth = completedAt.year == now.year && completedAt.month == now.month;

    final nextLevelState = applyLocalDataExp(
      level: normalized.level,
      currentExp: normalized.currentExp,
      maxExp: normalized.maxExp,
      gainedExp: record.earnedExp,
    );

    final weeklyCounts = List<int>.from(
      normalized.weeklyActivityCounts.isEmpty
          ? List<int>.filled(7, 0)
          : normalized.weeklyActivityCounts,
    );
    while (weeklyCounts.length < 7) {
      weeklyCounts.add(0);
    }
    final weekdayIndex = completedAt.weekday - 1;
    weeklyCounts[weekdayIndex] += 1;

    final weeklyBars = buildLocalDataWeeklyBars(weeklyCounts);
    final weeklyCompletedCount = normalized.weeklyCompletedCount + 1;
    final weeklyCompletionRate = calculateWeeklyCompletionRate(
      weeklyCompletedCount,
      normalized.weeklyRewardTarget,
    );
    final weeklyRateDelta =
        weeklyCompletionRate - normalized.previousWeeklyCompletionRate;
    final recentActivities = [
      RecentActivity(
        date: formatActivityDate(completedAt),
        subtitle: '${record.title} 완료',
        exp: record.earnedExp,
      ),
      ...normalized.recentActivities,
    ].take(20).toList();
    final completedQuests = [
      record,
      ...normalized.completedQuests,
    ].take(100).toList();

    final categoryStats = applyLocalDataCategoryStats(
      diligenceStat: normalized.diligenceStat,
      orderStat: normalized.orderStat,
      intelligenceStat: normalized.intelligenceStat,
      healthStat: normalized.healthStat,
      category: record.category,
      difficulty: record.difficulty,
    );

    return normalized.copyWith(
      userRole: roleForLevel(nextLevelState.level),
      level: nextLevelState.level,
      currentExp: nextLevelState.currentExp,
      maxExp: nextLevelState.maxExp,
      completedQuestCount: normalized.completedQuestCount + 1,
      earnedExp: normalized.earnedExp + record.earnedExp,
      dailyRewardCount: math.min(
        normalized.dailyRewardTarget,
        normalized.dailyRewardCount + 1,
      ),
      weeklyRewardCount: math.min(
        normalized.weeklyRewardTarget,
        normalized.weeklyRewardCount + 1,
      ),
      monthlyRewardCount: math.min(
        normalized.monthlyRewardTarget,
        normalized.monthlyRewardCount + 1,
      ),
      weeklyCompletedCount: weeklyCompletedCount,
      weeklyCompletionRate: weeklyCompletionRate,
      weeklyRateDelta: weeklyRateDelta,
      diligenceStat: categoryStats.diligenceStat,
      orderStat: categoryStats.orderStat,
      intelligenceStat: categoryStats.intelligenceStat,
      healthStat: categoryStats.healthStat,
      weeklyActivityCounts: weeklyCounts,
      weeklyActivityBars: weeklyBars,
      recentActivities: recentActivities,
      completedQuests: completedQuests,
      quests: normalized.quests
          .where((item) => item.id != record.questId)
          .toList(),
    );
  }

  AppLocalData undoCompleteQuest(
    AppLocalData currentData,
    CompletedQuestRecord record,
  ) {
    final now = DateTime.now();
    final completedAt = DateTime.tryParse(record.completedAt)?.toLocal() ?? now;
    final normalized = normalizeLocalDataForDate(currentData, now: now);
    final sameDay = _isSameDate(completedAt, now);
    final sameWeek = _isSameWeek(completedAt, now);
    final sameMonth = completedAt.year == now.year && completedAt.month == now.month;
    final existingQuestIds = normalized.quests.map((quest) => quest.id).toSet();

    final nextCompletedQuests = List<CompletedQuestRecord>.from(
      normalized.completedQuests,
    );
    final removedIndex = nextCompletedQuests.indexWhere(
      (item) => item.questId == record.questId && item.completedAt == record.completedAt,
    );
    if (removedIndex >= 0) {
      nextCompletedQuests.removeAt(removedIndex);
    } else {
      nextCompletedQuests.removeWhere((item) => item.questId == record.questId);
    }

    final weeklyCounts = List<int>.from(
      normalized.weeklyActivityCounts.isEmpty
          ? List<int>.filled(7, 0)
          : normalized.weeklyActivityCounts,
    );
    while (weeklyCounts.length < 7) {
      weeklyCounts.add(0);
    }
    final weekdayIndex = completedAt.weekday - 1;
    if (sameWeek && weekdayIndex >= 0 && weekdayIndex < weeklyCounts.length) {
      weeklyCounts[weekdayIndex] = math.max(0, weeklyCounts[weekdayIndex] - 1);
    }

    final weeklyCompletedCount = sameWeek
        ? math.max(0, normalized.weeklyCompletedCount - 1)
        : normalized.weeklyCompletedCount;
    final weeklyCompletionRate = calculateWeeklyCompletionRate(
      weeklyCompletedCount,
      normalized.weeklyRewardTarget,
    );
    final expState = removeLocalDataExp(
      level: normalized.level,
      currentExp: normalized.currentExp,
      lostExp: record.earnedExp,
    );
    final categoryStats = subtractLocalDataCategoryStats(
      diligenceStat: normalized.diligenceStat,
      orderStat: normalized.orderStat,
      intelligenceStat: normalized.intelligenceStat,
      healthStat: normalized.healthStat,
      category: record.category,
      difficulty: record.difficulty,
    );

    final restoredQuest = _questFromCompletedRecord(record);
    final restoredQuests = existingQuestIds.contains(restoredQuest.id)
        ? normalized.quests
        : [restoredQuest, ...normalized.quests];

    return normalized.copyWith(
      userRole: roleForLevel(expState.level),
      level: expState.level,
      currentExp: expState.currentExp,
      maxExp: expState.maxExp,
      completedQuestCount: math.max(0, normalized.completedQuestCount - 1),
      earnedExp: math.max(0, normalized.earnedExp - record.earnedExp),
      dailyRewardCount: sameDay
          ? math.max(0, normalized.dailyRewardCount - 1)
          : normalized.dailyRewardCount,
      weeklyRewardCount: sameWeek
          ? math.max(0, normalized.weeklyRewardCount - 1)
          : normalized.weeklyRewardCount,
      monthlyRewardCount: sameMonth
          ? math.max(0, normalized.monthlyRewardCount - 1)
          : normalized.monthlyRewardCount,
      weeklyCompletedCount: weeklyCompletedCount,
      weeklyCompletionRate: weeklyCompletionRate,
      weeklyRateDelta:
          weeklyCompletionRate - normalized.previousWeeklyCompletionRate,
      diligenceStat: categoryStats.diligenceStat,
      orderStat: categoryStats.orderStat,
      intelligenceStat: categoryStats.intelligenceStat,
      healthStat: categoryStats.healthStat,
      weeklyActivityCounts: weeklyCounts,
      weeklyActivityBars: buildLocalDataWeeklyBars(weeklyCounts),
      recentActivities: normalized.recentActivities
          .where((activity) => !_matchesCompletedActivity(activity, record))
          .toList(),
      completedQuests: nextCompletedQuests,
      quests: restoredQuests,
    );
  }

  AppLocalData completeDungeon(
    AppLocalData currentData, {
    required String dungeonId,
    required int creditReward,
  }) {
    final normalized = normalizeLocalDataForDate(currentData);
    if (normalized.clearedDungeonIds.contains(dungeonId)) {
      return normalized;
    }

    return normalized.copyWith(
      credits: normalized.credits + creditReward,
      clearedDungeonIds: [...normalized.clearedDungeonIds, dungeonId],
    );
  }
}

QuestItem _questFromCompletedRecord(CompletedQuestRecord record) {
  final subtasks = record.subtasks
      .map(
        (subtask) => subtask.copyWith(
          completedAt: subtask.isDone ? subtask.completedAt : null,
        ),
      )
      .toList();
  final defaultDurationSeconds = subtasks.isEmpty
      ? defaultQuestDurationSecondsForDifficulty(record.difficulty)
      : subtasks.fold<int>(
          0,
          (total, subtask) => total + subtask.plannedDurationSeconds,
        );

  return QuestItem(
    id: record.questId,
    title: record.title,
    exp: record.earnedExp,
    difficulty: record.difficulty,
    category: record.category,
    elapsedSeconds: record.elapsedSeconds,
    defaultDurationSeconds: defaultDurationSeconds,
    subtasks: subtasks,
    activeSubtaskId: _firstIncompleteSubtaskId(subtasks),
    syncTarget: record.syncTarget,
  );
}

bool _isSameDate(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

bool _isSameWeek(DateTime left, DateTime right) {
  final leftStart = DateTime(left.year, left.month, left.day)
      .subtract(Duration(days: left.weekday - 1));
  final rightStart = DateTime(right.year, right.month, right.day)
      .subtract(Duration(days: right.weekday - 1));
  return _isSameDate(leftStart, rightStart);
}

String? _firstIncompleteSubtaskId(List<QuestSubtask> subtasks) {
  for (final subtask in subtasks) {
    if (!subtask.isDone) {
      return subtask.id;
    }
  }
  return null;
}

bool _matchesCompletedActivity(
  RecentActivity activity,
  CompletedQuestRecord record,
) {
  return activity.subtitle.contains(record.title) && activity.exp == record.earnedExp;
}

AppLocalData _sanitizeLoadedData(AppLocalData data) {
  final completedQuestIds = data.completedQuests
      .map((record) => record.questId.trim())
      .where((id) => id.isNotEmpty)
      .toSet();
  if (completedQuestIds.isEmpty) {
    return data;
  }

  return data.copyWith(
    quests: data.quests
        .where((quest) => !completedQuestIds.contains(quest.id.trim()))
        .toList(),
  );
}
