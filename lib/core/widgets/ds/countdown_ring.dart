import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/contrast.dart';
import '../../theme/design_tokens.dart';

/// A ring that empties while the time runs out, with the seconds left in the middle.
/// The time comes from [endsAt] (a server time the caller already has), so a screen that
/// is rebuilt, or a phone that sleeps, still shows the true time. The last 10 seconds
/// turn the ring to the warning colour. It redraws once a second, not every frame, and
/// with "remove animations" or Low-end mode that is all it does.
class CountdownRing extends StatefulWidget {
  final DateTime endsAt;
  final int totalSeconds;
  final double size;
  final VoidCallback? onDone;

  /// Tests replace the clock.
  final DateTime Function()? now;

  const CountdownRing({super.key, required this.endsAt, required this.totalSeconds, this.size = 72, this.onDone, this.now});

  /// Whole seconds left, never below 0 and never above [total].
  static int secondsLeft(DateTime endsAt, DateTime now, int total) {
    final ms = endsAt.difference(now).inMilliseconds;
    if (ms <= 0) return 0;
    final s = (ms / 1000).ceil();
    return s > total ? total : s;
  }

  @override
  State<CountdownRing> createState() => _CountdownRingState();
}

class _CountdownRingState extends State<CountdownRing> {
  Timer? _t;
  bool _fired = false;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    if (CountdownRing.secondsLeft(widget.endsAt, _now(), widget.totalSeconds) == 0 && !_fired) {
      _fired = true;
      _t?.cancel();
      widget.onDone?.call();
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(CountdownRing old) {
    super.didUpdateWidget(old);
    if (old.endsAt != widget.endsAt) {
      _fired = false;
      _t?.cancel();
      _t = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final left = CountdownRing.secondsLeft(widget.endsAt, _now(), widget.totalSeconds);
    final total = widget.totalSeconds <= 0 ? 1 : widget.totalSeconds;
    final urgent = left <= 10;
    final ring = urgent ? ensureContrast(c.error, c.surface) : c.primary;
    return Align(
      widthFactor: 1,
      heightFactor: 1,
      child: Semantics(
      label: trf(context, 'uxSecondsLeft', {'n': left}),
      excludeSemantics: true,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: CountdownRingPainter(track: c.chip, ring: ring, fraction: left / total),
          child: Center(child: Directionality(textDirection: TextDirection.ltr, child: Text('$left', key: const ValueKey('ringSeconds'), style: DsType.title.copyWith(color: c.textStrong)))),
        ),
      ),
    ));
  }
}

class CountdownRingPainter extends CustomPainter {
  final Color track, ring;
  final double fraction;
  const CountdownRingPainter({required this.track, required this.ring, required this.fraction});

  @override
  void paint(Canvas canvas, Size size) {
    const w = 7.0;
    final rect = Rect.fromLTWH(w / 2, w / 2, size.width - w, size.height - w);
    canvas.drawArc(
        rect,
        0,
        2 * math.pi,
        false,
        Paint()
          ..color = track
          ..style = PaintingStyle.stroke
          ..strokeWidth = w);
    canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * fraction.clamp(0.0, 1.0),
        false,
        Paint()
          ..color = ring
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = w);
  }

  @override
  bool shouldRepaint(CountdownRingPainter o) => o.fraction != fraction || o.ring != ring || o.track != track;
}
