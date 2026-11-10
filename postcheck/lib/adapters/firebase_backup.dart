import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import '../domain/cloud_backup.dart';

/// Firebase is initialized only when the user explicitly opens a login flow.
/// This adapter never receives DraftInput, images or findings.
final class FirebaseBackupAdapter implements CloudBackupPort {
  FirebaseBackupAdapter({http.Client? client})
    : _client = client ?? http.Client();
  final http.Client _client;
  static const endpoint = String.fromEnvironment('POSTCHECK_BACKUP_URL');
  static const project = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const sender = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const googleClient = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
  FirebaseAuth? _auth;
  bool _googleInitialized = false;
  @override
  bool get configured =>
      endpoint.startsWith('https://') &&
      [project, apiKey, appId, sender, googleClient].every((v) => v.isNotEmpty);
  @override
  bool get signedIn => _auth?.currentUser != null;
  Future<String?> ruleToken() async => _auth?.currentUser?.getIdToken();
  Future<void> _initialize() async {
    if (!configured) throw const FormatException('クラウドは未接続です。端末内の機能は利用できます。');
    if (_auth != null) return;
    final app = Firebase.apps.isEmpty
        ? await Firebase.initializeApp(
            options: const FirebaseOptions(
              apiKey: apiKey,
              appId: appId,
              messagingSenderId: sender,
              projectId: project,
              iosBundleId: 'jp.kawakou.postcheck',
              iosClientId: googleClient,
            ),
          )
        : Firebase.app();
    _auth = FirebaseAuth.instanceFor(app: app);
  }

  @override
  Future<void> signIn(LoginProvider provider) async {
    await _initialize();
    if (provider == LoginProvider.apple) {
      await _auth!.signInWithProvider(AppleAuthProvider());
      return;
    }
    if (!_googleInitialized) {
      await GoogleSignIn.instance.initialize(clientId: googleClient);
      _googleInitialized = true;
    }
    final account = await GoogleSignIn.instance.authenticate();
    await _auth!.signInWithCredential(
      GoogleAuthProvider.credential(idToken: account.authentication.idToken),
    );
  }

  @override
  Future<void> signOut() async {
    await _auth?.signOut();
    if (_googleInitialized) await GoogleSignIn.instance.signOut();
  }

  Future<http.Response> _request(
    String method, {
    String? body,
    String? revision,
  }) async {
    final user = _auth?.currentUser;
    if (user == null) throw const FormatException('ログインしてください。');
    final token = await user.getIdToken();
    if (token == null) throw const FormatException('もう一度ログインしてください。');
    final request = http.Request(method, Uri.parse('$endpoint/v1/backup'))
      ..followRedirects = false
      ..headers.addAll({
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'If-Match': ?revision,
        if (method == 'PUT' && revision == null) 'If-None-Match': '*',
      });
    if (body != null) request.body = body;
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 30));
    if (response.bodyBytes.length > 262144) {
      throw const FormatException('復元データが上限を超えています。');
    }
    if (response.statusCode == 409) {
      throw const FormatException('別の端末で更新されました。クラウドの状態を再取得してください。');
    }
    if (response.statusCode == 401) {
      throw const FormatException('ログインの有効期限を確認できません。再ログインしてください。');
    }
    if (response.statusCode != 404 &&
        (response.statusCode < 200 || response.statusCode >= 300)) {
      throw const FormatException('クラウド処理を完了できませんでした。接続・設定を確認してください。');
    }
    return response;
  }

  @override
  Future<CloudSnapshot?> fetch() async {
    final response = await _request('GET');
    if (response.statusCode == 404) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return CloudSnapshot(
      payload: jsonEncode(data['payload']),
      revision: data['revision'] as String,
      updatedAt: DateTime.parse(data['updatedAt'] as String),
    );
  }

  @override
  Future<void> save(String payload, {String? expectedRevision}) async {
    final response = await _request(
      'PUT',
      body: payload,
      revision: expectedRevision,
    );
    if (response.statusCode != 200) throw const FormatException('保存できませんでした。');
  }

  @override
  Future<void> delete(String expectedRevision) async {
    final response = await _request('DELETE', revision: expectedRevision);
    if (response.statusCode != 204 && response.statusCode != 404) {
      throw const FormatException('削除できませんでした。');
    }
  }
}
