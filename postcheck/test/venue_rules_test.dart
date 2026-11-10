import 'package:flutter_test/flutter_test.dart';
import 'package:postcheck/application/check_draft.dart';
import 'package:postcheck/domain/models.dart';
import 'package:postcheck_rules/contracts.dart';

void main() {
  test(
    'venue matching links image and caption to source without changing local dictionary',
    () {
      final venue = PublishedVenue(
        id: 'v',
        version: 7,
        updatedAt: DateTime.utc(2026),
        policy: VenuePolicy(
          name: '架空施設',
          words: ['試作A'],
          sourceText: '架空の掲載条件',
          releaseAt: DateTime.now().add(const Duration(days: 1)),
        ),
      );
      final result = RuleChecker(venue: venue).check(
        const DraftInput(caption: '試作Aを見ました'),
        const Observations(
          blocks: [
            TextBlock(
              id: 'label',
              text: '展示 試作A',
              region: ImageRegion(.1, .1, .2, .1),
            ),
          ],
        ),
      );
      expect(
        result.where((f) => f.ruleEvidence?.contains('v7') ?? false).length,
        2,
      );
      expect(result.any((f) => f.target is CaptionTarget), true);
      expect(result.any((f) => f.target is PhotoTarget), true);
    },
  );
  test('expired venue does not create word rules', () {
    final venue = PublishedVenue(
      id: 'v',
      version: 1,
      updatedAt: DateTime.utc(2020),
      policy: VenuePolicy(
        name: 'expired',
        words: ['試作A'],
        validUntil: DateTime.utc(2020),
      ),
    );
    expect(
      RuleChecker(
        venue: venue,
      ).check(const DraftInput(caption: '試作A'), const Observations()),
      isEmpty,
    );
  });
}
