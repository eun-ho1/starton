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
    final completedAt =
        DateTime.tryParse(record.completedAt)?.toLocal() ?? DateTime.now();
    final normalized = normalizeLocalDataForDate(currentData, now: completedAt);

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
