import '../domain/models.dart';

String redactionMarkerFor(String languageCode) => switch (languageCode) {
  'en' => '[Hidden]',
  _ => '［非表示］',
};

String redactCaption(
  String caption,
  Iterable<TextSpanRange> ranges, {
  String marker = '［非表示］',
}) {
  final sorted = ranges.where((r) => r.validFor(caption)).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  final merged = <TextSpanRange>[];
  for (final range in sorted) {
    if (merged.isNotEmpty && range.start <= merged.last.end) {
      final previous = merged.removeLast();
      merged.add(
        TextSpanRange(
          previous.start,
          range.end > previous.end ? range.end : previous.end,
        ),
      );
    } else {
      merged.add(range);
    }
  }
  var result = caption;
  for (final range in merged.reversed) {
    result = result.replaceRange(range.start, range.end, marker);
  }
  return result;
}

List<ImageRegion> selectedRegions(
  List<Finding> findings,
  Map<String, ReviewDecision> decisions,
  List<ImageRegion> manual,
) => [
  ...findings
      .where((f) => decisions[f.id] == ReviewDecision.hide)
      .map((f) => f.target)
      .whereType<PhotoTarget>()
      .map((t) => t.region),
  ...manual.where((r) => r.isValid),
];

String selectedCaption(
  String original,
  List<Finding> findings,
  Map<String, ReviewDecision> decisions, {
  String marker = '［非表示］',
}) => redactCaption(
  original,
  findings
      .where((f) => decisions[f.id] == ReviewDecision.hide)
      .map((f) => f.target)
      .whereType<CaptionTarget>()
      .map((t) => t.range),
  marker: marker,
);
