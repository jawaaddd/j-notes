import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';

/// An error response from the API: {"error": {"code", "message", "details"}}.
class ApiException implements Exception {
  ApiException(this.status, this.code, this.message, [this.details = const {}]);

  final int status;
  final String code;
  final String message;
  final Map<String, dynamic> details;

  bool get isUnauthorized => status == 401 && code == 'UNAUTHORIZED';

  @override
  String toString() => message;
}

/// Thin HTTP client for the notes-app API. One instance per server + token.
class ApiClient {
  ApiClient(this.baseUrl, {this.token, http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final Uri baseUrl;
  final String? token;
  final http.Client _http;

  /// Called when an authenticated request gets a 401, so the app can return
  /// to the sign-in screen.
  void Function()? onUnauthorized;

  ApiClient withToken(String? token) => ApiClient(baseUrl, token: token, httpClient: _http)..onUnauthorized = onUnauthorized;

  String get host => baseUrl.hasPort ? '${baseUrl.host}:${baseUrl.port}' : baseUrl.host;

  Future<dynamic> _send(String method, String path, {Object? body, Map<String, String>? query}) async {
    final uri = baseUrl.replace(path: path, queryParameters: query);
    final req = http.Request(method, uri);
    req.headers['Accept'] = 'application/json';
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 15)));
    } on SocketException catch (e) {
      throw ApiException(0, 'OFFLINE', "Can't reach the server at $host (${e.osError?.message ?? e.message})");
    } on http.ClientException catch (e) {
      throw ApiException(0, 'OFFLINE', "Can't reach the server at $host (${e.message})");
    }
    if (res.statusCode == 204 || res.body.isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw ApiException(res.statusCode, 'BAD_RESPONSE', 'The server sent something that isn\'t JSON. Is this a notes-app server?');
    }
    if (res.statusCode >= 400) {
      final err = (decoded is Map ? decoded['error'] : null) as Map<String, dynamic>?;
      final ex = ApiException(
        res.statusCode,
        err?['code'] as String? ?? 'HTTP_${res.statusCode}',
        err?['message'] as String? ?? 'Request failed (${res.statusCode})',
        (err?['details'] as Map<String, dynamic>?) ?? const {},
      );
      if (ex.isUnauthorized && token != null) onUnauthorized?.call();
      throw ex;
    }
    return decoded;
  }

  Map<String, dynamic> _map(Object? v) => v as Map<String, dynamic>;
  List<T> _list<T>(Object? v, T Function(Map<String, dynamic>) f) => [for (final x in v as List) f(x as Map<String, dynamic>)];

  // ---- auth ----

  Future<AuthStatus> authStatus() async => AuthStatus.fromJson(_map(await _send('GET', '/api/auth/status')));

  Future<String> login(String password, String deviceName) async =>
      _map(await _send('POST', '/api/auth/login', body: {'password': password, 'deviceName': deviceName}))['token'] as String;

  Future<String> setup(String code, String password, String deviceName) async =>
      _map(await _send('POST', '/api/auth/setup', body: {'setupCode': code, 'password': password, 'deviceName': deviceName}))['token']
          as String;

  Future<void> logout() => _send('POST', '/api/auth/logout');

  Future<void> changePassword(String current, String next) =>
      _send('PUT', '/api/auth/password', body: {'currentPassword': current, 'newPassword': next});

  Future<List<ApiToken>> tokens() async => _list(await _send('GET', '/api/tokens'), ApiToken.fromJson);

  /// Returns the token string, shown to the user once.
  Future<String> createToken(String name) async => _map(await _send('POST', '/api/tokens', body: {'name': name}))['token'] as String;

  Future<void> deleteToken(int id) => _send('DELETE', '/api/tokens/$id');

  // ---- boards, lists, tags ----

  Future<List<Board>> boards() async => _list(await _send('GET', '/api/boards'), Board.fromJson);

  Future<BoardDetail> board(int id) async => BoardDetail.fromJson(_map(await _send('GET', '/api/boards/$id')));

  Future<Board> createBoard(String name) async => Board.fromJson(_map(await _send('POST', '/api/boards', body: {'name': name})));

  /// Fields: name, itemNoun, specialTagLabel, position.
  Future<Board> updateBoard(int id, Map<String, dynamic> fields) async =>
      Board.fromJson(_map(await _send('PATCH', '/api/boards/$id', body: fields)));

  /// Without [cards], a board that still has cards fails with 409
  /// BOARD_HAS_CARDS and `details.cardCount`. [cards] is "delete" or "move".
  Future<void> deleteBoard(int id, {String? cards, int? toBoardId, List<int> applyTagIds = const []}) => _send(
    'DELETE',
    '/api/boards/$id',
    body: {'cards': ?cards, 'toBoardId': ?toBoardId, if (applyTagIds.isNotEmpty) 'applyTagIds': applyTagIds},
  );

  Future<BoardList> createList(int boardId, String name, {ListKind kind = ListKind.open}) async =>
      BoardList.fromJson(_map(await _send('POST', '/api/boards/$boardId/lists', body: {'name': name, 'kind': kind.name})));

  /// Fields: name, kind ("open" or "done").
  Future<BoardList> updateList(int id, Map<String, dynamic> fields) async =>
      BoardList.fromJson(_map(await _send('PATCH', '/api/lists/$id', body: fields)));

  Future<void> reorderLists(int boardId, List<int> listIds) => _send('PUT', '/api/boards/$boardId/lists/order', body: {'listIds': listIds});

  /// Archives every card in the list; returns how many.
  Future<int> archiveList(int id) async => _map(await _send('POST', '/api/lists/$id/archive'))['archived'] as int;

  /// Without [moveToListId], a list with cards fails with 409 LIST_HAS_CARDS.
  Future<void> deleteList(int id, {int? moveToListId}) => _send('DELETE', '/api/lists/$id', body: {'moveToListId': ?moveToListId});

  Future<Tag> createTag(int boardId, String name, String color, {bool isSpecial = false}) async =>
      Tag.fromJson(_map(await _send('POST', '/api/boards/$boardId/tags', body: {'name': name, 'color': color, 'isSpecial': isSpecial})));

  /// Fields: name, color, isSpecial, position.
  Future<Tag> updateTag(int id, Map<String, dynamic> fields) async =>
      Tag.fromJson(_map(await _send('PATCH', '/api/tags/$id', body: fields)));

  Future<void> deleteTag(int id) => _send('DELETE', '/api/tags/$id');

  // ---- cards ----

  Future<List<CardSummary>> cards(int boardId, {DateTime? dueFrom, DateTime? dueTo, bool archived = false, String sort = 'due'}) async {
    final q = <String, String>{'sort': sort};
    if (dueFrom != null) q['dueFrom'] = apiTime(dueFrom);
    if (dueTo != null) q['dueTo'] = apiTime(dueTo);
    if (archived) q['archived'] = 'true';
    return _list(await _send('GET', '/api/boards/$boardId/cards', query: q), CardSummary.fromJson);
  }

  Future<CardDetail> card(int id) async => CardDetail.fromJson(_map(await _send('GET', '/api/cards/$id')));

  Future<CardDetail> createCard(int boardId, Map<String, dynamic> body) async =>
      CardDetail.fromJson(_map(await _send('POST', '/api/boards/$boardId/cards', body: body)));

  /// PATCH with only the fields being changed; pass null to clear a field.
  Future<CardDetail> updateCard(int id, Map<String, dynamic> fields) async =>
      CardDetail.fromJson(_map(await _send('PATCH', '/api/cards/$id', body: fields)));

  Future<CardDetail> markDone(int id) async => CardDetail.fromJson(_map(await _send('POST', '/api/cards/$id/done')));

  Future<void> deleteCard(int id) => _send('DELETE', '/api/cards/$id');

  Future<DateTime> saveNotes(int id, List<NoteBlock> blocks) async {
    final res = _map(
      await _send(
        'PUT',
        '/api/cards/$id/notes',
        body: {
          'blocks': [for (final b in blocks) b.toJson()],
        },
      ),
    );
    return DateTime.parse(res['updatedAt'] as String).toLocal();
  }

  // ---- inbox and sources ----

  Future<InboxList> inbox() async => InboxList.fromJson(_map(await _send('GET', '/api/inbox')));

  Future<void> resolveInbox(int id, String action, {Map<String, dynamic>? edits}) =>
      _send('POST', '/api/inbox/$id/resolve', body: {'action': action, 'edits': ?edits});

  Future<List<Source>> sources() async => _list(await _send('GET', '/api/sources'), Source.fromJson);
}

/// RFC 3339 in UTC, the format the API expects for timestamps.
String apiTime(DateTime t) => '${t.toUtc().toIso8601String().split('.').first}Z';
