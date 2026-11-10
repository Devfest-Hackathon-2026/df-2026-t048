import 'dart:math' as math;

import '../domain/models.dart';
import 'review.dart';

/// Retains the provenance of hidden text without rolling back later edits.
/// Positions refer to UTF-16 offsets, as do [TextSpanRange] and Dart strings.
final class RetainedCaption {
  RetainedCaption(String initial) : _text = initial;

  String _text;
  final List<_HiddenGroup> _groups = [];

  String get text => _text;

  /// Keeps history only where a single changed interval can be mapped safely.
  /// Edits intersecting a replacement invalidate its history, not its text.
  void revise(String value) {
    if (value == _text) return;
    final before = _text;
    final limit = math.min(before.length, value.length);
    var prefix = 0;
    while (prefix < limit &&
        before.codeUnitAt(prefix) == value.codeUnitAt(prefix)) {
      prefix++;
    }
    while (prefix > 0 &&
        (!_boundary(before, prefix) || !_boundary(value, prefix))) {
      prefix--;
    }
    var suffix = 0;
    while (suffix < limit &&
        before.codeUnitAt(before.length - suffix - 1) ==
            value.codeUnitAt(value.length - suffix - 1)) {
      suffix++;
    }
    while (suffix > 0 &&
        (!_boundary(before, before.length - suffix) ||
            !_boundary(value, value.length - suffix))) {
      suffix--;
    }

    // Repeated text can admit several equally valid edit locations. Include
    // all of them when invalidating histories rather than guessing an owner.
    final earliest = math.min(
      prefix,
      math.min(before.length - suffix, value.length - suffix),
    );
    final disjointSuffix = math.min(suffix, limit - prefix);
    final oldEnd = before.length - disjointSuffix;
    final delta = value.length - before.length;
    _groups.removeWhere((group) {
      if (group.start == group.end &&
          group.start >= earliest &&
          group.start <= oldEnd) {
        return true;
      }
      if (group.end <= earliest) return false;
      if (group.start >= oldEnd) {
        group.start += delta;
        return false;
      }
      return true;
    });
    _text = value;
  }

  /// Hides valid ranges in the current text, matching [redactCaption].
  /// An existing hidden replacement inside a new hide remains opaque: its
  /// history is discarded, so restoring the new hide cannot reveal that text.
  void hide(Map<String, TextSpanRange> ranges, {required String marker}) {
    final valid =
        ranges.entries.where((entry) => entry.value.validFor(_text)).toList()
          ..sort((a, b) => a.value.start.compareTo(b.value.start));
    final pending = <_HideRange>[];
    for (final entry in valid) {
      final range = entry.value;
      if (pending.isNotEmpty && range.start <= pending.last.end) {
        final group = pending.last;
        group.end = math.max(group.end, range.end);
        group.owners[entry.key] = range;
      } else {
        pending.add(_HideRange(range.start, range.end, {entry.key: range}));
      }
    }
    // Apply from right to left so input coordinates stay valid. Each change
    // also rebases the unaffected histories to their new output positions.
    for (final range in pending.reversed) {
      final owners = range.owners.map(
        (key, span) => MapEntry(
          key,
          TextSpanRange(span.start - range.start, span.end - range.start),
        ),
      );
      final source = _text.substring(range.start, range.end);
      _groups.removeWhere(
        (group) =>
            group.owners.keys.any(owners.containsKey) ||
            _intersects(group, range.start, range.end),
      );
      final delta = marker.length - (range.end - range.start);
      for (final group in _groups) {
        if (group.start >= range.end) group.start += delta;
      }
      _text = _text.replaceRange(range.start, range.end, marker);
      _groups.add(_HiddenGroup(range.start, source, marker, owners));
    }
  }

  bool canRestore(String key) {
    final matching = _groups.where((group) => group.owners.containsKey(key));
    if (matching.length != 1) return false;
    final group = matching.single;
    return group.start >= 0 &&
        group.end <= _text.length &&
        _text.substring(group.start, group.end) == group.rendered;
  }

  /// Restores only this owner's range; overlapping owners remain hidden.
  /// False leaves both the text and every retained history unchanged.
  bool restore(String key) {
    if (!canRestore(key)) return false;
    final group = _groups.singleWhere((g) => g.owners.containsKey(key));
    final end = group.end;
    final remaining = Map<String, TextSpanRange>.of(group.owners)..remove(key);
    final replacement = redactCaption(
      group.source,
      remaining.values,
      marker: group.marker,
    );
    final delta = replacement.length - group.rendered.length;
    _text = _text.replaceRange(group.start, end, replacement);
    for (final other in _groups) {
      if (!identical(other, group) && other.start >= end) {
        other.start += delta;
      }
    }
    _groups.remove(group);
    // Removing a bridging owner can split one merged replacement into several
    // markers. Keep only those markers in history, so later edits to newly
    // visible text do not invalidate an unrelated remaining owner.
    final entries = remaining.entries.toList()
      ..sort((a, b) => a.value.start.compareTo(b.value.start));
    final chunks = <_HideRange>[];
    for (final entry in entries) {
      final span = entry.value;
      if (chunks.isNotEmpty && span.start <= chunks.last.end) {
        chunks.last.end = math.max(chunks.last.end, span.end);
        chunks.last.owners[entry.key] = span;
      } else {
        chunks.add(_HideRange(span.start, span.end, {entry.key: span}));
      }
    }
    var shift = 0;
    for (final chunk in chunks) {
      _groups.add(
        _HiddenGroup(
          group.start + chunk.start + shift,
          group.source.substring(chunk.start, chunk.end),
          group.marker,
          chunk.owners.map(
            (owner, span) => MapEntry(
              owner,
              TextSpanRange(span.start - chunk.start, span.end - chunk.start),
            ),
          ),
        ),
      );
      shift += group.marker.length - (chunk.end - chunk.start);
    }
    return true;
  }

  static bool _intersects(_HiddenGroup group, int start, int end) =>
      group.start == group.end
      ? group.start >= start && group.start < end
      : group.start < end && group.end > start;

  static bool _boundary(String value, int at) =>
      at == 0 ||
      at == value.length ||
      !(value.codeUnitAt(at - 1) >= 0xD800 &&
          value.codeUnitAt(at - 1) <= 0xDBFF &&
          value.codeUnitAt(at) >= 0xDC00 &&
          value.codeUnitAt(at) <= 0xDFFF);
}

final class _HideRange {
  _HideRange(this.start, this.end, this.owners);
  final int start;
  int end;
  final Map<String, TextSpanRange> owners;
}

final class _HiddenGroup {
  _HiddenGroup(this.start, this.source, this.marker, this.owners);
  int start;
  final String source;
  final String marker;
  final Map<String, TextSpanRange> owners;
  String get rendered => redactCaption(source, owners.values, marker: marker);
  int get end => start + rendered.length;
}
