class DungeonStatusResponse {
  const DungeonStatusResponse({
    required this.dungeonId,
    required this.title,
    required this.difficulty,
    required this.completed,
    required this.cleared,
    required this.canClaim,
    required this.creditReward,
    required this.clearedAt,
  });

  factory DungeonStatusResponse.fromJson(Object? json) {
    final object = _asJsonObject(json, 'Dungeon status must be a JSON object.');

    return DungeonStatusResponse(
      dungeonId: _readString(object, 'dungeonId'),
      title: _readString(object, 'title'),
      difficulty: _readString(object, 'difficulty'),
      completed: _readBool(object, 'completed'),
      cleared: _readBool(object, 'cleared'),
      canClaim: _readBool(object, 'canClaim'),
      creditReward: _readInt(object, 'creditReward'),
      clearedAt: _readOptionalString(object, 'clearedAt'),
    );
  }

  final String dungeonId;
  final String title;
  final String difficulty;
  final bool completed;
  final bool cleared;
  final bool canClaim;
  final int creditReward;
  final String? clearedAt;
}

class DungeonListResponse {
  const DungeonListResponse({required this.dungeons});

  factory DungeonListResponse.fromJson(Object? json) {
    final object = _asJsonObject(json, 'Dungeon list must be a JSON object.');
    final rawDungeons = object['dungeons'];
    if (rawDungeons is! List) {
      throw const FormatException('dungeons must be a JSON array.');
    }

    return DungeonListResponse(
      dungeons: rawDungeons.map(DungeonStatusResponse.fromJson).toList(),
    );
  }

  final List<DungeonStatusResponse> dungeons;
}

class DungeonClearResponse {
  const DungeonClearResponse({
    required this.dungeonId,
    required this.cleared,
    required this.credits,
    required this.clearedAt,
  });

  factory DungeonClearResponse.fromJson(Object? json) {
    final object = _asJsonObject(
      json,
      'Dungeon clear result must be a JSON object.',
    );

    return DungeonClearResponse(
      dungeonId: _readString(object, 'dungeonId'),
      cleared: _readBool(object, 'cleared'),
      credits: _readInt(object, 'credits'),
      clearedAt: _readString(object, 'clearedAt'),
    );
  }

  final String dungeonId;
  final bool cleared;
  final int credits;
  final String clearedAt;
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

String? _readOptionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : value;
  }
  throw FormatException('$key must be a string or null.');
}

bool _readBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is bool) {
    return value;
  }
  throw FormatException('$key must be a boolean.');
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
