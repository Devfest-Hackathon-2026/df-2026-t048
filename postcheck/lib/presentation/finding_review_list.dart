import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../domain/models.dart';
import '../l10n/app_localizations.dart';
import 'apple_components.dart';
import 'app_theme.dart';
import 'postcheck_controller.dart';

/// The same finding IDs/numbers are used in the photo and the vertical list.
class FindingReviewList extends StatefulWidget {
  const FindingReviewList({
    super.key,
    required this.controller,
    required this.findings,
    required this.onMask,
    required this.onVenueDetails,
  });
  final PostCheckController controller;
  final List<Finding> findings;
  final Future<void> Function(Finding) onMask;
  final Future<void> Function() onVenueDetails;
  @override
  State<FindingReviewList> createState() => FindingReviewListState();
}

class FindingReviewListState extends State<FindingReviewList> {
  final _anchors = <String, GlobalKey>{};
  Future<void> reveal(String id) async {
    final target = _anchors[id]?.currentContext;
    if (target != null) {
      await Scrollable.ensureVisible(
        target,
        alignment: 0,
        duration: const Duration(milliseconds: 220),
      );
    }
  }

  void _select(String id) {
    widget.controller.select(id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.controller.selectedId == id) reveal(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final selected =
        widget.findings.where((f) => f.id == c.selectedId).firstOrNull ??
        widget.findings.firstOrNull;
    final ids = widget.findings.map((f) => f.id).toSet();
    _anchors.removeWhere((id, _) => !ids.contains(id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final finding in widget.findings)
          KeyedSubtree(
            key: _anchors.putIfAbsent(finding.id, GlobalKey.new),
            child: _FindingRow(
              key: ValueKey(finding.id),
              controller: c,
              finding: finding,
              number: c.reviewFindings.indexOf(finding) + 1,
              selected: finding == selected,
              onSelect: () => _select(finding.id),
              onMask: () => widget.onMask(finding),
              onVenueDetails: widget.onVenueDetails,
            ),
          ),
      ],
    );
  }
}

class _FindingRow extends StatefulWidget {
  const _FindingRow({
    super.key,
    required this.controller,
    required this.finding,
    required this.number,
    required this.selected,
    required this.onSelect,
    required this.onMask,
    required this.onVenueDetails,
  });
  final PostCheckController controller;
  final Finding finding;
  final int number;
  final bool selected;
  final VoidCallback onSelect;
  final Future<void> Function() onMask, onVenueDetails;
  @override
  State<_FindingRow> createState() => _FindingRowState();
}

class _FindingRowState extends State<_FindingRow> {
  bool remember = false;
  @override
  void didUpdateWidget(_FindingRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.finding, widget.finding)) remember = false;
  }

  String question(Finding f) {
    if (f.source == FindingSource.gemma) return f.question;
    return switch (f.kind) {
      FindingKind.contact => 'この連絡先を公開しますか？',
      FindingKind.imageText => 'この文字を公開しますか？',
      FindingKind.face => '写っている方の掲載許可はありますか？',
      FindingKind.announcement => '今、告知してよい内容ですか？',
      FindingKind.privateWord => 'この登録ワードを公開しますか？',
      FindingKind.context => f.question,
      FindingKind.screenDevice => switch (f.detectedLabel) {
        'whiteboard' => 'ホワイトボードを隠しますか？',
        'wine_glass' => 'お酒（ワイングラス）を隠しますか？',
        'book' => '本・資料を隠しますか？',
        'picture_frame' => '額縁を隠しますか？',
        'poster' => 'ポスターを隠しますか？',
        _ => 'パソコンやスマホを隠しますか？',
      },
    };
  }

  String label(Finding f) => f.displayLabel;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, f = widget.finding;
    final decision = c.decisionFor(f);
    final rawText = f.excerpt.trim();
    return Padding(
      key: ValueKey('finding-row-${f.id}'),
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: widget.selected
                ? CupertinoColors.activeBlue
                : Colors.transparent,
            width: 1.3,
          ),
        ),
        child: GlassSurface(
          radius: 22,
          native: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                selected: widget.selected,
                child: InkWell(
                  key: ValueKey('finding-select-${f.id}'),
                  borderRadius: BorderRadius.circular(22),
                  onTap: widget.onSelect,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.selected
                                ? CupertinoColors.activeBlue
                                : PostCheckPalette.blueSoft,
                          ),
                          child: Text(
                            '${widget.number}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: widget.selected
                                  ? Colors.white
                                  : CupertinoColors.activeBlue,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // OCR and quoted content is literal, including in English UI.
                              if (rawText.isNotEmpty)
                                Text(
                                  rawText,
                                  maxLines: widget.selected ? null : 2,
                                  overflow: widget.selected
                                      ? TextOverflow.visible
                                      : TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              else
                                AppText(
                                  label(f),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              if (rawText.isNotEmpty &&
                                  f.kind != FindingKind.imageText) ...[
                                const SizedBox(height: 4),
                                AppText(
                                  label(f),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: PostCheckPalette.secondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          decision == ReviewDecision.pending
                              ? CupertinoIcons.circle
                              : CupertinoIcons.checkmark_circle_fill,
                          size: 20,
                          semanticLabel: tr(
                            context,
                            decision == ReviewDecision.pending
                                ? '未確認'
                                : decision == ReviewDecision.keep
                                ? '残す'
                                : '隠す',
                          ),
                          color: decision == ReviewDecision.pending
                              ? PostCheckPalette.tertiary
                              : CupertinoColors.activeBlue,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        for (final choice in [
                          ReviewDecision.keep,
                          ReviewDecision.hide,
                        ]) ...[
                          if (choice == ReviewDecision.hide)
                            const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              key: ValueKey('finding-${choice.name}-${f.id}'),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: decision == choice
                                    ? CupertinoColors.activeBlue
                                    : null,
                                foregroundColor: decision == choice
                                    ? Colors.white
                                    : null,
                              ),
                              onPressed:
                                  c.busy ||
                                      c.preparingPreview ||
                                      (choice == ReviewDecision.keep &&
                                          !c.canReselect(f))
                                  ? null
                                  : () {
                                      widget.onSelect();
                                      if (choice == ReviewDecision.hide &&
                                          f.target is WholePhotoTarget) {
                                        widget.onMask();
                                      } else {
                                        c.decide(f, choice, remember: remember);
                                      }
                                    },
                              child: AppText(
                                choice == ReviewDecision.keep ? '残す' : '隠す',
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (!c.canReselect(f))
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: AppText(
                          '非表示部分が文章編集で変わったため、この候補だけは戻せません。現在の文章は保持しています。',
                        ),
                      ),
                    if (widget.selected) ...[
                      const SizedBox(height: 8),
                      AppText(
                        question(f),
                        style: const TextStyle(
                          fontSize: 13,
                          color: PostCheckPalette.secondary,
                        ),
                      ),
                      for (final question
                          in f.related
                              .expand((r) => r.evidence)
                              .map((r) => r.question)
                              .toSet()
                              .where((q) => q != f.question))
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: AppText(
                            question,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      for (final excerpt
                          in f.related
                              .expand((r) => r.evidence)
                              .map((r) => r.excerpt)
                              .toSet()
                              .where((t) => t.isNotEmpty && t != f.excerpt))
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            excerpt,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      for (final evidence
                          in f.related
                              .expand((r) => r.evidence)
                              .map((r) => r.ruleEvidence)
                              .whereType<String>()
                              .toSet()
                              .where((t) => t != f.ruleEvidence))
                        Text(evidence, style: const TextStyle(fontSize: 12)),
                      if (f.ruleEvidence != null) ...[
                        const SizedBox(height: 8),
                        if (f.source == FindingSource.gemma)
                          const AppText('関連する施設ルール（原文）'),
                        Text(
                          f.ruleEvidence!,
                          maxLines: f.source == FindingSource.gemma ? null : 3,
                          overflow: f.source == FindingSource.gemma
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                        ),
                        TextButton(
                          onPressed: widget.onVenueDetails,
                          child: const AppText('施設ルールの原文を見る'),
                        ),
                      ],
                      if (c.policy.suggestionFor(f) != null)
                        AppText(
                          '過去の選択では「${c.policy.suggestionFor(f) == ReviewDecision.hide ? '隠す' : '残す'}」が多い傾向です。',
                        ),
                      // A row hidden by an earlier recheck has no editable
                      // mask on the edited photo; choosing 「残す」 reopens it.
                      if (f.target is! CaptionTarget && !c.isHiddenEarlier(f))
                        TextButton(
                          onPressed: c.preparingPreview ? null : widget.onMask,
                          child: AppText(
                            f.target is WholePhotoTarget
                                ? '範囲を指定して隠す'
                                : '隠す範囲を調整',
                          ),
                        ),
                      if (decision != ReviewDecision.pending)
                        TextButton(
                          onPressed: c.preparingPreview
                              ? null
                              : () => c.decide(f, ReviewDecision.pending),
                          child: const AppText('この選択を戻す'),
                        ),
                      if (c.policy.learningEnabled)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const AppText('この選択を今後の提案に活かす'),
                          value: remember,
                          onChanged: (value) =>
                              setState(() => remember = value ?? false),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
