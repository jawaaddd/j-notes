import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/client.dart';

/// Where the app is in connecting and signing in (ui-frontend-spec, Sign-in
/// and setup).
enum SessionPhase { loading, connect, setup, signIn, ready }

@immutable
class SessionState {
  const SessionState({required this.phase, this.api, this.serverUrl, this.error, this.passwordFromEnv = false});

  final SessionPhase phase;

  /// The API client for [serverUrl]; carries the session token once ready.
  final ApiClient? api;
  final String? serverUrl;
  final String? error;
  final bool passwordFromEnv;

  SessionState copyWith({SessionPhase? phase, ApiClient? api, String? error, bool clearError = false}) => SessionState(
    phase: phase ?? this.phase,
    api: api ?? this.api,
    serverUrl: serverUrl,
    error: clearError ? null : (error ?? this.error),
    passwordFromEnv: passwordFromEnv,
  );
}

const defaultServerUrl = 'http://localhost:8080';

/// Keeps the server address in preferences and the session token in the OS
/// keychain. If no keychain is available (e.g. no Secret Service running on
/// Linux), the token goes in a file only this user can read, in the app's
/// support folder.
class _TokenStore {
  final _secure = const FlutterSecureStorage();

  String _key(String server) => 'session-token:$server';

  Future<String?> read(String server) async {
    final key = _key(server);
    try {
      final token = await _secure.read(key: key);
      if (token != null) return token;
    } catch (e) {
      debugPrint('keychain unavailable, using the token file: $e');
    }
    return (await _readFile())[key];
  }

  Future<void> write(String server, String? token) async {
    final key = _key(server);
    var saved = false;
    try {
      token == null ? await _secure.delete(key: key) : await _secure.write(key: key, value: token);
      saved = true;
    } catch (e) {
      debugPrint('keychain unavailable, using the token file: $e');
    }
    // Keep the file in step: drop the token when it's in the keychain or
    // signed out, so a stale one never outlives the session.
    final tokens = await _readFile();
    final had = tokens.containsKey(key);
    if (token != null && !saved) {
      tokens[key] = token;
    } else {
      tokens.remove(key);
    }
    if (had || tokens.containsKey(key)) await _writeFile(tokens);
  }

  Future<File?> _file() async {
    try {
      return File('${(await getApplicationSupportDirectory()).path}/session-tokens.json');
    } catch (e) {
      debugPrint('no app support folder, token not persisted: $e');
      return null;
    }
  }

  Future<Map<String, String>> _readFile() async {
    try {
      final f = await _file();
      if (f == null || !await f.exists()) return {};
      return (jsonDecode(await f.readAsString()) as Map<String, dynamic>).cast<String, String>();
    } catch (e) {
      debugPrint('token file unreadable: $e');
      return {};
    }
  }

  Future<void> _writeFile(Map<String, String> tokens) async {
    try {
      final f = await _file();
      if (f == null) return;
      await f.parent.create(recursive: true);
      // Create it private before the token goes in.
      if (!await f.exists()) {
        await f.create();
        if (!Platform.isWindows) await Process.run('chmod', ['600', f.path]);
      }
      await f.writeAsString(jsonEncode(tokens), flush: true);
    } catch (e) {
      debugPrint('token not persisted: $e');
    }
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);

class SessionNotifier extends Notifier<SessionState> {
  final _tokens = _TokenStore();

  @override
  SessionState build() {
    Future.microtask(_restore);
    return const SessionState(phase: SessionPhase.loading);
  }

  String get _deviceName => 'notes-app desktop (${Platform.localHostname})';

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('serverUrl');
    if (url == null) {
      state = const SessionState(phase: SessionPhase.connect, serverUrl: defaultServerUrl);
      return;
    }
    await connect(url, remember: false);
  }

  ApiClient _client(String url, String? token) => ApiClient(Uri.parse(url), token: token)..onUnauthorized = _onUnauthorized;

  /// Checks the server and moves to setup, sign-in, or straight to ready if a
  /// saved token still works.
  Future<void> connect(String rawUrl, {bool remember = true}) async {
    final url = normalizeServerUrl(rawUrl);
    if (url == null) {
      state = SessionState(phase: SessionPhase.connect, serverUrl: rawUrl, error: 'Enter an address like http://localhost:8080');
      return;
    }
    state = SessionState(phase: SessionPhase.loading, serverUrl: url);
    final anon = _client(url, null);
    try {
      final status = await anon.authStatus();
      if (remember) await (await SharedPreferences.getInstance()).setString('serverUrl', url);
      if (status.setupRequired) {
        state = SessionState(phase: SessionPhase.setup, api: anon, serverUrl: url);
        return;
      }
      final token = await _tokens.read(url);
      if (token != null) {
        final authed = _client(url, token);
        try {
          await authed.sources(); // cheap check that the token is still valid
          state = SessionState(phase: SessionPhase.ready, api: authed, serverUrl: url, passwordFromEnv: status.passwordFromEnv);
          return;
        } on ApiException catch (e) {
          if (!e.isUnauthorized) rethrow;
          await _tokens.write(url, null);
        }
      }
      state = SessionState(phase: SessionPhase.signIn, api: anon, serverUrl: url, passwordFromEnv: status.passwordFromEnv);
    } on ApiException catch (e) {
      state = SessionState(phase: SessionPhase.connect, serverUrl: url, error: e.message);
    }
  }

  Future<void> setup(String code, String password) async {
    final api = state.api!;
    try {
      final token = await api.setup(code.trim(), password, _deviceName);
      await _signedIn(token);
    } on ApiException catch (e) {
      state = state.copyWith(error: e.message);
    }
  }

  Future<void> signIn(String password) async {
    final api = state.api!;
    state = state.copyWith(clearError: true);
    try {
      final token = await api.login(password, _deviceName);
      await _signedIn(token);
    } on ApiException catch (e) {
      final msg = switch (e.code) {
        'INVALID_PASSWORD' => 'Wrong password.',
        'RATE_LIMITED' => 'Too many attempts, try again in ${e.details['retryAfterSeconds']}s.',
        _ => e.message,
      };
      state = state.copyWith(error: msg);
    }
  }

  Future<void> _signedIn(String token) async {
    final url = state.serverUrl!;
    await _tokens.write(url, token);
    state = SessionState(phase: SessionPhase.ready, api: _client(url, token), serverUrl: url, passwordFromEnv: state.passwordFromEnv);
  }

  Future<void> signOut() async {
    final api = state.api;
    try {
      await api?.logout();
    } on ApiException {
      // Signing out locally is what matters; the token may already be gone.
    }
    await _tokens.write(state.serverUrl!, null);
    state = SessionState(phase: SessionPhase.signIn, api: _client(state.serverUrl!, null), serverUrl: state.serverUrl);
  }

  void changeServer() {
    state = SessionState(phase: SessionPhase.connect, serverUrl: state.serverUrl);
  }

  void _onUnauthorized() {
    if (state.phase != SessionPhase.ready) return;
    _tokens.write(state.serverUrl!, null);
    state = SessionState(
      phase: SessionPhase.signIn,
      api: _client(state.serverUrl!, null),
      serverUrl: state.serverUrl,
      error: 'Your session ended. Sign in again.',
    );
  }
}

/// Accepts "localhost:8080" or a full URL; returns null if it can't be a server address.
String? normalizeServerUrl(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (!s.contains('://')) s = 'http://$s';
  final uri = Uri.tryParse(s);
  if (uri == null || uri.host.isEmpty || !(uri.scheme == 'http' || uri.scheme == 'https')) return null;
  return Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null).toString();
}
