import 'package:start_on/models/api_response.dart';
import 'package:start_on/models/auth_models.dart';
import 'package:start_on/services/api_client.dart';

class AuthRepository {
  AuthRepository({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient(),
      _ownsApiClient = apiClient == null;

  final ApiClient _apiClient;
  final bool _ownsApiClient;

  Future<AuthSessionResponse> signIn({
    required String email,
    required String password,
  }) {
    return _authenticate(
      path: '/auth/sign-in',
      request: AuthEmailPasswordRequest(email: email, password: password),
    );
  }

  Future<AuthSessionResponse> signUp({
    required String email,
    required String password,
  }) {
    return _authenticate(
      path: '/auth/sign-up',
      request: AuthEmailPasswordRequest(email: email, password: password),
    );
  }

  Future<AuthSessionResponse> refreshSession({required String refreshToken}) {
    return _refresh(refreshToken: refreshToken);
  }

  Future<AuthSessionResponse> _authenticate({
    required String path,
    required AuthEmailPasswordRequest request,
  }) async {
    final response = await _apiClient.postResponse<AuthSessionResponse>(
      path,
      body: request.toJson(),
      parseData: AuthSessionResponse.fromJson,
    );

    return _requireSession(response);
  }

  Future<AuthSessionResponse> _refresh({required String refreshToken}) async {
    final response = await _apiClient.postResponse<AuthSessionResponse>(
      '/auth/refresh',
      body: {'refreshToken': refreshToken.trim()},
      parseData: AuthSessionResponse.fromJson,
    );

    return _requireSession(response);
  }

  AuthSessionResponse _requireSession(
    ApiResponse<AuthSessionResponse> response,
  ) {
    final data = response.data;
    if (response.success && data != null) {
      return data;
    }

    final error = response.error;
    throw AuthRepositoryException(
      code: error?.code ?? 'missing_auth_session',
      message:
          error?.message ?? 'Server response did not include an auth session.',
    );
  }

  void close() {
    if (_ownsApiClient) {
      _apiClient.close();
    }
  }
}

class AuthRepositoryException implements Exception {
  const AuthRepositoryException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => 'AuthRepositoryException($code): $message';
}
