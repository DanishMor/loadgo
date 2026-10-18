import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/contrast.dart';
import '../../theme/design_tokens.dart';
import '../common.dart';
import 'haptics.dart';

enum FareVerdict { low, fair, high }

/// The price in one picture: a bar with the usual range of the route lit up, a tick for
/// the estimate, and a handle on the same bar for the price the person chooses. All
/// amounts are integer paise. Under the bar one short line says whether the chosen price
/// is low, fair or high.
class FareMeter extends StatelessWidget {
  final int estimatePaise;

  /// The usual range of finished trips (the `rateRange` data). Null when there is none.
  final int? usualLowPaise;
  final int? usualHighPaise;
  final int valuePaise;
  final ValueChanged<int> onChanged;

  /// Slider step; 1000 paise is 10 rupees.
  final int stepPaise;

  const FareMeter({super.key, required this.estimatePaise, required this.valuePaise, required this.onChanged, this.usualLowPaise, this.usualHighPaise, this.stepPaise = 1000});

  bool get hasRange => usualLowPaise != null && usualHighPaise != null && usualHighPaise! >= usualLowPaise!;

  /// Where the slider starts and ends: half the estimate to double it, widened to hold the usual range.
  int get minPaise => _roundDown(hasRange && usualLowPaise! < estimatePaise ~/ 2 ? usualLowPaise! : estimatePaise ~/ 2);
  int get maxPaise => _roundUp(hasRange && usualHighPaise! > estimatePaise * 2 ? usualHighPaise! : estimatePaise * 2);

  int _roundDown(int v) => v - v % stepPaise;
  int _roundUp(int v) => v % stepPaise == 0 ? v : v + stepPaise - v % stepPaise;

  /// Low and high are judged against the usual range; without one, against 85% and 115% of the estimate.
  FareVerdict get verdict {
    final low = hasRange ? usualLowPaise! : estimatePaise * 85 ~/ 100;
    final high = hasRange ? usualHighPaise! : estimatePaise * 115 ~/ 100;
    if (valuePaise < low) return FareVerdict.low;
    if (valuePaise > high) return FareVerdict.high;
    return FareVerdict.fair;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final lo = minPaise, hi = maxPaise;
    final span = (hi - lo) <= 0 ? 1 : hi - lo;
    double at(int v) => ((v - lo) / span).clamp(0.0, 1.0);
    final v = verdict;
    final hint = switch (v) {
      FareVerdict.low => 'uxFareLow',
      FareVerdict.fair => 'uxFareFair',
      FareVerdict.high => 'uxFareHigh',
    };
    final steps = (hi - lo) ~/ stepPaise;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(tr(context, 'uxFareYour'), style: DsType.label.copyWith(color: c.textMuted)),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(formatPaise(valuePaise), key: const ValueKey('fareMeterValue'), style: DsType.display.copyWith(color: c.textStrong)),
        ),
        const SizedBox(height: DsSpace.s2),
        SizedBox(
          height: 40,
          child: Stack(alignment: Alignment.center, children: [
            Positioned.fill(
              child: CustomPaint(
                painter: FareMeterPainter(
                  track: c.chip,
                  range: c.successBg,
                  rangeEdge: ensureContrast(c.success, c.surface),
                  tick: c.textStrong,
                  from: hasRange ? at(usualLowPaise!) : null,
                  to: hasRange ? at(usualHighPaise!) : null,
                  estimate: at(estimatePaise),
                  rtl: Directionality.of(context) == TextDirection.rtl,
                ),
              ),
            ),
            // The painted bar is the track; the slider only brings the handle.
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 10,
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
                activeTickMarkColor: Colors.transparent,
                inactiveTickMarkColor: Colors.transparent,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Semantics(
                label: tr(context, 'uxFareYour'),
                value: formatPaise(valuePaise),
                child: Slider(
                  value: valuePaise.clamp(lo, hi).toDouble(),
                  min: lo.toDouble(),
                  max: hi.toDouble(),
                  divisions: steps < 1 ? null : steps,
                  onChanged: (d) {
                    final n = (d / stepPaise).round() * stepPaise;
                    if (n != valuePaise) {
                      Haptics.tap();
                      onChanged(n);
                    }
                  },
                ),
              ),
            ),
          ]),
        ),
        Row(children: [
          Icon(v == FareVerdict.fair ? Icons.check_circle_rounded : Icons.info_rounded, size: 18, color: ensureContrast(v == FareVerdict.fair ? c.success : c.warning, c.surface)),
          const SizedBox(width: DsSpace.s2),
          Expanded(child: Text(tr(context, hint), key: const ValueKey('fareMeterHint'), style: DsType.bodySmall.copyWith(color: c.text))),
        ]),
        const SizedBox(height: DsSpace.s1),
        Text(
          hasRange ? trf(context, 'uxFareUsual', {'low': formatPaise(usualLowPaise!), 'high': formatPaise(usualHighPaise!)}) : tr(context, 'uxFareNoRange'),
          key: const ValueKey('fareMeterUsual'),
          style: DsType.caption.copyWith(color: c.textMuted),
        ),
      ],
    );
  }
}

class FareMeterPainter extends CustomPainter {
  final Color track, range, rangeEdge, tick;
  final double? from, to;
  final double estimate;
  final bool rtl;

  const FareMeterPainter({required this.track, required this.range, required this.rangeEdge, required this.tick, required this.from, required this.to, required this.estimate, this.rtl = false});

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 12.0; // the slider overlay radius, so the bar lines up with the handle
    final w = size.width - pad * 2;
    double x(double f) => pad + (rtl ? 1 - f : f) * w;
    final y = size.height / 2;
    final bar = RRect.fromRectAndRadius(Rect.fromLTWH(pad, y - 5, w, 10), const Radius.circular(5));
    canvas.drawRRect(bar, Paint()..color = track);
    if (from != null && to != null) {
      final a = x(from!), b = x(to!);
      final r = RRect.fromRectAndRadius(Rect.fromLTRB(a < b ? a : b, y - 5, a < b ? b : a, y + 5), const Radius.circular(5));
      canvas.drawRRect(r, Paint()..color = range);
      canvas.drawRRect(
          r,
          Paint()
            ..color = rangeEdge
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
    canvas.drawLine(
        Offset(x(estimate), y - 9),
        Offset(x(estimate), y + 9),
        Paint()
          ..color = tick
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(FareMeterPainter o) => o.from != from || o.to != to || o.estimate != estimate || o.track != track || o.range != range || o.tick != tick || o.rtl != rtl;
}
