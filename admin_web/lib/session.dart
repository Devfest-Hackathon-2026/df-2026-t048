import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:postcheck_rules/postcheck_rules.dart';

class AdminSession {
  AdminSession({required this.demo})
    : api = RulesApi(baseUrl: const String.fromEnvironment('RULE_API_URL'));
  final bool demo;
  RulesApi api;
  Map<String, dynamic>? actor;
  bool get operator => actor?['operator'] == true;
  Future<void> login({bool asOperator = false, bool asStaff = false}) async {
    if (demo) {
      if (!['localhost', '127.0.0.1'].contains(Uri.base.host)) {
        throw const RulesApiException(403);
      }
      api.close();
      api = RulesApi(
        baseUrl: const String.fromEnvironment(
          'RULE_API_URL',
          defaultValue: 'http://127.0.0.1:8787',
        ),
        token: () async => asOperator
            ? 'postcheck-demo-operator'
            : asStaff
            ? 'postcheck-demo-staff'
            : 'postcheck-demo-org',
      );
    } else {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
            appId: String.fromEnvironment('FIREBASE_WEB_APP_ID'),
            messagingSenderId: String.fromEnvironment(
              'FIREBASE_MESSAGING_SENDER_ID',
            ),
            projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
            authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
          ),
        );
      }
      await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      api.close();
      api = RulesApi(
        baseUrl: const String.fromEnvironment('RULE_API_URL'),
        token: () async => FirebaseAuth.instance.currentUser?.getIdToken(),
      );
    }
    actor = await api.session();
  }

  Future<void> logout() async {
    actor = null;
    if (!demo && Firebase.apps.isNotEmpty) {
      await FirebaseAuth.instance.signOut();
    }
    api.close();
    api = RulesApi(baseUrl: const String.fromEnvironment('RULE_API_URL'));
  }
}
