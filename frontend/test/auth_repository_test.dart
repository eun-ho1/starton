import 'package:flutter_test/flutter_test.dart';
import 'package:start_on/models/api_response.dart';
import 'package:start_on/models/auth_models.dart';
import 'package:start_on/repositories/auth_repository.dart';
import 'package:start_on/services/api_client.dart';

void main() {
  test('signIn posts credentials to sign-in endpoint', () async {
    final apiClient = _FakeAuthApiClient(_successResponse());
    final repository = AuthRepository(apiClient: apiClient);

    final session = await repository.signIn(
      email: 'tester@starton.local',
      password: 'secret123',
    );

    expect(apiClient.path, '/auth/sign-in');
    expect(apiClient.body, {
      'email': 'tester@starton.local',
      'password': 'secret123',
    });
    expect(session.accessToken, 'access-token');
  });

  test('signUp posts credentials to sign-up endpoint', () async {
    final apiClient = _FakeAuthApiClient(_successResponse());
    final repository = AuthRepository(apiClient: apiClient);

    await repository.signUp(
      email: 'tester@starton.local',
      password: 'secret123',
    );

    expect(apiClient.path, '/auth/sign-up');
  });

  test('refreshSession posts refresh token to refresh endpoint', () async {
    final apiClient = _FakeAuthApiClient(_successResponse());
    final repository = AuthRepository(apiClient: apiClient);

    await repository.refreshSession(refreshToken: 'refresh-token');

    expect(apiClient.path, '/auth/refresh');
    expect(apiClient.body, {'refreshToken': 'refresh-token'});
  });

  test(
    'throws repository exception when success response has no session',
    () async {
      final apiClient = _FakeAuthApiClient(
        const ApiResponse<AuthSessionResponse>(
          success: true,
          data: null,
          error: null,
        ),
      );
      final repository = AuthRepository(apiClient: apiClient);

      expect(
        () => repository.signIn(
          email: 'tester@starton.local',
          password: 'secret123',
        ),
        throwsA(isA<AuthRepositoryException>()),
      );
    },
  );
}

ApiResponse<AuthSessionResponse> _successResponse() {
  return const ApiResponse<AuthSessionResponse>(
    success: true,
    data: AuthSessionResponse(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      user: AuthUserResponse(id: 'user-1', email: 'tester@starton.local'),
    ),
    error: null,
  );
}

class _FakeAuthApiClient extends ApiClient {
  _FakeAuthApiClient(this.response) : super(baseUrl: 'http://localhost');

  final ApiResponse<AuthSessionResponse> response;
  String? path;
  Object? body;

  @override
  Future<ApiResponse<T>> postResponse<T>(
    String path, {
    required ApiDataParser<T> parseData,
    Object? body,
    Map<String, String>? queryParameters,
  }) async {
    this.path = path;
    this.body = body;
    return response as ApiResponse<T>;
  }
}
