import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'app_theme.dart';

/// 引き下げ更新。Materialの矢印は出さず、細い円弧を回して更新中を示す。
class SoftRefresh extends StatefulWidget {
  const SoftRefresh({super.key, required this.onRefresh, required this.child});

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  State<SoftRefresh> createState() => SoftRefreshState();
}

class SoftRefreshState extends State<SoftRefresh>
    with SingleTickerProviderStateMixin {
  static const _threshold = 72.0;
  static const _hold = 72.0;
  static const _max = 120.0;
  static const _minSpin = Duration(milliseconds: 900);

  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..addListener(_tick);
  double _offset = 0;
  double _from = 0;
  double _to = 0;
  bool _dragging = false;
  bool _refreshing = false;
  Future<void>? _inflight;

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final t = Curves.easeOutCubic.transform(_settle.value);
    setState(() => _offset = _from + (_to - _from) * t);
  }

  TickerFuture _animateTo(double target) {
    _from = _offset;
    _to = target;
    return _settle.forward(from: 0);
  }

  Future<void> show() {
    _inflight ??= _run();
    return _inflight!;
  }

  Future<void> _run() async {
    setState(() => _refreshing = true);
    if (_offset < _hold - 1) _animateTo(_hold);
    final started = DateTime.now();
    try {
      await widget.onRefresh();
    } catch (_) {
      // 呼び出し側が一覧のエラー表示を行う。
    }
    final rest = _minSpin - DateTime.now().difference(started);
    if (rest > Duration.zero) await Future.delayed(rest);
    if (!mounted) return;
    await _animateTo(0);
    if (!mounted) return;
    setState(() => _refreshing = false);
    _inflight = null;
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical || _refreshing) {
      return false;
    }
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _dragging = true;
      _settle.stop();
    }
    if (notification is OverscrollNotification &&
        notification.overscroll < 0 &&
        notification.dragDetails != null) {
      _dragging = true;
      _settle.stop();
      setState(
        () => _offset = (_offset - notification.overscroll).clamp(0.0, _max),
      );
    } else if (notification is ScrollUpdateNotification &&
        _dragging &&
        notification.dragDetails != null &&
        notification.scrollDelta != null &&
        notification.scrollDelta! > 0 &&
        notification.metrics.pixels <= notification.metrics.minScrollExtent) {
      setState(
        () => _offset = (_offset - notification.scrollDelta!).clamp(0.0, _max),
      );
    }
    if (notification is ScrollEndNotification && _dragging) {
      _dragging = false;
      if (_offset >= _threshold) {
        show();
      } else if (_offset > 0) {
        _animateTo(0);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final reveal = (_offset / _threshold).clamp(0.0, 1.0);
    final visible = _offset > 8;
    return Column(
      children: [
        SizedBox(
          height: _offset,
          child: visible
              ? Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: PostCheckPalette.border),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(9),
                      child: RefreshMark(
                        spinning: _refreshing,
                        reveal: _refreshing ? 0.72 : reveal,
                        color: PostCheckPalette.primary,
                        size: 18,
                      ),
                    ),
                  ),
                )
              : null,
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

/// 矢印のない細い円弧。更新中だけ一定速度で回る。
class RefreshMark extends StatefulWidget {
  const RefreshMark({
    super.key,
    required this.color,
    this.spinning = false,
    this.reveal = 0.78,
    this.size = 20,
  });

  final Color color;
  final bool spinning;
  final double reveal;
  final double size;

  @override
  State<RefreshMark> createState() => _RefreshMarkState();
}

class _RefreshMarkState extends State<RefreshMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _spin.repeat();
  }

  @override
  void didUpdateWidget(RefreshMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spinning && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.spinning && _spin.isAnimating) {
      _spin.stop();
      _spin.value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _spin,
        builder: (context, _) => CustomPaint(
          painter: _RingPainter(
            color: widget.color,
            sweep: widget.spinning
                ? 0.72
                : (0.18 + 0.6 * widget.reveal.clamp(0.0, 1.0)),
            turns: widget.spinning ? _spin.value : 0,
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.color,
    required this.sweep,
    required this.turns,
  });

  final Color color;
  final double sweep;
  final double turns;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = (size.shortestSide * 0.1).clamp(1.35, 1.7);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2 - stroke,
    );
    canvas.drawArc(
      rect,
      turns * math.pi * 2 - math.pi / 2,
      sweep.clamp(0.12, 0.86) * math.pi * 2,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.sweep != sweep ||
      oldDelegate.turns != turns;
}
