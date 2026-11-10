import 'package:flutter_test/flutter_test.dart';
import 'package:postcheck/application/check_draft.dart';
import 'package:postcheck/application/review.dart';
import 'package:postcheck/domain/models.dart';

void main() {
  test(
    'translated markers redact only selected ranges without translating user text',
    () {
      for (final code in ['ja', 'en']) {
        const caption = '🎨 联系方式 test@example.com 연락처';
        final found = const RuleChecker().check(
          const DraftInput(caption: caption),
          const Observations(),
        );
        final result = selectedCaption(caption, found, {
          found.single.id: ReviewDecision.hide,
        }, marker: redactionMarkerFor(code));
        expect(result, '🎨 联系方式 ${redactionMarkerFor(code)} 연락처');
      }
    },
  );
}
