import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:start_on/models/completed_quest_record.dart';
import 'package:start_on/models/quest_item.dart';
import 'package:start_on/pages/quest_timer_screen.dart';

void main() {
  testWidgets(
    'subtask timer advances to next subtask and completes parent quest',
    (tester) async {
      final changedQuests = <QuestItem>[];
      Object? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  Navigator.of(context)
                      .push<Object?>(
                        MaterialPageRoute<Object?>(
                          builder: (_) => QuestTimerScreen(
                            quest: _timedSubtaskQuest(),
                            userLevel: 1,
                            notificationsEnabled: false,
                            onQuestChanged: changedQuests.add,
                          ),
                        ),
                      )
                      .then((value) => result = value);
                },
                child: const Text('open timer'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('open timer'));
      await tester.pumpAndSettle();

      expect(find.text('진행 중 · 0:00/1:00'), findsOneWidget);
      expect(find.text('대기 · 0:00/1:00'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.play_arrow_rounded).last);
      await tester.pump();

      for (var i = 0; i < 60; i += 1) {
        await tester.pump(const Duration(seconds: 1));
      }

      expect(find.text('완료됨 · 1:00/1:00'), findsOneWidget);
      expect(find.text('진행 중 · 0:00/1:00'), findsOneWidget);
      expect(changedQuests.last.activeSubtaskId, 'subtask-2');
      expect(changedQuests.last.subtasks.first.status, 'done');
      expect(changedQuests.last.subtasks.first.elapsedSeconds, 60);

      for (var i = 0; i < 60; i += 1) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump();

      expect(result, isA<CompletedQuestRecord>());
      final record = result! as CompletedQuestRecord;
      expect(record.questId, 'quest-1');
      expect(record.elapsedSeconds, 120);
      expect(record.subtasks, hasLength(2));
      expect(record.subtasks.map((subtask) => subtask.status), [
        'done',
        'done',
      ]);
      expect(record.subtasks.map((subtask) => subtask.elapsedSeconds), [
        60,
        60,
      ]);
    },
  );

  testWidgets('edit page AI button requests suggestion flow', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    QuestItem? requestedOriginalQuest;
    QuestItem? requestedDraft;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                Navigator.of(context).push<Object?>(
                  MaterialPageRoute<Object?>(
                    builder: (_) => QuestTimerScreen(
                      quest: _simpleQuest(),
                      userLevel: 1,
                      notificationsEnabled: false,
                      onAiSuggestionRequested:
                          ({
                            required QuestItem originalQuest,
                            required QuestItem draft,
                          }) async {
                            requestedOriginalQuest = originalQuest;
                            requestedDraft = draft;
                            return draft.copyWith(title: 'AI 제안 결과');
                          },
                    ),
                  ),
                );
              },
              child: const Text('open timer'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open timer'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI 제안 페이지로 이동'));
    await tester.pumpAndSettle();

    expect(requestedOriginalQuest?.id, 'quest-simple');
    expect(requestedDraft?.title, '단일 작업');
    expect(find.text('AI 제안 결과'), findsOneWidget);
  });

  testWidgets('edit page delete button returns delete result', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    Object? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                Navigator.of(context)
                    .push<Object?>(
                      MaterialPageRoute<Object?>(
                        builder: (_) => QuestTimerScreen(
                          quest: _timedSubtaskQuest(),
                          userLevel: 1,
                          notificationsEnabled: false,
                        ),
                      ),
                    )
                    .then((value) => result = value);
              },
              child: const Text('open timer'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open timer'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pumpAndSettle();

    expect(find.text('퀘스트 수정'), findsOneWidget);
    expect(find.byTooltip('퀘스트 삭제'), findsOneWidget);

    await tester.tap(find.byTooltip('퀘스트 삭제'));
    await tester.pumpAndSettle();

    expect(find.text('퀘스트 삭제'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '삭제'));
    await tester.pumpAndSettle();

    expect(result, isA<QuestTimerDeleteResult>());
    expect((result! as QuestTimerDeleteResult).quest.id, 'quest-1');
  });
}

QuestItem _simpleQuest() {
  return QuestItem(
    id: 'quest-simple',
    title: '단일 작업',
    exp: 50,
    difficulty: '보통',
    category: 'work',
    elapsedSeconds: 0,
    defaultDurationSeconds: 25 * 60,
  );
}

QuestItem _timedSubtaskQuest() {
  return QuestItem(
    id: 'quest-1',
    title: '순차 작업',
    exp: 30,
    difficulty: '쉬움',
    category: 'study',
    elapsedSeconds: 0,
    defaultDurationSeconds: 25 * 60,
    activeSubtaskId: 'subtask-1',
    subtasks: const [
      QuestSubtask(
        id: 'subtask-1',
        title: '첫 번째 단계',
        orderIndex: 0,
        estimatedMinutes: 1,
      ),
      QuestSubtask(
        id: 'subtask-2',
        title: '두 번째 단계',
        orderIndex: 1,
        estimatedMinutes: 1,
      ),
    ],
  );
}
