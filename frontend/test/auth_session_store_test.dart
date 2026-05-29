import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:start_on/models/auth_models.dart';
import 'package:start_on/storage/auth_session_store.dart';

void main() {
  const store = AuthSessionStore();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('saves and loads server auth session', () async {
    final session = AuthSession.fromAuthResponse(
      const AuthSessionResponse(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        user: AuthUserResponse(id: 'user-1', email: 'tester@starton.local'),
      ),
    );

    await store.save(session);
    final loaded = await store.load();

    expect(loaded, isNotNull);
    expect(loaded?.userId, 'user-1');
    expect(loaded?.email, 'tester@starton.local');
    expect(loaded?.displayName, 'Tester');
    expect(loaded?.accessToken, 'access-token');
    expect(loaded?.refreshToken, 'refresh-token');
    expect(loaded?.isLocalOnly, isFalse);
    expect(loaded?.hasBearerToken, isTrue);
  });

  test('loads trimmed access token for authenticated API clients', () async {
    await store.save(
      const AuthSession(
        userId: 'user-1',
        email: 'tester@starton.local',
        displayName: 'Tester',
        accessToken: ' access-token ',
      ),
    );

    expect(await store.loadAccessToken(), 'access-token');
  });

  test('loads trimmed refresh token when present', () async {
    await store.save(
      const AuthSession(
        userId: 'user-1',
        email: 'tester@starton.local',
        displayName: 'Tester',
        accessToken: 'access-token',
        refreshToken: ' refresh-token ',
      ),
    );

    expect(await store.loadRefreshToken(), 'refresh-token');
  });

  test('removes refresh token key when refresh token is null', () async {
    await store.save(
      const AuthSession(
        userId: 'user-1',
        email: 'tester@starton.local',
        displayName: 'Tester',
        accessToken: 'access-token',
        refreshToken: null,
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth.refresh_token'), isNull);
  });

  test('saves and loads local-only session without bearer token', () async {
    await store.save(
      AuthSession.local(email: 'guest@starton.local', displayName: '게스트'),
    );

    final loaded = await store.load();

    expect(loaded?.userId, 'local:guest@starton.local');
    expect(loaded?.accessToken, '');
    expect(loaded?.isLocalOnly, isTrue);
    expect(loaded?.hasBearerToken, isFalse);
  });

  test('clears incomplete server session', () async {
    SharedPreferences.setMockInitialValues({
      'auth.is_signed_in': true,
      'auth.user_id': 'user-1',
      'auth.email': 'tester@starton.local',
      'auth.display_name': 'Tester',
    });

    final loaded = await store.load();
    final prefs = await SharedPreferences.getInstance();

    expect(loaded, isNull);
    expect(prefs.getBool('auth.is_signed_in'), isNull);
    expect(prefs.getString('auth.user_id'), isNull);
  });

  test('clear removes all auth keys', () async {
    await store.save(
      const AuthSession(
        userId: 'user-1',
        email: 'tester@starton.local',
        displayName: 'Tester',
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
      ),
    );

    await store.clear();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('auth.is_signed_in'), isNull);
    expect(prefs.getString('auth.user_id'), isNull);
    expect(prefs.getString('auth.email'), isNull);
    expect(prefs.getString('auth.display_name'), isNull);
    expect(prefs.getString('auth.access_token'), isNull);
    expect(prefs.getString('auth.refresh_token'), isNull);
    expect(prefs.getBool('auth.is_local_only'), isNull);
  });
}
