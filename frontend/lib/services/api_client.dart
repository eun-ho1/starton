import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:start_on/models/api_response.dart';
import 'package:start_on/models/auth_models.dart';
import 'package:start_on/storage/auth_session_store.dart';

typedef AuthTokenProvider = FutureOr<String?> Function();

class ApiClient {
  ApiClient({
    String? baseUrl,
    http.Client? httpClient,
    AuthTokenProvider? authTokenProvider,
    AuthSessionStore? authSessionStore,
    Duration timeout = const Duration(seconds: 20),
  }) : baseUrl = _normalizeBaseUrl(baseUrl ?? resolveDefaultBaseUrl()),
       _httpClient = httpClient ?? http.Client(),
       _authTokenProvider = authTokenProvider,
       _authSessionStore = authSessionStore,
       _timeout = timeout;

  ApiClient.authenticated({
    String? baseUrl,
    http.Client? httpClient,
    AuthSessionStore authSessionStore = const AuthSessionStore(),
    Duration timeout = const Duration(seconds: 20),
  }) : this(
         baseUrl: baseUrl,
         httpClient: httpClient,
         authTokenProvider: authSessionStore.loadAccessToken,
         authSessionStore: authSessionStore,
         timeout: timeout,
       );

  static const String _configuredBaseUrl = String.fromEnvironment(
    'START_ON_API_BASE_URL',
    defaultValue: '',
  );

  static const String _androidEmulatorBaseUrl = 'http://10.0.2.2:8000/api/v1';
  static const String _localhostBaseUrl = 'http://127.0.0.1:8000/api/v1';

  final String baseUrl;
  final http.Client _httpClient;
  final AuthTokenProvider? _authTokenProvider;
  final AuthSessionStore? _authSessionStore;
  final Duration _timeout;

  static String resolveDefaultBaseUrl() {
    if (_configuredBaseUrl.isNotEmpty) {
      return _configuredBaseUrl;
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      // Android Emulator maps the host machine's localhost to 10.0.2.2,
      // so a FastAPI server started with uvicorn --host 0.0.0.0 --port 8000
      // is reachable there without depending on the host Wi-Fi IP address.
      return _androidEmulatorBaseUrl;
    }

    return _localhostBaseUrl;
  }

  Future<dynamic> get(String path, {Map<String, String>? queryParameters}) {
    return request('GET', path, queryParameters: queryParameters);
  }

  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, String>? queryParameters,
  }) {
    return request('POST', path, body: body, queryParameters: queryParameters);
  }

  Future<dynamic> patch(
    String path, {
    Object? body,
    Map<String, String>? queryParameters,
  }) {
    return request('PATCH', path, body: body, queryParameters: queryParameters);
  }

  Future<dynamic> delete(
    String path, {
    Object? body,
    Map<String, String>? queryParameters,
  }) {
    return request(
      'DELETE',
      path,
      body: body,
      queryParameters: queryParameters,
    );
  }

  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? queryParameters,
  }) async {
    final uri = _buildUri(path, queryParameters);
    final encodedBody = body == null ? null : jsonEncode(body);

    var response = await _sendWithHandling(
      method.toUpperCase(),
      uri,
      headers: await _buildHeaders(),
      body: encodedBody,
    );

    if (_shouldTryRefresh(response, path)) {
      final refreshed = await _refreshSession();
      if (refreshed) {
        response = await _sendWithHandling(
          method.toUpperCase(),
          uri,
          headers: await _buildHeaders(),
          body: encodedBody,
        );
      }
    }

    final decodedBody = _decodeResponseBody(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiClientException.fromResponse(response, decodedBody);
    }

    return decodedBody;
  }

  Future<http.Response> _sendWithHandling(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async {
    try {
      return await _send(
        method,
        uri,
        headers: headers,
        body: body,
      ).timeout(_timeout);
    } on TimeoutException catch (error) {
      throw ApiClientException(
        statusCode: 0,
        code: 'request_timeout',
        message: 'API server response timed out.',
        cause: error,
      );
    } on http.ClientException catch (error) {
      throw ApiClientException(
        statusCode: 0,
        code: 'network_error',
        message: 'Failed to reach API server.',
        cause: error,
      );
    } on Exception catch (error) {
      throw ApiClientException(
        statusCode: 0,
        code: 'network_error',
        message: 'Failed to reach API server.',
        cause: error,
      );
    }
  }

  Future<ApiResponse<T>> getResponse<T>(
    String path, {
    required ApiDataParser<T> parseData,
    Map<String, String>? queryParameters,
  }) {
    return requestResponse(
      'GET',
      path,
      parseData: parseData,
      queryParameters: queryParameters,
    );
  }

  Future<ApiResponse<T>> postResponse<T>(
    String path, {
    required ApiDataParser<T> parseData,
    Object? body,
    Map<String, String>? queryParameters,
  }) {
    return requestResponse(
      'POST',
      path,
      parseData: parseData,
      body: body,
      queryParameters: queryParameters,
    );
  }

  Future<ApiResponse<T>> patchResponse<T>(
    String path, {
    required ApiDataParser<T> parseData,
    Object? body,
    Map<String, String>? queryParameters,
  }) {
    return requestResponse(
      'PATCH',
      path,
      parseData: parseData,
      body: body,
      queryParameters: queryParameters,
    );
  }

  Future<ApiResponse<T>> deleteResponse<T>(
    String path, {
    required ApiDataParser<T> parseData,
    Object? body,
    Map<String, String>? queryParameters,
  }) {
    return requestResponse(
      'DELETE',
      path,
      parseData: parseData,
      body: body,
      queryParameters: queryParameters,
    );
  }

  Future<ApiResponse<T>> requestResponse<T>(
    String method,
    String path, {
    required ApiDataParser<T> parseData,
    Object? body,
    Map<String, String>? queryParameters,
  }) async {
    final decodedBody = await request(
      method,
      path,
      body: body,
      queryParameters: queryParameters,
    );

    try {
      return ApiResponse<T>.fromJson(decodedBody, parseData);
    } on FormatException catch (error) {
      throw ApiClientException(
        statusCode: 200,
        code: 'invalid_api_response',
        message: 'Server returned an invalid API response envelope.',
        responseBody: decodedBody,
        cause: error,
      );
    }
  }

  Uri _buildUri(String path, Map<String, String>? queryParameters) {
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    final uri = Uri.parse('$baseUrl/$normalizedPath');

    if (queryParameters == null || queryParameters.isEmpty) {
      return uri;
    }

    return uri.replace(
      queryParameters: {...uri.queryParameters, ...queryParameters},
    );
  }

  Future<Map<String, String>> _buildHeaders() async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };

    final token = await _authTokenProvider?.call();
    if (token != null && token.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${token.trim()}';
    }

    return headers;
  }

  bool _shouldTryRefresh(http.Response response, String path) {
    if (_authSessionStore == null || path == '/auth/refresh') {
      return false;
    }
    if (response.statusCode != 401) {
      return false;
    }
    final decodedBody = _decodeResponseBody(response);
    final exception = ApiClientException.fromResponse(response, decodedBody);
    return exception.code == 'invalid_token';
  }

  Future<bool> _refreshSession() async {
    final authSessionStore = _authSessionStore;
    if (authSessionStore == null) {
      return false;
    }

    final currentSession = await authSessionStore.load();
    final refreshToken = currentSession?.refreshToken?.trim();
    if (currentSession == null || refreshToken == null || refreshToken.isEmpty) {
      await authSessionStore.clear();
      return false;
    }

    final refreshUri = _buildUri('/auth/refresh', null);
    final refreshResponse = await _sendWithHandling(
      'POST',
      refreshUri,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'refreshToken': refreshToken}),
    );
    if (refreshResponse.statusCode < 200 || refreshResponse.statusCode >= 300) {
      await authSessionStore.clear();
      return false;
    }

    final decodedBody = _decodeResponseBody(refreshResponse);
    final apiResponse = ApiResponse<AuthSessionResponse>.fromJson(
      decodedBody,
      AuthSessionResponse.fromJson,
    );
    final sessionData = apiResponse.data;
    if (!apiResponse.success || sessionData == null) {
      await authSessionStore.clear();
      return false;
    }

    await authSessionStore.save(
      AuthSession(
        userId: sessionData.user.id,
        email: sessionData.user.email ?? currentSession.email,
        displayName: currentSession.displayName,
        accessToken: sessionData.accessToken,
        refreshToken: sessionData.refreshToken,
      ),
    );
    return true;
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) {
    return switch (method) {
      'GET' => _httpClient.get(uri, headers: headers),
      'POST' => _httpClient.post(uri, headers: headers, body: body),
      'PATCH' => _httpClient.patch(uri, headers: headers, body: body),
      'DELETE' => _httpClient.delete(uri, headers: headers, body: body),
      _ =>
        _httpClient
            .send(
              http.Request(method, uri)
                ..headers.addAll(headers)
                ..body = body ?? '',
            )
            .then(http.Response.fromStream),
    };
  }

  dynamic _decodeResponseBody(http.Response response) {
    if (response.body.isEmpty) {
      return null;
    }

    try {
      return jsonDecode(response.body);
    } on FormatException catch (error) {
      throw ApiClientException(
        statusCode: response.statusCode,
        code: 'invalid_json_response',
        message: 'Server returned invalid JSON.',
        cause: error,
      );
    }
  }

  void close() => _httpClient.close();

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
        value,
        'baseUrl',
        'Base URL must not be empty.',
      );
    }
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}

class ApiClientException implements Exception {
  ApiClientException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.responseBody,
    this.cause,
  });

  factory ApiClientException.fromResponse(
    http.Response response,
    dynamic responseBody,
  ) {
    String code = 'http_${response.statusCode}';
    String message = 'Request failed with status ${response.statusCode}.';

    if (responseBody case {'error': final Object? error}) {
      if (error case {'code': final Object? errorCode}) {
        code = errorCode.toString();
      }
      if (error case {'message': final Object? errorMessage}) {
        message = errorMessage.toString();
      }
    } else if (responseBody case {'detail': final Object? detail}) {
      if (detail case {'code': final Object? detailCode}) {
        code = detailCode.toString();
      }
      if (detail case {'message': final Object? detailMessage}) {
        message = detailMessage.toString();
      } else {
        message = detail.toString();
      }
    }

    return ApiClientException(
      statusCode: response.statusCode,
      code: code,
      message: message,
      responseBody: responseBody,
    );
  }

  final int statusCode;
  final String code;
  final String message;
  final dynamic responseBody;
  final Object? cause;

  @override
  String toString() => 'ApiClientException($statusCode, $code): $message';
}
