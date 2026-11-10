import 'dart:convert';
import 'package:http/http.dart' as http;
import 'contracts.dart';

final class RulesApiException implements Exception {
  const RulesApiException(this.status);
  final int status;
  String get message => switch (status) {
    400 => '入力内容・公開範囲の確認を見直してください。',
    401 => 'ログインし直してください。',
    403 => 'この操作の権限がありません。',
    409 => '状態が更新されたか、最後の責任者を取り消そうとしています。一覧と権限を確認してください。',
    412 => '施設責任者の確認・有効な招待を先に完了してください。',
    _ => '接続できませんでした。入力を保持したまま再試行できます。',
  };
}

final class RulesApi implements VenueRepositoryPort {
  RulesApi({required this.baseUrl, this.token, http.Client? client})
    : _client = client ?? http.Client() {
    final u = Uri.parse(baseUrl);
    if (baseUrl.isNotEmpty &&
        u.scheme != 'https' &&
        !(u.scheme == 'http' &&
            ['localhost', '127.0.0.1', '10.0.2.2'].contains(u.host))) {
      throw ArgumentError('HTTPS endpoint required');
    }
  }
  final String baseUrl;
  final Future<String?> Function()? token;
  final http.Client _client;
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
  }) async {
    final t = await token?.call();
    final req = http.Request(method, Uri.parse('$baseUrl$path'))
      ..followRedirects = false
      ..headers['Content-Type'] = 'application/json';
    if (t != null) req.headers['Authorization'] = 'Bearer $t';
    if (body != null) req.body = jsonEncode(body);
    try {
      final res = await _client.send(req).timeout(const Duration(seconds: 20));
      if (res.statusCode < 200 || res.statusCode >= 300)
        throw RulesApiException(res.statusCode);
      final bytes = <int>[];
      await for (final chunk in res.stream.timeout(
        const Duration(seconds: 20),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > 2000000) throw const RulesApiException(413);
      }
      return jsonDecode(utf8.decode(bytes));
    } on RulesApiException {
      rethrow;
    } catch (_) {
      throw const RulesApiException(503);
    }
  }

  @override
  Future<List<PublishedVenue>> list() async =>
      (await request('/v1/venues') as List)
          .map((j) => PublishedVenue.fromJson(j))
          .toList();
  Future<Map<String, dynamic>> session() async =>
      Map<String, dynamic>.from(await request('/v1/session'));
  Future<List<ManagedVenue>> managed() async =>
      (await request('/v1/admin/venues') as List)
          .map((j) => ManagedVenue.fromJson(j))
          .toList();
  Future<ManagedVenue> save(VenuePolicy p, {ManagedVenue? existing}) async =>
      ManagedVenue.fromJson(
        await request(
          '/v1/admin/venues${existing == null ? '' : '/${existing.id}'}',
          method: existing == null ? 'POST' : 'PUT',
          body: {'policy': p.toJson(), 'version': existing?.version ?? 0},
        ),
      );
  Future<ManagedVenue> change(
    ManagedVenue v,
    String action, {
    String reason = '',
    bool publicAcknowledged = false,
  }) async => ManagedVenue.fromJson(
    await request(
      '/v1/admin/venues/${v.id}/$action',
      method: 'POST',
      body: {
        'version': v.version,
        'reason': reason,
        'publicAcknowledged': publicAcknowledged,
      },
    ),
  );
  Future<Map<String, dynamic>> access(String id) async =>
      Map<String, dynamic>.from(await request('/v1/access/venues/$id'));
  Future<List<Map<String, dynamic>>> accessRequests() async =>
      (await request('/v1/access/requests') as List)
          .map((v) => Map<String, dynamic>.from(v))
          .toList();
  Future<Map<String, dynamic>> requestVerification(String id) async =>
      Map<String, dynamic>.from(
        await request(
          '/v1/access/requests',
          method: 'POST',
          body: {'venueId': id},
        ),
      );
  Future<Map<String, dynamic>> issueVerification(
    String id,
    String officialUrl,
  ) async => Map<String, dynamic>.from(
    await request(
      '/v1/access/requests/$id/issue',
      method: 'POST',
      body: {'officialSourceUrl': officialUrl, 'confirmed': true},
    ),
  );
  Future<Map<String, dynamic>> invite(String id, String role) async =>
      Map<String, dynamic>.from(
        await request(
          '/v1/access/venues/$id/invite',
          method: 'POST',
          body: {'role': role},
        ),
      );
  Future<Map<String, dynamic>> revoke(String id, String uid) async =>
      Map<String, dynamic>.from(
        await request(
          '/v1/access/venues/$id/revoke',
          method: 'POST',
          body: {'uid': uid},
        ),
      );
  Future<Map<String, dynamic>> previewAccess(String raw) async =>
      Map<String, dynamic>.from(
        await request(
          '/v1/access/preview',
          method: 'POST',
          body: {'token': raw},
        ),
      );
  Future<Map<String, dynamic>> consumeAccess(String raw) async =>
      Map<String, dynamic>.from(
        await request(
          '/v1/access/consume',
          method: 'POST',
          body: {'token': raw, 'confirmed': true},
        ),
      );
  void close() => _client.close();
}
