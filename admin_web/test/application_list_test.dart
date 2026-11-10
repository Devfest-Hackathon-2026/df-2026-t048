import 'package:flutter_test/flutter_test.dart';
import 'package:postcheck_rules/postcheck_rules.dart';

void main() {
  test('applicationTitle prefers applicationName over facility name', () {
    final withTitle = ManagedVenue.fromJson({
      'id': 'a',
      'org': 'demo',
      'version': 1,
      'status': 'draft',
      'draft': const VenuePolicy(
        name: '架空アリーナ',
        applicationName: '春の展示ルール申請',
      ).toJson(),
      'publishedVersion': 0,
    });
    expect(withTitle.applicationTitle, '春の展示ルール申請');
    expect(withTitle.statusLabel, '下書き');

    final legacy = ManagedVenue.fromJson({
      'id': 'b',
      'org': 'demo',
      'version': 1,
      'status': 'pending',
      'draft': const VenuePolicy(name: '架空ホール').toJson(),
      'publishedVersion': 0,
    });
    expect(legacy.applicationTitle, '架空ホール');
    expect(legacy.statusLabel, '審査中');
  });
}
