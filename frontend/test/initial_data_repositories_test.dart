import 'package:flutter_test/flutter_test.dart';
import 'package:start_on/models/api_response.dart';
import 'package:start_on/models/dungeon_api_models.dart';
import 'package:start_on/models/profile_api_models.dart';
import 'package:start_on/models/stats_api_models.dart';
import 'package:start_on/repositories/dungeon_repository.dart';
import 'package:start_on/repositories/profile_repository.dart';
import 'package:start_on/repositories/stats_repository.dart';
import 'package:start_on/services/api_client.dart';

void main() {
  test('ProfileRepository loads profile endpoint', () async {
    final apiClient = _FakeApiClient(
      const ApiResponse<ProfileResponse>(
        success: true,
        data: ProfileResponse(
          userName: 'Tester',
          userRole: 'Beginner',
          level: 2,
          currentExp: 120,
          maxExp: 700,
          credits: 9,
          completedQuestCount: 5,
          earnedExp: 320,
        ),
        error: null,
      ),
    );
    final repository = ProfileRepository(apiClient: apiClient);

    final profile = await repository.getProfile();

    expect(apiClient.requests.single.method, 'GET');
    expect(apiClient.requests.single.path, '/profile');
    expect(profile.userName, 'Tester');
    expect(profile.credits, 9);
  });

  test('StatsRepository loads stats summary endpoint', () async {
    final apiClient = _FakeApiClient(
      const ApiResponse<StatsSummaryResponse>(
        success: true,
        data: StatsSummaryResponse(
          dailyRewardCount: 1,
          dailyRewardTarget: 3,
          weeklyRewardCount: 2,
          weeklyRewardTarget: 7,
          monthlyRewardCount: 4,
          monthlyRewardTarget: 30,
          weeklyCompletedCount: 2,
          weeklyCompletionRate: 29,
          weeklyRateDelta: 5,
          diligenceStat: 12,
          orderStat: 8,
          intelligenceStat: 15,
          healthStat: 7,
        ),
        error: null,
      ),
    );
    final repository = StatsRepository(apiClient: apiClient);

    final stats = await repository.getSummary();

    expect(apiClient.requests.single.method, 'GET');
    expect(apiClient.requests.single.path, '/stats/summary');
    expect(stats.weeklyCompletionRate, 29);
    expect(stats.intelligenceStat, 15);
  });

  test('DungeonRepository loads dungeon list endpoint', () async {
    final apiClient = _FakeApiClient(
      const ApiResponse<DungeonListResponse>(
        success: true,
        data: DungeonListResponse(
          dungeons: [
            DungeonStatusResponse(
              dungeonId: 'dungeon_meditation',
              title: 'Meditation',
              difficulty: 'easy',
              completed: true,
              cleared: true,
              canClaim: false,
              creditReward: 8,
              clearedAt: '2026-05-09T12:00:00',
            ),
          ],
        ),
        error: null,
      ),
    );
    final repository = DungeonRepository(apiClient: apiClient);

    final response = await repository.listDungeons();

    expect(apiClient.requests.single.method, 'GET');
    expect(apiClient.requests.single.path, '/dungeons');
    expect(response.dungeons.single.dungeonId, 'dungeon_meditation');
    expect(response.dungeons.single.cleared, isTrue);
  });

  test('DungeonRepository posts dungeon clear endpoint', () async {
    final apiClient = _FakeApiClient(
      const ApiResponse<DungeonClearResponse>(
        success: true,
        data: DungeonClearResponse(
          dungeonId: 'dungeon_meditation',
          cleared: true,
          credits: 18,
          clearedAt: '2026-05-09T12:00:00',
        ),
        error: null,
      ),
    );
    final repository = DungeonRepository(apiClient: apiClient);

    final response = await repository.clearDungeon('dungeon_meditation');

    expect(apiClient.requests.single.method, 'POST');
    expect(
      apiClient.requests.single.path,
      '/dungeons/dungeon_meditation/clear',
    );
    expect(response.credits, 18);
  });
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient(this.response) : super(baseUrl: 'http://localhost');

  final ApiResponse<dynamic> response;
  final List<_CapturedRequest> requests = [];

  @override
  Future<ApiResponse<T>> getResponse<T>(
    String path, {
    required ApiDataParser<T> parseData,
    Map<String, String>? queryParameters,
  }) async {
    requests.add(_CapturedRequest(method: 'GET', path: path));
    return response as ApiResponse<T>;
  }

  @override
  Future<ApiResponse<T>> postResponse<T>(
    String path, {
    required ApiDataParser<T> parseData,
    Object? body,
    Map<String, String>? queryParameters,
  }) async {
    requests.add(_CapturedRequest(method: 'POST', path: path));
    return response as ApiResponse<T>;
  }
}

class _CapturedRequest {
  const _CapturedRequest({required this.method, required this.path});

  final String method;
  final String path;
}
