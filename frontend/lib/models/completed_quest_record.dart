import 'package:start_on/models/quest_api_models.dart';
import 'package:start_on/models/quest_category.dart';
import 'package:start_on/models/quest_item.dart';

class CompletedQuestRecord {
  CompletedQuestRecord({
    required this.questId,
    required this.title,
    required this.difficulty,
    required this.category,
    required this.earnedExp,
    required this.completedAt,
    required this.elapsedSeconds,
    List<QuestSubtask>? subtasks,
    this.proofImagePath,
    this.syncTarget,
  }) : subtasks = List.unmodifiable(subtasks ?? const <QuestSubtask>[]);

  final String questId;
  final String title;
  final String difficulty;
  final String category;
  final int earnedExp;
  final String completedAt;
  final int elapsedSeconds;
  final List<QuestSubtask> subtasks;
  final String? proofImagePath;
  final String? syncTarget;

  CompletedQuestRecord copyWith({
    String? questId,
    String? title,
    String? difficulty,
    String? category,
    int? earnedExp,
    String? completedAt,
    int? elapsedSeconds,
    List<QuestSubtask>? subtasks,
    Object? proofImagePath = _completedQuestNoChange,
    Object? syncTarget = _completedQuestNoChange,
  }) {
    return CompletedQuestRecord(
      questId: questId ?? this.questId,
      title: title ?? this.title,
      difficulty: difficulty ?? this.difficulty,
      category: category ?? this.category,
      earnedExp: earnedExp ?? this.earnedExp,
      completedAt: completedAt ?? this.completedAt,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      subtasks: subtasks ?? this.subtasks,
      proofImagePath: identical(proofImagePath, _completedQuestNoChange)
          ? this.proofImagePath
          : proofImagePath as String?,
      syncTarget: identical(syncTarget, _completedQuestNoChange)
          ? this.syncTarget
          : syncTarget as String?,
    );
  }

  factory CompletedQuestRecord.fromApiResponse(
    CompletedQuestRecordResponse response,
  ) {
    return CompletedQuestRecord(
      questId: response.questId,
      title: response.title,
      difficulty: questDifficultyFromApi(response.difficulty),
      category: normalizeQuestCategory(response.category),
      earnedExp: response.earnedExp,
      completedAt: response.completedAt,
      elapsedSeconds: response.elapsedSeconds,
      subtasks: const <QuestSubtask>[],
      proofImagePath: response.proofImagePath,
      syncTarget: null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'questId': questId,
      'title': title,
      'difficulty': difficulty,
      'category': category,
      'earnedExp': earnedExp,
      'completedAt': completedAt,
      'elapsedSeconds': elapsedSeconds,
      'subtasks': subtasks.map((subtask) => subtask.toJson()).toList(),
      'proofImagePath': proofImagePath,
      'syncTarget': syncTarget,
    };
  }

  factory CompletedQuestRecord.fromJson(Map<String, dynamic> json) {
    return CompletedQuestRecord(
      questId:
          (json['questId'] as String?) ??
          (json['quest_id'] as String?) ??
          (json['task_id'] as String?) ??
          '',
      title: json['title'] as String? ?? '',
      difficulty: normalizeQuestDifficulty(json['difficulty'] as String?),
      category: normalizeQuestCategory(json['category'] as String?),
      earnedExp:
          _readJsonInt(json['earnedExp']) ??
          _readJsonInt(json['earned_exp']) ??
          0,
      completedAt:
          (json['completedAt'] as String?) ??
          (json['completed_at'] as String?) ??
          '',
      elapsedSeconds:
          _readJsonInt(json['elapsedSeconds']) ??
          _readJsonInt(json['elapsed_seconds']) ??
          0,
      subtasks: _completedRecordSubtasksFromJson(json['subtasks']),
      proofImagePath:
          (json['proofImagePath'] as String?) ??
          (json['proof_image_path'] as String?),
      syncTarget:
          (json['syncTarget'] as String?) ?? (json['sync_target'] as String?),
    );
  }
}

const _completedQuestNoChange = Object();

int? _readJsonInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

List<QuestSubtask> _completedRecordSubtasksFromJson(Object? value) {
  if (value is! List) {
    return const <QuestSubtask>[];
  }

  return value
      .whereType<Map>()
      .map((item) => QuestSubtask.fromJson(Map<String, dynamic>.from(item)))
      .toList();
}
