class LeaderboardResponse {
  const LeaderboardResponse({
    required this.entries,
    required this.currentUserRank,
  });

  factory LeaderboardResponse.fromJson(Object? json) {
    final object = _asJsonObject(
      json,
      'Leaderboard response must be a JSON object.',
    );

    return LeaderboardResponse(
      entries: ((object['entries'] as List<dynamic>?) ?? const [])
          .map(LeaderboardEntryResponse.fromJson)
          .toList(),
      currentUserRank: _readInt(object, 'currentUserRank'),
    );
  }

  final List<LeaderboardEntryResponse> entries;
  final int currentUserRank;
}

class LeaderboardEntryResponse {
  const LeaderboardEntryResponse({
    required this.rank,
    required this.userId,
    required this.userName,
    required this.userRole,
    required this.level,
    required this.score,
    required this.earnedExp,
    required this.credits,
    required this.completedQuestCount,
    required this.weeklyCompletedCount,
    required this.weeklyCompletionRate,
    required this.clearedDungeonCount,
    required this.isCurrentUser,
  });

  factory LeaderboardEntryResponse.fromJson(Object? json) {
    final object = _asJsonObject(
      json,
      'Leaderboard entry must be a JSON object.',
    );

    return LeaderboardEntryResponse(
      rank: _readInt(object, 'rank'),
      userId: _readString(object, 'userId'),
      userName: _readString(object, 'userName'),
      userRole: _readString(object, 'userRole'),
      level: _readInt(object, 'level'),
      score: _readInt(object, 'score'),
      earnedExp: _readInt(object, 'earnedExp'),
      credits: _readInt(object, 'credits'),
      completedQuestCount: _readInt(object, 'completedQuestCount'),
      weeklyCompletedCount: _readInt(object, 'weeklyCompletedCount'),
      weeklyCompletionRate: _readInt(object, 'weeklyCompletionRate'),
      clearedDungeonCount: _readInt(object, 'clearedDungeonCount'),
      isCurrentUser: _readBool(object, 'isCurrentUser'),
    );
  }

  final int rank;
  final String userId;
  final String userName;
  final String userRole;
  final int level;
  final int score;
  final int earnedExp;
  final int credits;
  final int completedQuestCount;
  final int weeklyCompletedCount;
  final int weeklyCompletionRate;
  final int clearedDungeonCount;
  final bool isCurrentUser;
}

Map<String, dynamic> _asJsonObject(Object? value, String message) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map<String, dynamic>(
      (key, value) => MapEntry(key.toString(), value),
    );
  }
  throw FormatException(message);
}

String _readString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw FormatException('$key must be a non-empty string.');
}

int _readInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  throw FormatException('$key must be a number.');
}

bool _readBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is bool) {
    return value;
  }
  throw FormatException('$key must be a boolean.');
}
