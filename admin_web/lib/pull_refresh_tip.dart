import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';
import 'soft_refresh.dart';

const _tipSeenKey = 'postcheck_admin_pull_refresh_tip_seen';

bool _tipSeenThisSession = false;

Future<bool> hasSeenPullRefreshTip() async {
  if (_tipSeenThisSession) return true;
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_tipSeenKey) ?? false;
  } catch (_) {
    // Optional onboarding storage must never turn a successful login into an error.
    return true;
  }
}

Future<void> markPullRefreshTipSeen() async {
  _tipSeenThisSession = true;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_tipSeenKey, true);
  } catch (_) {
    // Storage-disabled/private browsers still allow the user to dismiss the tip.
  }
}

/// Gmail風：初回だけ「上端を下へ引いて更新」を実演するカード。
class PullRefreshTipCard extends StatefulWidget {
  const PullRefreshTipCard({
    super.key,
    required this.onDismiss,
    required this.onTryRefresh,
  });

  final VoidCallback onDismiss;
  final Future<void> Function() onTryRefresh;

  @override
  State<PullRefreshTipCard> createState() => _PullRefreshTipCardState();
}

class _PullRefreshTipCardState extends State<PullRefreshTipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();
  bool _trying = false;

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  Future<void> _try() async {
    if (_trying) return;
    setState(() => _trying = true);
    try {
      await widget.onTryRefresh();
      await markPullRefreshTipSeen();
      if (mounted) widget.onDismiss();
    } finally {
      if (mounted) setState(() => _trying = false);
    }
  }

  Future<void> _dismiss() async {
    await markPullRefreshTipSeen();
    if (mounted) widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final pull = CurvedAnimation(
      parent: _motion,
      curve: const Interval(0.0, 0.32, curve: Curves.easeOut),
    );
    final spinning = CurvedAnimation(
      parent: _motion,
      curve: const Interval(0.32, 0.88, curve: Curves.linear),
    );
    return Card(
      color: PostCheckPalette.blueSoft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '下へ引くと更新できます',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Gmailと同じ操作です。一覧のいちばん上で下へ引き、指を離すと最新の申請に更新します。',
                        style: TextStyle(color: PostCheckPalette.secondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '閉じる',
                  onPressed: _trying ? null : _dismiss,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 88,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: PostCheckPalette.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: AnimatedBuilder(
                animation: _motion,
                builder: (context, _) {
                  final t = pull.value;
                  final spin = spinning.value;
                  final offset = 36.0 + 18.0 * t;
                  return Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      Positioned(
                        top: 14,
                        child: Opacity(
                          opacity: 0.4 + 0.6 * (t > 0 ? 1 : spin),
                          child: RefreshMark(
                            spinning: spin > 0 && spin < 1,
                            reveal: spin > 0 ? 0.72 : t,
                            color: PostCheckPalette.primary,
                            size: 16,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 28,
                        right: 28,
                        top: offset,
                        child: Column(
                          children: [
                            _demoRow(true),
                            const SizedBox(height: 8),
                            _demoRow(false),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _trying ? null : _try,
                  child: Text(_trying ? '更新しています…' : 'いま更新してみる'),
                ),
                TextButton(
                  onPressed: _trying ? null : _dismiss,
                  child: const Text('あとで自分で試す'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _demoRow(bool strong) => Container(
    height: 12,
    decoration: BoxDecoration(
      color: strong ? PostCheckPalette.borderStrong : PostCheckPalette.border,
      borderRadius: BorderRadius.circular(4),
    ),
  );
}
