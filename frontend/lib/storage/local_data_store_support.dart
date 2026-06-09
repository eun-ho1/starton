import 'dart:math' as math;

import 'package:start_on/models/app_local_data.dart';

AppLocalData normalizeLocalDataForDate(AppLocalData data, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final todayKey = localDataDateKey(current);
  final weekKey = localDataWeekKey(current);
  final monthKey = localDataMonthKey(current);

  var normalized = data;

  final counts = List<int>.from(
    normalized.weeklyActivityCounts.isEmpty
        ? localDataActivityCountsFromBars(normalized.weeklyActivityBars)
        : normalized.weeklyActivityCounts,
  );
  while (counts.length < 7) {
    counts.add(0);
  }
  if (counts.length > 7) {
    counts.removeRange(7, counts.length);
  }

  if (normalized.dailyResetKey != todayKey) {
    normalized = normalized.copyWith(
      dailyRewardCount: 0,
      dailyResetKey: todayKey,
    );
  }

  if (normalized.weeklyResetKey != weekKey) {
    normalized = normalized.copyWith(
      weeklyRewardCount: 0,
      weeklyCompletedCount: 0,
      previousWeeklyCompletionRate: normalized.weeklyCompletionRate,
      weeklyCompletionRate: 0,
      weeklyRateDelta: 0,
      weeklyActivityCounts: List<int>.filled(7, 0),
      weeklyActivityBars: List<double>.filled(7, 0),
      weeklyResetKey: weekKey,
    );
  } else {
    normalized = normalized.copyWith(
      weeklyActivityCounts: counts,
      weeklyActivityBars: buildLocalDataWeeklyBars(counts),
      weeklyResetKey: weekKey,
    );
  }

  if (normalized.monthlyResetKey != monthKey) {
    normalized = normalized.copyWith(
      monthlyRewardCount: 0,
      monthlyResetKey: monthKey,
    );
  }

  if (normalized.userRole != roleForLevel(normalized.level)) {
    normalized = normalized.copyWith(userRole: roleForLevel(normalized.level));
  }

  return normalized.copyWith(
    dailyResetKey: normalized.dailyResetKey.isEmpty
        ? todayKey
        : normalized.dailyResetKey,
    weeklyResetKey: normalized.weeklyResetKey.isEmpty
        ? weekKey
        : normalized.weeklyResetKey,
    monthlyResetKey: normalized.monthlyResetKey.isEmpty
        ? monthKey
        : normalized.monthlyResetKey,
  );
}

LocalDataLevelState applyLocalDataExp({
  required int level,
  required int currentExp,
  required int maxExp,
  required int gainedExp,
}) {
  var nextLevel = level;
  var nextCurrentExp = currentExp + gainedExp;
  var nextMaxExp = maxExp;

  while (nextCurrentExp >= nextMaxExp && nextMaxExp > 0) {
    nextCurrentExp -= nextMaxExp;
    nextLevel += 1;
    nextMaxExp = requiredExpForLevel(nextLevel);
  }

  return LocalDataLevelState(
    level: nextLevel,
    currentExp: nextCurrentExp,
    maxExp: nextMaxExp,
  );
}

LocalDataLevelState removeLocalDataExp({
  required int level,
  required int currentExp,
  required int lostExp,
}) {
  var nextLevel = math.max(0, level);
  var nextCurrentExp = math.max(0, currentExp);
  var remainingLoss = math.max(0, lostExp);

  while (remainingLoss > nextCurrentExp && nextLevel > 0) {
    remainingLoss -= nextCurrentExp;
    nextLevel -= 1;
    nextCurrentExp = requiredExpForLevel(nextLevel);
  }

  nextCurrentExp = math.max(0, nextCurrentExp - remainingLoss);
  return LocalDataLevelState(
    level: nextLevel,
    currentExp: nextCurrentExp,
    maxExp: requiredExpForLevel(nextLevel),
  );
}

LocalDataCategoryStats applyLocalDataCategoryStats({
  required int diligenceStat,
  required int orderStat,
  required int intelligenceStat,
  required int healthStat,
  required String category,
  required String difficulty,
}) {
  final diligenceGain = switch (difficulty) {
    '쉬움' => 4,
    '보통' => 6,
    _ => 9,
  };
  final categoryGain = switch (difficulty) {
    '쉬움' => 5,
    '보통' => 8,
    _ => 12,
  };
  final normalizedCategory = normalizeQuestCategory(category);

  return LocalDataCategoryStats(
    diligenceStat: math.min(
      100,
      diligenceStat +
          diligenceGain +
          (normalizedCategory == 'work' ? categoryGain : 0),
    ),
    orderStat: normalizedCategory == 'home'
        ? math.min(100, orderStat + categoryGain)
        : orderStat,
    intelligenceStat: normalizedCategory == 'study'
        ? math.min(100, intelligenceStat + categoryGain)
        : intelligenceStat,
    healthStat: normalizedCategory == 'life'
        ? math.min(100, healthStat + categoryGain)
        : healthStat,
  );
}

LocalDataCategoryStats subtractLocalDataCategoryStats({
  required int diligenceStat,
  required int orderStat,
  required int intelligenceStat,
  required int healthStat,
  required String category,
  required String difficulty,
}) {
  final diligenceGain = switch (difficulty) {
    '쉬움' => 4,
    '보통' => 6,
    _ => 9,
  };
  final categoryGain = switch (difficulty) {
    '쉬움' => 5,
    '보통' => 8,
    _ => 12,
  };
  final normalizedCategory = normalizeQuestCategory(category);

  return LocalDataCategoryStats(
    diligenceStat: math.max(
      0,
      diligenceStat - diligenceGain - (normalizedCategory == 'work' ? categoryGain : 0),
    ),
    orderStat: normalizedCategory == 'home'
        ? math.max(0, orderStat - categoryGain)
        : orderStat,
    intelligenceStat: normalizedCategory == 'study'
        ? math.max(0, intelligenceStat - categoryGain)
        : intelligenceStat,
    healthStat: normalizedCategory == 'life'
        ? math.max(0, healthStat - categoryGain)
        : healthStat,
  );
}

List<int> localDataActivityCountsFromBars(List<double> bars) {
  final source = bars.isEmpty ? List<double>.filled(7, 0) : bars;
  return List<int>.generate(
    7,
    (index) => index < source.length ? (source[index] * 5).round() : 0,
  );
}

List<double> buildLocalDataWeeklyBars(List<int> counts) {
  final cappedCounts = counts.take(7).toList();
  final maxCount = cappedCounts.fold<int>(0, math.max);
  if (maxCount <= 0) {
    return List<double>.filled(7, 0);
  }

  return cappedCounts.map((count) => count / maxCount).toList();
}

int calculateWeeklyCompletionRate(int completedCount, int weeklyTarget) {
  if (weeklyTarget <= 0) {
    return 0;
  }

  return math.min(100, ((completedCount / weeklyTarget) * 100).round());
}

int requiredExpForLevel(int level) {
  return 500 + (level * 100);
}

String roleForLevel(int level) {
  if (level >= 8) {
    return '마스터';
  }
  if (level >= 5) {
    return '숙련가';
  }
  if (level >= 2) {
    return '모험가';
  }
  return '초보자';
}

String formatActivityDate(DateTime dateTime) {
  return '${dateTime.year}.${localDataTwoDigits(dateTime.month)}.${localDataTwoDigits(dateTime.day)} '
      '${localDataTwoDigits(dateTime.hour)}:${localDataTwoDigits(dateTime.minute)}';
}

String localDataDateKey(DateTime dateTime) {
  return '${dateTime.year}-${localDataTwoDigits(dateTime.month)}-${localDataTwoDigits(dateTime.day)}';
}

String localDataMonthKey(DateTime dateTime) {
  return '${dateTime.year}-${localDataTwoDigits(dateTime.month)}';
}

String localDataWeekKey(DateTime dateTime) {
  final startOfWeek = DateTime(
    dateTime.year,
    dateTime.month,
    dateTime.day,
  ).subtract(Duration(days: dateTime.weekday - 1));
  return localDataDateKey(startOfWeek);
}

String localDataTwoDigits(int value) => value.toString().padLeft(2, '0');

class LocalDataLevelState {
  const LocalDataLevelState({
    required this.level,
    required this.currentExp,
    required this.maxExp,
  });

  final int level;
  final int currentExp;
  final int maxExp;
}

class LocalDataCategoryStats {
  const LocalDataCategoryStats({
    required this.diligenceStat,
    required this.orderStat,
    required this.intelligenceStat,
    required this.healthStat,
  });

  final int diligenceStat;
  final int orderStat;
  final int intelligenceStat;
  final int healthStat;
}
