import 'package:start_on/models/api_response.dart';
import 'package:start_on/models/leaderboard_api_models.dart';
import 'package:start_on/services/api_client.dart';

class LeaderboardRepository {
  LeaderboardRepository({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient.authenticated(),
      _ownsApiClient = apiClient == null;

  final ApiClient _apiClient;
  final bool _ownsApiClient;

  Future<LeaderboardResponse> getLeaderboard({int limit = 50}) async {
    final response = await _apiClient.getResponse<LeaderboardResponse>(
      '/leaderboard?limit=$limit',
      parseData: LeaderboardResponse.fromJson,
    );

    return _requireData(
      response,
      code: 'missing_leaderboard',
      message: 'Server response did not include leaderboard data.',
    );
  }

  void close() {
    if (_ownsApiClient) {
      _apiClient.close();
    }
  }

  T _requireData<T>(
    ApiResponse<T> response, {
    required String code,
    required String message,
  }) {
    final data = response.data;
    if (response.success && data != null) {
      return data;
    }

    final error = response.error;
    throw LeaderboardRepositoryException(
      code: error?.code ?? code,
      message: error?.message ?? message,
    );
  }
}

class LeaderboardRepositoryException implements Exception {
  const LeaderboardRepositoryException({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;

  @override
  String toString() => 'LeaderboardRepositoryException($code): $message';
}
