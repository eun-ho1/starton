import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:start_on/models/auth_models.dart';
import 'package:start_on/services/api_client.dart';
import 'package:start_on/storage/auth_session_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'authenticated client sends saved access token as Bearer header',
    () async {
      await const AuthSessionStore().save(
        const AuthSession(
          userId: 'user-1',
          email: 'tester@starton.local',
          displayName: 'Tester',
          accessToken: ' access-token ',
        ),
      );

      final capturedHeaders = <String, String>{};
      final apiClient = ApiClient.authenticated(
        baseUrl: 'http://localhost/api/v1',
        httpClient: MockClient((request) async {
          capturedHeaders.addAll(request.headers);
          return _okResponse();
        }),
      );

      await apiClient.get('/profile');

      expect(capturedHeaders['Authorization'], 'Bearer access-token');
    },
  );

  test(
    'authenticated client omits Authorization header for local-only session',
    () async {
      await const AuthSessionStore().save(
        AuthSession.local(email: 'guest@starton.local', displayName: '게스트'),
      );

      final capturedHeaders = <String, String>{};
      final apiClient = ApiClient.authenticated(
        baseUrl: 'http://localhost/api/v1',
        httpClient: MockClient((request) async {
          capturedHeaders.addAll(request.headers);
          return _okResponse();
        }),
      );

      await apiClient.get('/profile');

      expect(capturedHeaders.containsKey('Authorization'), isFalse);
    },
  );

  test('client normalizes request timeout failures', () async {
    final apiClient = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      timeout: const Duration(milliseconds: 1),
      httpClient: MockClient((request) async {
        await Future<void>.delayed(const Duration(seconds: 1));
        return _okResponse();
      }),
    );

    await expectLater(
      apiClient.get('/profile'),
      throwsA(
        isA<ApiClientException>()
            .having((error) => error.statusCode, 'statusCode', 0)
            .having((error) => error.code, 'code', 'request_timeout'),
      ),
    );
  });

  test('client normalizes network failures', () async {
    final apiClient = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      httpClient: MockClient((request) async {
        throw const SocketException('Network is unreachable');
      }),
    );

    await expectLater(
      apiClient.get('/profile'),
      throwsA(
        isA<ApiClientException>()
            .having((error) => error.statusCode, 'statusCode', 0)
            .having((error) => error.code, 'code', 'network_error'),
      ),
    );
  });

  test('authenticated client refreshes expired token and retries once', () async {
    await const AuthSessionStore().save(
      const AuthSession(
        userId: 'user-1',
        email: 'tester@starton.local',
        displayName: 'Tester',
        accessToken: 'expired-token',
        refreshToken: 'refresh-token',
      ),
    );

    var profileAttempts = 0;
    final apiClient = ApiClient.authenticated(
      baseUrl: 'http://localhost/api/v1',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': const AuthSessionResponse(
                accessToken: 'new-access-token',
                refreshToken: 'new-refresh-token',
                user: AuthUserResponse(
                  id: 'user-1',
                  email: 'tester@starton.local',
                ),
              ).toJson(),
              'error': null,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        profileAttempts += 1;
        if (profileAttempts == 1) {
          return http.Response(
            jsonEncode({
              'detail': {
                'code': 'invalid_token',
                'message': 'Supabase access token validation failed.',
              },
            }),
            401,
            headers: {'content-type': 'application/json'},
          );
        }

        expect(request.headers['Authorization'], 'Bearer new-access-token');
        return _okResponse();
      }),
    );

    await apiClient.get('/profile');

    final session = await const AuthSessionStore().load();
    expect(profileAttempts, 2);
    expect(session?.accessToken, 'new-access-token');
    expect(session?.refreshToken, 'new-refresh-token');
  });
}

http.Response _okResponse() {
  return http.Response(
    jsonEncode({
      'success': true,
      'data': {'ok': true},
      'error': null,
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}
