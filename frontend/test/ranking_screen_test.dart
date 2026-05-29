import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:start_on/models/app_local_data.dart';
import 'package:start_on/models/leaderboard_api_models.dart';
import 'package:start_on/pages/ranking_screen.dart';

void main() {
  testWidgets('renders Korean ranking UI and uses server leaderboard ranks', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RankingScreen(
            data: _sampleData(),
            leaderboard: const LeaderboardResponse(
              currentUserRank: 42,
              entries: [
                LeaderboardEntryResponse(
                  rank: 1,
                  userId: 'user-2',
                  userName: '상위유저',
                  userRole: 'Master',
                  level: 12,
                  score: 5000,
                  earnedExp: 2200,
                  credits: 100,
                  completedQuestCount: 80,
                  weeklyCompletedCount: 16,
                  weeklyCompletionRate: 100,
                  clearedDungeonCount: 4,
                  isCurrentUser: false,
                ),
                LeaderboardEntryResponse(
                  rank: 42,
                  userId: 'user-1',
                  userName: '테스터',
                  userRole: 'Beginner',
                  level: 5,
                  score: 2100,
                  earnedExp: 800,
                  credits: 40,
                  completedQuestCount: 20,
                  weeklyCompletedCount: 5,
                  weeklyCompletionRate: 62,
                  clearedDungeonCount: 1,
                  isCurrentUser: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('주간 랭킹'), findsOneWidget);
    expect(find.text('완료한 퀘스트'), findsOneWidget);
    expect(find.text('획득한 EXP'), findsOneWidget);
    expect(find.text('#42'), findsOneWidget);
    expect(find.text('다음 순위까지 2901점 남았어요'), findsOneWidget);
    expect(find.text('42'), findsWidgets);
    expect(find.textContaining('이번 주 5개 완료'), findsOneWidget);
  });

  testWidgets('does not show mock users when server leaderboard is missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RankingScreen(
            data: _sampleData(),
          ),
        ),
      ),
    );

    expect(find.text('테스터'), findsOneWidget);
    expect(find.text('Dawn Runner'), findsNothing);
    expect(find.text('Focus Master'), findsNothing);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('현재 1위입니다'), findsOneWidget);
  });
}

AppLocalData _sampleData() {
  return AppLocalData(
    userName: '테스터',
    userRole: '초보자',
    level: 5,
    currentExp: 150,
    maxExp: 500,
    credits: 40,
    completedQuestCount: 20,
    earnedExp: 800,
    dailyRewardCount: 1,
    dailyRewardTarget: 3,
    weeklyRewardCount: 5,
    weeklyRewardTarget: 7,
    monthlyRewardCount: 12,
    monthlyRewardTarget: 30,
    weeklyCompletedCount: 5,
    weeklyCompletionRate: 62,
    weeklyRateDelta: 4,
    diligenceStat: 10,
    orderStat: 8,
    intelligenceStat: 7,
    healthStat: 6,
    weeklyActivityCounts: const [0, 1, 1, 1, 1, 1, 0],
    weeklyActivityBars: const [0, 0.2, 0.3, 0.5, 0.4, 0.6, 0],
    recentActivities: const [],
    completedQuests: const [],
    quests: const [],
    clearedDungeonIds: const ['d-1'],
    previousWeeklyCompletionRate: 58,
    dailyResetKey: '',
    weeklyResetKey: '',
    monthlyResetKey: '',
  );
}
