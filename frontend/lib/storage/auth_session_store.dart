import 'package:start_on/models/auth_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthSession {
  const AuthSession({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.accessToken,
    this.refreshToken,
    this.isLocalOnly = false,
  });

  factory AuthSession.fromAuthResponse(AuthSessionResponse response) {
    final email = response.user.email ?? '';
    return AuthSession(
      userId: response.user.id,
      email: email,
      displayName: _displayNameForEmail(email),
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
    );
  }

  factory AuthSession.local({
    required String email,
    required String displayName,
  }) {
    final normalizedEmail = email.trim();
    return AuthSession(
      userId: normalizedEmail.isEmpty ? 'local:user' : 'local:$normalizedEmail',
      email: normalizedEmail,
      displayName: displayName.trim().isEmpty ? '사용자' : displayName.trim(),
      accessToken: '',
      isLocalOnly: true,
    );
  }

  final String userId;
  final String email;
  final String displayName;
  final String accessToken;
  final String? refreshToken;
  final bool isLocalOnly;

  bool get hasBearerToken => accessToken.trim().isNotEmpty;
}

class AuthSessionStore {
  const AuthSessionStore();

  static const _isSignedInKey = 'auth.is_signed_in';
  static const _userIdKey = 'auth.user_id';
  static const _emailKey = 'auth.email';
  static const _displayNameKey = 'auth.display_name';
  static const _accessTokenKey = 'auth.access_token';
  static const _refreshTokenKey = 'auth.refresh_token';
  static const _isLocalOnlyKey = 'auth.is_local_only';

  Future<AuthSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final isSignedIn = prefs.getBool(_isSignedInKey) ?? false;
    if (!isSignedIn) {
      return null;
    }

    final session = AuthSession(
      userId: prefs.getString(_userIdKey) ?? '',
      email: prefs.getString(_emailKey) ?? '',
      displayName: prefs.getString(_displayNameKey) ?? '',
      accessToken: prefs.getString(_accessTokenKey) ?? '',
      refreshToken: _readNullableString(prefs, _refreshTokenKey),
      isLocalOnly: prefs.getBool(_isLocalOnlyKey) ?? false,
    );

    if (!_isValid(session)) {
      await clear();
      return null;
    }

    return session;
  }

  Future<void> save(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isSignedInKey, true);
    await prefs.setString(_userIdKey, session.userId);
    await prefs.setString(_emailKey, session.email);
    await prefs.setString(_displayNameKey, session.displayName);
    await prefs.setString(_accessTokenKey, session.accessToken);
    await prefs.setBool(_isLocalOnlyKey, session.isLocalOnly);

    final refreshToken = session.refreshToken;
    if (refreshToken == null || refreshToken.trim().isEmpty) {
      await prefs.remove(_refreshTokenKey);
    } else {
      await prefs.setString(_refreshTokenKey, refreshToken);
    }
  }

  Future<String?> loadAccessToken() async {
    final session = await load();
    if (session == null || !session.hasBearerToken) {
      return null;
    }

    return session.accessToken.trim();
  }

  Future<String?> loadRefreshToken() async {
    final session = await load();
    final refreshToken = session?.refreshToken?.trim();
    if (refreshToken == null || refreshToken.isEmpty) {
      return null;
    }
    return refreshToken;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_isSignedInKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_displayNameKey);
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_isLocalOnlyKey);
  }

  bool _isValid(AuthSession session) {
    if (session.userId.trim().isEmpty ||
        session.email.trim().isEmpty ||
        session.displayName.trim().isEmpty) {
      return false;
    }

    return session.isLocalOnly || session.hasBearerToken;
  }
}

String? _readNullableString(SharedPreferences prefs, String key) {
  final value = prefs.getString(key);
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return value;
}

String _displayNameForEmail(String email) {
  final localPart = email.split('@').first.trim();
  final cleaned = localPart.replaceAll(RegExp(r'[._-]+'), ' ').trim();
  if (cleaned.isEmpty) {
    return '사용자';
  }

  return cleaned
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
