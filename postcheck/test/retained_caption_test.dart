import 'package:flutter_test/flutter_test.dart';
import 'package:postcheck/application/retained_caption.dart';
import 'package:postcheck/application/review.dart';
import 'package:postcheck/domain/models.dart';

void main() {
  test('restores one hidden range without rolling back surrounding text', () {
    final caption = RetainedCaption('前 A 後');
    caption.hide({'a': const TextSpanRange(2, 3)}, marker: '[H]');
    expect(caption.text, '前 [H] 後');
    caption.revise('追加 前 [H] 後');
    caption.revise('追加 前 [H] 後の編集');
    expect(caption.canRestore('a'), isTrue);
    expect(caption.restore('a'), isTrue);
    expect(caption.text, '追加 前 A 後の編集');
    expect(caption.canRestore('a'), isFalse);
  });

  test(
    'editing a marker invalidates its undo without changing later edits',
    () {
      final caption = RetainedCaption('before secret after');
      caption.hide({'secret': const TextSpanRange(7, 13)}, marker: '[Hidden]');
      caption.revise('before [Edited] after');
      expect(caption.canRestore('secret'), isFalse);
      expect(caption.restore('secret'), isFalse);
      expect(caption.text, 'before [Edited] after');
    },
  );

  test('overlap keeps every other owner hidden when one owner is restored', () {
    final caption = RetainedCaption('0123456789');
    caption.hide({
      'a': const TextSpanRange(1, 5),
      'b': const TextSpanRange(3, 7),
    }, marker: '[H]');
    expect(caption.text, '0[H]789');
    expect(caption.restore('a'), isTrue);
    expect(caption.text, '012[H]789');
    expect(caption.canRestore('b'), isTrue);
    expect(caption.restore('b'), isTrue);
    expect(caption.text, '0123456789');
  });

  test(
    'touching ranges merge exactly as redactCaption and restore separately',
    () {
      final caption = RetainedCaption('0123456789');
      final ranges = {
        'a': const TextSpanRange(1, 3),
        'b': const TextSpanRange(3, 5),
        'c': const TextSpanRange(7, 9),
      };
      caption.hide(ranges, marker: '[H]');
      expect(
        caption.text,
        redactCaption('0123456789', ranges.values, marker: '[H]'),
      );
      expect(caption.restore('b'), isTrue);
      expect(caption.text, '0[H]3456[H]9');
      expect(caption.restore('c'), isTrue);
      expect(caption.text, '0[H]3456789');
      expect(caption.restore('a'), isTrue);
      expect(caption.text, '0123456789');
    },
  );

  test('repeated hide commits preserve the unaffected earlier history', () {
    final caption = RetainedCaption('A B C');
    caption.hide({'a': const TextSpanRange(0, 1)}, marker: '[H]');
    caption.hide({'c': const TextSpanRange(6, 7)}, marker: '[H]');
    expect(caption.text, '[H] B [H]');
    expect(caption.restore('a'), isTrue);
    expect(caption.text, 'A B [H]');
    expect(caption.restore('c'), isTrue);
    expect(caption.text, 'A B C');
  });

  test('hiding across an existing marker never reveals the nested secret', () {
    final caption = RetainedCaption('A secret Z');
    caption.hide({'inner': const TextSpanRange(2, 8)}, marker: '[H]');
    expect(caption.text, 'A [H] Z');
    caption.hide({'outer': const TextSpanRange(0, 5)}, marker: '[H]');
    expect(caption.text, '[H] Z');
    expect(caption.canRestore('inner'), isFalse);
    expect(caption.restore('outer'), isTrue);
    expect(caption.text, 'A [H] Z');
    expect(caption.restore('inner'), isFalse);
  });

  test(
    'duplicate literal marker text is never mistaken for the hidden owner',
    () {
      final caption = RetainedCaption('[H] A [H]');
      caption.hide({'a': const TextSpanRange(4, 5)}, marker: '[H]');
      expect(caption.text, '[H] [H] [H]');
      expect(caption.restore('a'), isTrue);
      expect(caption.text, '[H] A [H]');
    },
  );

  test(
    'ambiguous deletion of identical markers invalidates possible owners',
    () {
      final caption = RetainedCaption('A A');
      caption.hide({
        'first': const TextSpanRange(0, 1),
        'last': const TextSpanRange(2, 3),
      }, marker: '[H]');
      caption.revise('[H]');
      expect(caption.restore('first'), isFalse);
      expect(caption.restore('last'), isFalse);
      expect(caption.text, '[H]');
    },
  );

  test(
    'emoji ranges use valid UTF-16 boundaries and preserve later emoji edits',
    () {
      final caption = RetainedCaption('前😀機密🚀後');
      caption.hide({'secret': const TextSpanRange(3, 5)}, marker: '［非表示］');
      expect(caption.text, '前😀［非表示］🚀後');
      caption.revise('前😁［非表示］🚀後');
      expect(caption.restore('secret'), isTrue);
      expect(caption.text, '前😁機密🚀後');
    },
  );

  test('invalid surrogate-splitting and out-of-bounds hides are ignored', () {
    final caption = RetainedCaption('前😀後');
    caption.hide({
      'split': const TextSpanRange(1, 2),
      'outside': const TextSpanRange(4, 5),
    }, marker: '[H]');
    expect(caption.text, '前😀後');
    expect(caption.restore('split'), isFalse);
    expect(caption.restore('outside'), isFalse);
  });

  test('insertion at marker boundaries remains outside the hidden text', () {
    final caption = RetainedCaption('A secret Z');
    caption.hide({'secret': const TextSpanRange(2, 8)}, marker: '[H]');
    caption.revise('A added[H] Z');
    caption.revise('A added[H]after Z');
    expect(caption.restore('secret'), isTrue);
    expect(caption.text, 'A addedsecretafter Z');
  });

  test('an empty marker is restorable until an edit touches its position', () {
    final caption = RetainedCaption('A secret Z');
    caption.hide({'secret': const TextSpanRange(2, 8)}, marker: '');
    expect(caption.text, 'A  Z');
    expect(caption.restore('secret'), isTrue);
    expect(caption.text, 'A secret Z');
    caption.hide({'secret': const TextSpanRange(2, 8)}, marker: '');
    caption.revise('A ! Z');
    expect(caption.restore('secret'), isFalse);
    expect(caption.text, 'A ! Z');
  });

  test('editing a restored overlap leaves another owner restorable', () {
    final caption = RetainedCaption('0123456789');
    caption.hide({
      'a': const TextSpanRange(1, 5),
      'b': const TextSpanRange(3, 7),
    }, marker: '[H]');
    expect(caption.restore('a'), isTrue);
    caption.revise('0AB[H]789');
    expect(caption.restore('b'), isTrue);
    expect(caption.text, '0AB3456789');
  });

  test(
    'restoring a bridge splits remaining owners into independent histories',
    () {
      final caption = RetainedCaption('0123456789');
      caption.hide({
        'a': const TextSpanRange(1, 3),
        'bridge': const TextSpanRange(2, 7),
        'b': const TextSpanRange(6, 8),
      }, marker: '[H]');
      expect(caption.restore('bridge'), isTrue);
      expect(caption.text, '0[H]345[H]89');
      caption.revise('0[H]XYZ[H]89');
      expect(caption.restore('b'), isTrue);
      expect(caption.text, '0[H]XYZ6789');
      expect(caption.restore('a'), isTrue);
      expect(caption.text, '012XYZ6789');
    },
  );
}
