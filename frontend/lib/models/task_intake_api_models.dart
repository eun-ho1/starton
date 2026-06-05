class TaskIntakeUserContext {
  const TaskIntakeUserContext({
    this.energyNow,
    this.availableMinutesToday,
    this.extra = const <String, dynamic>{},
  });

  factory TaskIntakeUserContext.fromJson(Object? json) {
    final object = _asJsonObject(
      json,
      'Task intake user context must be a JSON object.',
    );
    return TaskIntakeUserContext(
      energyNow: _readOptionalString(object, 'energy_now'),
      availableMinutesToday: _readOptionalInt(
        object,
        'available_minutes_today',
      ),
      extra: _readMap(object, 'extra'),
    );
  }

  final String? energyNow;
  final int? availableMinutesToday;
  final Map<String, dynamic> extra;

  Map<String, dynamic> toJson() {
    return {
      'energy_now': energyNow,
      'available_minutes_today': availableMinutesToday,
      'extra': Map<String, dynamic>.from(extra),
    };
  }
}

class TaskIntakeRequest {
  const TaskIntakeRequest({
    required this.text,
    this.source = 'manual',
    this.clientTimezone = 'Asia/Seoul',
    this.userContext = const TaskIntakeUserContext(),
    this.clientMetadata = const <String, dynamic>{},
  });

  final String text;
  final String source;
  final String clientTimezone;
  final TaskIntakeUserContext userContext;
  final Map<String, dynamic> clientMetadata;

  Map<String, dynamic> toJson() {
    return {
      'text': text.trim(),
      'source': source,
      'client_timezone': clientTimezone,
      'user_context': userContext.toJson(),
      'client_metadata': Map<String, dynamic>.from(clientMetadata),
    };
  }
}

class TaskIntakeResponse {
  const TaskIntakeResponse({
    required this.rawInputId,
    required this.candidateId,
    required this.status,
    required this.candidate,
  });

  factory TaskIntakeResponse.fromJson(Object? json) {
    final object = _asJsonObject(
      json,
      'Task intake response must be a JSON object.',
    );
    return TaskIntakeResponse(
      rawInputId: _readRequiredString(object, 'raw_input_id'),
      candidateId: _readOptionalString(object, 'candidate_id'),
      status: _readRequiredString(object, 'status'),
      candidate: object['candidate'] == null
          ? null
          : TaskCandidateResponse.fromJson(object['candidate']),
    );
  }

  final String rawInputId;
  final String? candidateId;
  final String status;
  final TaskCandidateResponse? candidate;

  Map<String, dynamic> toJson() {
    return {
      'raw_input_id': rawInputId,
      'candidate_id': candidateId,
      'status': status,
      'candidate': candidate?.toJson(),
    };
  }
}

class TaskCandidateResponse {
  const TaskCandidateResponse({
    required this.id,
    required this.userId,
    required this.rawInputId,
    required this.mediatorRunId,
    required this.title,
    required this.description,
    required this.dueAt,
    required this.priority,
    required this.estimatedMinutes,
    required this.energyRequired,
    required this.difficulty,
    required this.nextAction,
    required this.recommendedToday,
    required this.todayReason,
    required this.overloadWarning,
    required this.confidence,
    required this.status,
    required this.modelPayload,
    required this.subtasks,
    required this.reminders,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TaskCandidateResponse.fromJson(Object? json) {
    final object = _asJsonObject(
      json,
      'Task candidate response must be a JSON object.',
    );
    return TaskCandidateResponse(
      id: _readRequiredString(object, 'id'),
      userId: _readRequiredString(object, 'user_id'),
      rawInputId: _readRequiredString(object, 'raw_input_id'),
      mediatorRunId: _readOptionalString(object, 'mediator_run_id'),
      title: _readRequiredString(object, 'title'),
      description: _readOptionalString(object, 'description'),
      dueAt: _readOptionalDateTime(object, 'due_at'),
      priority: _readOptionalString(object, 'priority'),
      estimatedMinutes: _readOptionalInt(object, 'estimated_minutes'),
      energyRequired: _readOptionalString(object, 'energy_required'),
      difficulty: _readOptionalString(object, 'difficulty'),
      nextAction: _readOptionalString(object, 'next_action'),
      recommendedToday: _readBool(
        object,
        'recommended_today',
        defaultValue: false,
      ),
      todayReason: _readOptionalString(object, 'today_reason'),
      overloadWarning: _readOptionalString(object, 'overload_warning'),
      confidence: _readOptionalDouble(object, 'confidence'),
      status: _readOptionalString(object, 'status') ?? 'draft',
      modelPayload: _readMap(object, 'model_payload'),
      subtasks: _readList(
        object,
        'subtasks',
        CandidateSubtaskResponse.fromJson,
      ),
      reminders: _readList(
        object,
        'reminders',
        CandidateReminderResponse.fromJson,
      ),
      createdAt: _readOptionalDateTime(object, 'created_at'),
      updatedAt: _readOptionalDateTime(object, 'updated_at'),
    );
  }

  final String id;
  final String userId;
  final String rawInputId;
  final String? mediatorRunId;
  final String title;
  final String? description;
  final DateTime? dueAt;
  final String? priority;
  final int? estimatedMinutes;
  final String? energyRequired;
  final String? difficulty;
  final String? nextAction;
  final bool recommendedToday;
  final String? todayReason;
  final String? overloadWarning;
  final double? confidence;
  final String status;
  final Map<String, dynamic> modelPayload;
  final List<CandidateSubtaskResponse> subtasks;
  final List<CandidateReminderResponse> reminders;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'raw_input_id': rawInputId,
      'mediator_run_id': mediatorRunId,
      'title': title,
      'description': description,
      'due_at': dueAt?.toIso8601String(),
      'priority': priority,
      'estimated_minutes': estimatedMinutes,
      'energy_required': energyRequired,
      'difficulty': difficulty,
      'next_action': nextAction,
      'recommended_today': recommendedToday,
      'today_reason': todayReason,
      'overload_warning': overloadWarning,
      'confidence': confidence,
      'status': status,
      'model_payload': Map<String, dynamic>.from(modelPayload),
      'subtasks': subtasks.map((subtask) => subtask.toJson()).toList(),
      'reminders': reminders.map((reminder) => reminder.toJson()).toList(),
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}

class CandidateSubtaskResponse {
  const CandidateSubtaskResponse({
    required this.id,
    required this.candidateId,
    required this.title,
    required this.orderIndex,
    required this.estimatedMinutes,
    required this.isNextAction,
    required this.energyRequired,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CandidateSubtaskResponse.fromJson(Object? json) {
    final object = _asJsonObject(
      json,
      'Candidate subtask response must be a JSON object.',
    );
    return CandidateSubtaskResponse(
      id: _readRequiredString(object, 'id'),
      candidateId: _readRequiredString(object, 'candidate_id'),
      title: _readRequiredString(object, 'title'),
      orderIndex: _readInt(object, 'order_index'),
      estimatedMinutes: _readOptionalInt(object, 'estimated_minutes'),
      isNextAction: _readBool(object, 'is_next_action', defaultValue: false),
      energyRequired: _readOptionalString(object, 'energy_required'),
      createdAt: _readOptionalDateTime(object, 'created_at'),
      updatedAt: _readOptionalDateTime(object, 'updated_at'),
    );
  }

  final String id;
  final String candidateId;
  final String title;
  final int orderIndex;
  final int? estimatedMinutes;
  final bool isNextAction;
  final String? energyRequired;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'candidate_id': candidateId,
      'title': title,
      'order_index': orderIndex,
      'estimated_minutes': estimatedMinutes,
      'is_next_action': isNextAction,
      'energy_required': energyRequired,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}

class CandidateReminderResponse {
  const CandidateReminderResponse({
    required this.id,
    required this.candidateId,
    required this.remindAt,
    required this.message,
    required this.type,
    required this.escalationLevel,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CandidateReminderResponse.fromJson(Object? json) {
    final object = _asJsonObject(
      json,
      'Candidate reminder response must be a JSON object.',
    );
    return CandidateReminderResponse(
      id: _readRequiredString(object, 'id'),
      candidateId: _readRequiredString(object, 'candidate_id'),
      remindAt: _readOptionalDateTime(object, 'remind_at'),
      message: _readRequiredString(object, 'message'),
      type: _readOptionalString(object, 'type') ?? 'start',
      escalationLevel: _readOptionalInt(object, 'escalation_level') ?? 0,
      createdAt: _readOptionalDateTime(object, 'created_at'),
      updatedAt: _readOptionalDateTime(object, 'updated_at'),
    );
  }

  final String id;
  final String candidateId;
  final DateTime? remindAt;
  final String message;
  final String type;
  final int escalationLevel;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'candidate_id': candidateId,
      'remind_at': remindAt?.toIso8601String(),
      'message': message,
      'type': type,
      'escalation_level': escalationLevel,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}

class TaskConfirmRequest {
  const TaskConfirmRequest({
    this.accepted = true,
    this.editedFields = const <String, dynamic>{},
    this.selectedSubtaskIds,
    this.selectedReminderIds,
  });

  final bool accepted;
  final Map<String, dynamic> editedFields;
  final List<String>? selectedSubtaskIds;
  final List<String>? selectedReminderIds;

  Map<String, dynamic> toJson() {
    return {
      'accepted': accepted,
      'edited_fields': Map<String, dynamic>.from(editedFields),
      'selected_subtask_ids': selectedSubtaskIds,
      'selected_reminder_ids': selectedReminderIds,
    };
  }
}

class TaskCandidateReviseRequest {
  const TaskCandidateReviseRequest({
    this.revisionType = 'manual_edit',
    this.editedFields = const <String, dynamic>{},
    this.note,
  });

  final String revisionType;
  final Map<String, dynamic> editedFields;
  final String? note;

  Map<String, dynamic> toJson() {
    return {
      'revision_type': revisionType,
      'edited_fields': Map<String, dynamic>.from(editedFields),
      'note': note,
    };
  }
}

class TaskCandidateRejectRequest {
  const TaskCandidateRejectRequest({this.reason});

  final String? reason;

  Map<String, dynamic> toJson() {
    return {'reason': reason};
  }
}

class TaskCommitResultResponse {
  const TaskCommitResultResponse({
    required this.candidateId,
    required this.task,
  });

  factory TaskCommitResultResponse.fromJson(Object? json) {
    final object = _asJsonObject(
      json,
      'Task commit result response must be a JSON object.',
    );
    return TaskCommitResultResponse(
      candidateId: _readRequiredString(object, 'candidate_id'),
      task: TaskResponse.fromJson(object['task']),
    );
  }

  final String candidateId;
  final TaskResponse task;

  Map<String, dynamic> toJson() {
    return {'candidate_id': candidateId, 'task': task.toJson()};
  }
}

class TaskResponse {
  const TaskResponse({
    required this.id,
    required this.userId,
    required this.candidateId,
    required this.rawInputId,
    required this.mediatorRunId,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    required this.dueAt,
    required this.estimatedMinutes,
    required this.energyRequired,
    required this.difficulty,
    required this.nextAction,
    required this.source,
    this.elapsedSeconds,
    required this.metadata,
    required this.subtasks,
    required this.reminders,
    required this.createdAt,
    required this.updatedAt,
    required this.completedAt,
  });

  factory TaskResponse.fromJson(Object? json) {
    final object = _asJsonObject(json, 'Task response must be a JSON object.');
    return TaskResponse(
      id: _readRequiredString(object, 'id'),
      userId: _readRequiredString(object, 'user_id'),
      candidateId: _readOptionalString(object, 'candidate_id'),
      rawInputId: _readOptionalString(object, 'raw_input_id'),
      mediatorRunId: _readOptionalString(object, 'mediator_run_id'),
      title: _readRequiredString(object, 'title'),
      description: _readOptionalString(object, 'description'),
      status: _readOptionalString(object, 'status') ?? 'todo',
      priority: _readOptionalString(object, 'priority'),
      dueAt: _readOptionalDateTime(object, 'due_at'),
      estimatedMinutes: _readOptionalInt(object, 'estimated_minutes'),
      energyRequired: _readOptionalString(object, 'energy_required'),
      difficulty: _readOptionalString(object, 'difficulty'),
      nextAction: _readOptionalString(object, 'next_action'),
      source: _readOptionalString(object, 'source') ?? 'ai',
      elapsedSeconds:
          _readOptionalInt(object, 'elapsed_seconds') ??
          _readOptionalInt(object, 'elapsedSeconds'),
      metadata: _readMap(object, 'metadata'),
      subtasks: _readList(object, 'subtasks', SubtaskResponse.fromJson),
      reminders: _readList(object, 'reminders', ReminderResponse.fromJson),
      createdAt: _readOptionalDateTime(object, 'created_at'),
      updatedAt: _readOptionalDateTime(object, 'updated_at'),
      completedAt: _readOptionalDateTime(object, 'completed_at'),
    );
  }

  final String id;
  final String userId;
  final String? candidateId;
  final String? rawInputId;
  final String? mediatorRunId;
  final String title;
  final String? description;
  final String status;
  final String? priority;
  final DateTime? dueAt;
  final int? estimatedMinutes;
  final String? energyRequired;
  final String? difficulty;
  final String? nextAction;
  final String source;
  final int? elapsedSeconds;
  final Map<String, dynamic> metadata;
  final List<SubtaskResponse> subtasks;
  final List<ReminderResponse> reminders;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;

  bool get isCompleted =>
      status.trim().toLowerCase() == 'done' || completedAt != null;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'candidate_id': candidateId,
      'raw_input_id': rawInputId,
      'mediator_run_id': mediatorRunId,
      'title': title,
      'description': description,
      'status': status,
      'priority': priority,
      'due_at': dueAt?.toIso8601String(),
      'estimated_minutes': estimatedMinutes,
      'energy_required': energyRequired,
      'difficulty': difficulty,
      'next_action': nextAction,
      'source': source,
      'elapsed_seconds': elapsedSeconds,
      'metadata': Map<String, dynamic>.from(metadata),
      'subtasks': subtasks.map((subtask) => subtask.toJson()).toList(),
      'reminders': reminders.map((reminder) => reminder.toJson()).toList(),
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
    };
  }
}

class SubtaskResponse {
  const SubtaskResponse({
    required this.id,
    required this.taskId,
    required this.userId,
    required this.candidateSubtaskId,
    required this.title,
    required this.orderIndex,
    required this.estimatedMinutes,
    required this.status,
    required this.isNextAction,
    required this.energyRequired,
    required this.createdAt,
    required this.updatedAt,
    required this.completedAt,
  });

  factory SubtaskResponse.fromJson(Object? json) {
    final object = _asJsonObject(
      json,
      'Subtask response must be a JSON object.',
    );
    return SubtaskResponse(
      id: _readRequiredString(object, 'id'),
      taskId: _readRequiredString(object, 'task_id'),
      userId: _readRequiredString(object, 'user_id'),
      candidateSubtaskId: _readOptionalString(object, 'candidate_subtask_id'),
      title: _readRequiredString(object, 'title'),
      orderIndex: _readInt(object, 'order_index'),
      estimatedMinutes: _readOptionalInt(object, 'estimated_minutes'),
      status: _readOptionalString(object, 'status') ?? 'todo',
      isNextAction: _readBool(object, 'is_next_action', defaultValue: false),
      energyRequired: _readOptionalString(object, 'energy_required'),
      createdAt: _readOptionalDateTime(object, 'created_at'),
      updatedAt: _readOptionalDateTime(object, 'updated_at'),
      completedAt: _readOptionalDateTime(object, 'completed_at'),
    );
  }

  final String id;
  final String taskId;
  final String userId;
  final String? candidateSubtaskId;
  final String title;
  final int orderIndex;
  final int? estimatedMinutes;
  final String status;
  final bool isNextAction;
  final String? energyRequired;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;

  bool get isCompleted =>
      status.trim().toLowerCase() == 'done' || completedAt != null;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'task_id': taskId,
      'user_id': userId,
      'candidate_subtask_id': candidateSubtaskId,
      'title': title,
      'order_index': orderIndex,
      'estimated_minutes': estimatedMinutes,
      'status': status,
      'is_next_action': isNextAction,
      'energy_required': energyRequired,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
    };
  }
}

class ReminderResponse {
  const ReminderResponse({
    required this.id,
    required this.userId,
    required this.taskId,
    required this.candidateReminderId,
    required this.remindAt,
    required this.message,
    required this.type,
    required this.status,
    required this.escalationLevel,
    required this.createdAt,
    required this.updatedAt,
    required this.sentAt,
  });

  factory ReminderResponse.fromJson(Object? json) {
    final object = _asJsonObject(
      json,
      'Reminder response must be a JSON object.',
    );
    return ReminderResponse(
      id: _readRequiredString(object, 'id'),
      userId: _readRequiredString(object, 'user_id'),
      taskId: _readRequiredString(object, 'task_id'),
      candidateReminderId: _readOptionalString(object, 'candidate_reminder_id'),
      remindAt: _readRequiredDateTime(object, 'remind_at'),
      message: _readRequiredString(object, 'message'),
      type: _readOptionalString(object, 'type') ?? 'start',
      status: _readOptionalString(object, 'status') ?? 'scheduled',
      escalationLevel: _readOptionalInt(object, 'escalation_level') ?? 0,
      createdAt: _readOptionalDateTime(object, 'created_at'),
      updatedAt: _readOptionalDateTime(object, 'updated_at'),
      sentAt: _readOptionalDateTime(object, 'sent_at'),
    );
  }

  final String id;
  final String userId;
  final String taskId;
  final String? candidateReminderId;
  final DateTime remindAt;
  final String message;
  final String type;
  final String status;
  final int escalationLevel;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? sentAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'task_id': taskId,
      'candidate_reminder_id': candidateReminderId,
      'remind_at': remindAt.toIso8601String(),
      'message': message,
      'type': type,
      'status': status,
      'escalation_level': escalationLevel,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'sent_at': sentAt?.toIso8601String(),
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

int? _readOptionalInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null) {
      return parsed;
    }
  }
  throw FormatException('$key must be a number or numeric string or null.');
}

double? _readOptionalDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw FormatException('$key must be a number or null.');
}

bool _readBool(
  Map<String, dynamic> json,
  String key, {
  required bool defaultValue,
}) {
  final value = json[key];
  if (value == null) {
    return defaultValue;
  }
  if (value is bool) {
    return value;
  }
  throw FormatException('$key must be a boolean.');
}

DateTime? _readOptionalDateTime(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : DateTime.parse(trimmed);
  }
  throw FormatException('$key must be an ISO date-time string or null.');
}

DateTime _readRequiredDateTime(Map<String, dynamic> json, String key) {
  final value = _readOptionalDateTime(json, key);
  if (value == null) {
    throw FormatException('$key must be a non-empty ISO date-time string.');
  }
  return value;
}

Map<String, dynamic> _readMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return <String, dynamic>{};
  }
  return _asJsonObject(value, '$key must be a JSON object.');
}

List<T> _readList<T>(
  Map<String, dynamic> json,
  String key,
  T Function(Object? json) parseItem,
) {
  final value = json[key];
  if (value == null) {
    return <T>[];
  }
  if (value is! List) {
    throw FormatException('$key must be a JSON array.');
  }
  return value.map(parseItem).toList();
}
