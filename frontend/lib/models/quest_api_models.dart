class QuestItemResponse {
  const QuestItemResponse({
    required this.id,
    required this.title,
    required this.exp,
    required this.difficulty,
    required this.category,
    required this.elapsedSeconds,
    required this.defaultDurationSeconds,
    this.dueAt,
  });

  factory QuestItemResponse.fromJson(Object? json) {
    final object = _asJsonObject(json, 'Quest item must be a JSON object.');

    return QuestItemResponse(
      id: _readRequiredString(object, 'id'),
      title: _readRequiredString(object, 'title'),
      exp: _readInt(object, 'exp'),
      difficulty: _readRequiredString(object, 'difficulty'),
      category: _readRequiredString(object, 'category'),
      elapsedSeconds: _readInt(object, 'elapsedSeconds'),
      defaultDurationSeconds: _readInt(object, 'defaultDurationSeconds'),
      dueAt: _readOptionalDateTime(object, 'due_at'),
    );
  }

  final String id;
  final String title;
  final int exp;
  final String difficulty;
  final String category;
  final int elapsedSeconds;
  final int defaultDurationSeconds;
  final DateTime? dueAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'exp': exp,
      'difficulty': difficulty,
      'category': category,
      'elapsedSeconds': elapsedSeconds,
      'defaultDurationSeconds': defaultDurationSeconds,
      'due_at': dueAt?.toIso8601String(),
    };
  }
}

class QuestCreateRequest {
  const QuestCreateRequest({
    required this.title,
    required this.exp,
    required this.difficulty,
    required this.category,
    required this.defaultDurationSeconds,
    this.dueAt,
  });

  final String title;
  final int exp;
  final String difficulty;
  final String category;
  final int defaultDurationSeconds;
  final DateTime? dueAt;

  Map<String, dynamic> toJson() {
    return {
      'title': title.trim(),
      'exp': exp,
      'difficulty': difficulty,
      'category': category,
      'defaultDurationSeconds': defaultDurationSeconds,
      'due_at': dueAt?.toIso8601String(),
    };
  }
}

class QuestUpdateRequest {
  const QuestUpdateRequest({
    required this.title,
    required this.exp,
    required this.difficulty,
    required this.category,
    required this.elapsedSeconds,
    required this.defaultDurationSeconds,
    this.dueAt,
  });

  final String title;
  final int exp;
  final String difficulty;
  final String category;
  final int elapsedSeconds;
  final int defaultDurationSeconds;
  final DateTime? dueAt;

  Map<String, dynamic> toJson() {
    return {
      'title': title.trim(),
      'exp': exp,
      'difficulty': difficulty,
      'category': category,
      'elapsedSeconds': elapsedSeconds,
      'defaultDurationSeconds': defaultDurationSeconds,
      'due_at': dueAt?.toIso8601String(),
    };
  }
}

class QuestCompleteRequest {
  const QuestCompleteRequest({
    required this.elapsedSeconds,
    this.proofImagePath,
  });

  final int elapsedSeconds;
  final String? proofImagePath;

  Map<String, dynamic> toJson() {
    return {'elapsedSeconds': elapsedSeconds, 'proofImagePath': proofImagePath};
  }
}

class CompletedQuestRecordResponse {
  const CompletedQuestRecordResponse({
    required this.questId,
    required this.title,
    required this.difficulty,
    required this.category,
    required this.earnedExp,
    required this.completedAt,
    required this.elapsedSeconds,
    required this.proofImagePath,
  });

  factory CompletedQuestRecordResponse.fromJson(Object? json) {
    final object = _asJsonObject(
      json,
      'Completed quest record must be a JSON object.',
    );

    return CompletedQuestRecordResponse(
      questId: _readRequiredString(object, 'questId'),
      title: _readRequiredString(object, 'title'),
      difficulty: _readRequiredString(object, 'difficulty'),
      category: _readRequiredString(object, 'category'),
      earnedExp: _readInt(object, 'earnedExp'),
      completedAt: _readRequiredString(object, 'completedAt'),
      elapsedSeconds: _readInt(object, 'elapsedSeconds'),
      proofImagePath: _readOptionalString(object, 'proofImagePath'),
    );
  }

  final String questId;
  final String title;
  final String difficulty;
  final String category;
  final int earnedExp;
  final String completedAt;
  final int elapsedSeconds;
  final String? proofImagePath;

  Map<String, dynamic> toJson() {
    return {
      'questId': questId,
      'title': title,
      'difficulty': difficulty,
      'category': category,
      'earnedExp': earnedExp,
      'completedAt': completedAt,
      'elapsedSeconds': elapsedSeconds,
      'proofImagePath': proofImagePath,
    };
  }
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

String _readRequiredString(Map<String, dynamic> json, String key) {
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

DateTime? _readOptionalDateTime(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('$key must be an ISO date-time string or null.');
  }
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final parsed = DateTime.tryParse(trimmed);
  if (parsed == null) {
    throw FormatException('$key must be an ISO date-time string or null.');
  }
  return parsed;
}
