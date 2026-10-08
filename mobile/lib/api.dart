import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class DeviceSecrets implements SecretStore {
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  @override
  Future<String?> read(String key) => storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => storage.delete(key: key);
}

class ApiError implements Exception {
  final int status;
  final String message;
  ApiError(this.status, this.message);
  @override
  String toString() => message;
}

class Api {
  final String base;
  final http.Client client;
  final SecretStore secrets;
  String? access;
  String language = 'so';
  Future<void>? _refreshing;
  Api({String? base, http.Client? client, SecretStore? secrets})
    : base =
          base ??
          const String.fromEnvironment(
            'API_URL',
            defaultValue: 'http://10.0.2.2:8000/api/v1/',
          ),
      client = client ?? http.Client(),
      secrets = secrets ?? DeviceSecrets() {
    if (kReleaseMode && !this.base.startsWith('https://')) {
      throw StateError('Release API_URL must use HTTPS.');
    }
  }

  Future<void> restore() async {
    if (await secrets.read('refresh') != null) {
      try {
        await refresh();
      } on ApiError {
        access = null;
      }
    }
  }

  Future<void> refresh() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  Future<void> _refresh() async {
    final token = await secrets.read('refresh');
    if (token == null) {
      throw ApiError(401, 'sessionExpired');
    }
    try {
      final data = await call(
        'auth/refresh/',
        method: 'POST',
        body: {'refresh': token},
        authenticated: false,
      );
      access = data['access'] as String;
      await secrets.write('refresh', data['refresh'] as String);
    } on ApiError catch (e) {
      if (e.status == 401) {
        await clearAuth();
      }
      rethrow;
    }
  }

  Future<void> clearAuth() async {
    access = null;
    await secrets.delete('refresh');
  }

  Future<void> login(String email, String password) async {
    await clearAuth();
    final data = await call(
      'auth/login/',
      method: 'POST',
      authenticated: false,
      body: {'email': email, 'password': password},
    );
    access = data['access'] as String;
    await secrets.write('refresh', data['refresh'] as String);
  }

  Future<void> logout() async {
    // Keep the session if offline so the user can retry server-side revocation.
    final token = await secrets.read('refresh');
    await call('auth/logout/', method: 'POST', body: {'refresh': token});
    await clearAuth();
  }

  Future<String> guest() async {
    final existing = await secrets.read('guest');
    if (existing != null) {
      return existing;
    }
    final data = await call('guest/', method: 'POST', authenticated: false);
    final token = data['token'] as String;
    await secrets.write('guest', token);
    if (data['expires_at'] != null) {
      await secrets.write('guest_expiry', data['expires_at'] as String);
    }
    return token;
  }

  // Only call before a NEW quote, never when retrying an uncertain checkout.
  Future<void> freshGuestForQuote() async {
    final expiry = await secrets.read('guest_expiry');
    if (expiry != null && DateTime.parse(expiry).isBefore(DateTime.now())) {
      await secrets.delete('guest');
      await secrets.delete('guest_expiry');
    }
    await guest();
  }

  Future<dynamic> call(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    bool authenticated = true,
    bool anonymous = false,
    String? tracking,
    bool retry = true,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept-Language': language,
    };
    if (authenticated && access != null) {
      headers['Authorization'] = 'Bearer $access';
    }
    if (anonymous) {
      headers['X-Guest-Token'] = await guest();
    }
    if (tracking != null) {
      headers['X-Tracking-Token'] = tracking;
    }
    try {
      final request = http.Request(method, Uri.parse('$base$path'))
        ..headers.addAll(headers);
      if (body != null) {
        request.body = jsonEncode(body);
      }
      final response = await http.Response.fromStream(
        await client.send(request).timeout(const Duration(seconds: 20)),
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode == 401 &&
          authenticated &&
          retry &&
          await secrets.read('refresh') != null) {
        await refresh();
        return await call(
          path,
          method: method,
          body: body,
          authenticated: authenticated,
          anonymous: anonymous,
          tracking: tracking,
          retry: false,
        );
      }
      final dynamic data = response.body.isEmpty
          ? null
          : jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode >= 400) {
        throw ApiError(response.statusCode, _error(data));
      }
      return data;
    } on TimeoutException {
      throw ApiError(0, 'connectionUnknown');
    } on http.ClientException {
      throw ApiError(0, 'connectionUnknown');
    } on FormatException {
      throw ApiError(0, 'connectionUnknown');
    }
  }

  String _error(dynamic value) {
    if (value is Map) {
      return value.values.map(_error).join('\n');
    }
    if (value is List) {
      return value.map(_error).join('\n');
    }
    return value.toString();
  }

  Future<void> upload(String path, String filePath) async {
    if (await secrets.read('refresh') != null) {
      await refresh();
    }
    try {
      final req = http.MultipartRequest('POST', Uri.parse('$base$path'))
        ..headers.addAll({
          'Authorization': 'Bearer $access',
          'Accept-Language': language,
        })
        ..files.add(await http.MultipartFile.fromPath('image', filePath));
      final res = await http.Response.fromStream(
        await client.send(req).timeout(const Duration(seconds: 40)),
      ).timeout(const Duration(seconds: 40));
      if (res.statusCode >= 400) {
        throw ApiError(res.statusCode, _error(jsonDecode(res.body)));
      }
    } on TimeoutException {
      throw ApiError(0, 'connectionUnknown');
    } on http.ClientException {
      throw ApiError(0, 'connectionUnknown');
    } on FormatException {
      throw ApiError(0, 'connectionUnknown');
    }
  }
}
