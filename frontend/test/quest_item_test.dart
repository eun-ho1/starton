import 'package:flutter_test/flutter_test.dart';
import 'package:start_on/models/quest_api_models.dart';
import 'package:start_on/models/quest_item.dart';

void main() {
  test('fromApiResponse maps server quest fields to screen model fields', () {
    const response = QuestItemResponse(
      id: 'quest-1',
      title: '서버 퀘스트',
      exp: 50,
      difficulty: 'normal',
      category: 'study',
      elapsedSeconds: 120,
      defaultDurationSeconds: 2700,
      dueAt: null,
    );

    final quest = QuestItem.fromApiResponse(response);

    expect(quest.id, 'quest-1');
    expect(quest.title, '서버 퀘스트');
    expect(quest.exp, 50);
    expect(quest.difficulty, '보통');
    expect(quest.category, 'study');
    expect(quest.elapsedSeconds, 120);
    expect(quest.defaultDurationSeconds, 2700);
    expect(quest.dueDate, isNull);
    expect(quest.syncTarget, questSyncTargetQuest);
    expect(quest.syncsWithQuestApi, isTrue);
  });

  test('toCreateRequest maps screen model fields to server request fields', () {
    final quest = QuestItem(
      id: 'local-1',
      title: ' 새 퀘스트 ',
      exp: 100,
      difficulty: '어려움',
      category: 'A&I',
      elapsedSeconds: 300,
      defaultDurationSeconds: 5400,
      dueDate: DateTime(2026, 5, 9),
    );

    final request = quest.toCreateRequest();

    expect(request.toJson(), {
      'title': '새 퀘스트',
      'exp': 100,
      'difficulty': 'hard',
      'category': 'study',
      'defaultDurationSeconds': 5400,
      'due_at': '2026-05-09T00:00:00.000',
    });
  });

  test('toUpdateRequest includes elapsed seconds for server updates', () {
    final quest = QuestItem(
      id: 'quest-1',
      title: '진행 중 퀘스트',
      exp: 30,
      difficulty: '쉬움',
      category: 'life',
      elapsedSeconds: 600,
      defaultDurationSeconds: 1500,
      dueDate: DateTime(2026, 5, 10),
    );

    final request = quest.toUpdateRequest();

    expect(request.toJson(), {
      'title': '진행 중 퀘스트',
      'exp': 30,
      'difficulty': 'easy',
      'category': 'life',
      'elapsedSeconds': 600,
      'defaultDurationSeconds': 1500,
      'due_at': '2026-05-10T00:00:00.000',
    });
  });

  test('normalizeQuestDueDate converts utc due dates before trimming time', () {
    final normalized = normalizeQuestDueDate(
      DateTime.parse('2026-06-02T00:00:00Z'),
    );

    expect(normalized, DateTime(2026, 6, 2));
  });

  test('fromJson accepts server difficulty names from cached data', () {
    final quest = QuestItem.fromJson({
      'id': 'quest-1',
      'title': '캐시 퀘스트',
      'exp': 50,
      'difficulty': 'normal',
      'category': 'work',
      'elapsedSeconds': 0,
    });

    expect(quest.difficulty, '보통');
    expect(quest.defaultDurationSeconds, 45 * 60);
    expect(quest.syncTarget, questSyncTargetLocal);
    expect(quest.syncsWithQuestApi, isFalse);
  });

  test('fromJson restores due date from due_at cached data', () {
    final quest = QuestItem.fromJson({
      'id': 'quest-2',
      'title': 'calendar quest',
      'exp': 40,
      'difficulty': 'easy',
      'category': 'life',
      'elapsedSeconds': 0,
      'defaultDurationSeconds': 1200,
      'due_at': '2026-06-03T09:00:00+09:00',
    });

    expect(quest.dueDate, DateTime(2026, 6, 3));
  });

  test('json preserves task sync target', () {
    final quest = QuestItem(
      id: 'task-1',
      title: 'AI 태스크',
      exp: 100,
      difficulty: '어려움',
      category: 'study',
      elapsedSeconds: 0,
      defaultDurationSeconds: 5400,
      activeSubtaskId: 'task-subtask-1',
      subtasks: [
        QuestSubtask(
          id: 'task-subtask-1',
          title: '자료 열기',
          orderIndex: 0,
          estimatedMinutes: 5,
          status: 'done',
          isNextAction: true,
          energyRequired: 'low',
          completedAt: DateTime(2026, 5, 16, 10, 30),
          elapsedSeconds: 300,
        ),
      ],
      syncTarget: questSyncTargetTask,
    );

    final decoded = QuestItem.fromJson(quest.toJson());

    expect(decoded.syncTarget, questSyncTargetTask);
    expect(decoded.isTaskBacked, isTrue);
    expect(decoded.syncsWithQuestApi, isFalse);
    expect(decoded.activeSubtaskId, 'task-subtask-1');
    expect(decoded.effectiveDurationSeconds, 300);
    expect(decoded.effectiveActiveSubtaskId, isNull);
    expect(decoded.subtasks, hasLength(1));
    expect(decoded.subtasks.single.id, 'task-subtask-1');
    expect(decoded.subtasks.single.title, '자료 열기');
    expect(decoded.subtasks.single.orderIndex, 0);
    expect(decoded.subtasks.single.estimatedMinutes, 5);
    expect(decoded.subtasks.single.status, 'done');
    expect(decoded.subtasks.single.isDone, isTrue);
    expect(decoded.subtasks.single.isNextAction, isTrue);
    expect(decoded.subtasks.single.energyRequired, 'low');
    expect(decoded.subtasks.single.completedAt, DateTime(2026, 5, 16, 10, 30));
    expect(decoded.subtasks.single.elapsedSeconds, 300);
    expect(decoded.subtasks.single.plannedDurationSeconds, 300);
  });

  test('QuestSubtask copyWith can toggle completion locally', () {
    const subtask = QuestSubtask(
      id: 'task-subtask-1',
      title: '자료 열기',
      orderIndex: 0,
      status: 'todo',
    );
    final completedAt = DateTime(2026, 5, 16, 11);

    final done = subtask.copyWith(
      status: 'done',
      completedAt: completedAt,
      elapsedSeconds: 60,
    );
    final reopened = done.copyWith(
      status: 'todo',
      completedAt: null,
      elapsedSeconds: 0,
    );

    expect(done.isDone, isTrue);
    expect(done.completedAt, completedAt);
    expect(done.elapsedSeconds, 60);
    expect(reopened.isDone, isFalse);
    expect(reopened.completedAt, isNull);
    expect(reopened.elapsedSeconds, 0);
  });

  test('effective active subtask uses first incomplete task', () {
    final quest = QuestItem(
      id: 'task-1',
      title: 'AI 태스크',
      exp: 100,
      difficulty: '보통',
      category: 'study',
      elapsedSeconds: 60,
      defaultDurationSeconds: 1800,
      activeSubtaskId: 'done-subtask',
      subtasks: [
        const QuestSubtask(
          id: 'done-subtask',
          title: '완료된 단계',
          orderIndex: 0,
          estimatedMinutes: 1,
          status: 'done',
          elapsedSeconds: 60,
        ),
        const QuestSubtask(
          id: 'next-subtask',
          title: '다음 단계',
          orderIndex: 1,
          estimatedMinutes: 2,
        ),
      ],
    );

    expect(quest.effectiveDurationSeconds, 180);
    expect(quest.effectiveActiveSubtaskId, 'next-subtask');
  });
}
