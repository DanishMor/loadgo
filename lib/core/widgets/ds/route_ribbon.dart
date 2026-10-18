import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/design_tokens.dart';

/// Pickup to drop on one line: a filled dot, a dashed line with a small truck on
/// it, a pin, the two city names under the ends and the distance in the middle.
/// Drawn with a [CustomPainter], so it needs no map, no network and no image.
class RouteRibbon extends StatelessWidget {
  final String from;
  final String to;
  final int? distanceKm;

  /// 0..1: how far the truck is along the line (a trip in progress). Null puts it in the middle.
  final double? progress;

  const RouteRibbon({super.key, required this.from, required this.to, this.distanceKm, this.progress});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final km = distanceKm != null && distanceKm! > 0 ? trf(context, 'uxKm', {'n': distanceKm!}) : '';
    return Semantics(
      container: true,
      label: trf(context, 'uxRouteLabel', {'from': from, 'to': to, 'km': km}),
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 36,
            width: double.infinity,
            child: CustomPaint(
              painter: RouteRibbonPainter(line: c.inputBorder, dot: c.primary, pin: c.accentStrong, truck: c.primary, progress: progress, rtl: Directionality.of(context) == TextDirection.rtl),
            ),
          ),
          const SizedBox(height: DsSpace.s1),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(from, maxLines: 2, overflow: TextOverflow.ellipsis, style: DsType.label.copyWith(color: c.textStrong))),
              if (km.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: DsSpace.s2),
                  child: Text(km, style: DsType.caption.copyWith(color: c.textMuted)),
                ),
              Expanded(child: Text(to, textAlign: TextAlign.end, maxLines: 2, overflow: TextOverflow.ellipsis, style: DsType.label.copyWith(color: c.textStrong))),
            ],
          ),
        ],
      ),
    );
  }
}

class RouteRibbonPainter extends CustomPainter {
  final Color line, dot, pin, truck;
  final double? progress;
  final bool rtl;

  const RouteRibbonPainter({required this.line, required this.dot, required this.pin, required this.truck, this.progress, this.rtl = false});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    const pad = 10.0;
    final startX = rtl ? size.width - pad : pad;
    final endX = rtl ? pad : size.width - pad;
    final dash = Paint()
      ..color = line
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final len = (endX - startX).abs();
    final dir = rtl ? -1.0 : 1.0;
    // Dashes between the two ends, leaving room for the dot and the pin.
    for (double d = 14; d + 6 < len - 14; d += 12) {
      canvas.drawLine(Offset(startX + dir * d, y), Offset(startX + dir * (d + 6), y), dash);
    }
    canvas.drawCircle(Offset(startX, y), 7, Paint()..color = dot);
    // The pin: a rounded head with a point below it.
    final p = Offset(endX, y - 2);
    final path = Path()
      ..moveTo(p.dx, p.dy + 12)
      ..lineTo(p.dx - 7, p.dy + 2)
      ..arcToPoint(Offset(p.dx + 7, p.dy + 2), radius: const Radius.circular(7.5), clockwise: true)
      ..close();
    canvas.drawPath(path, Paint()..color = pin);
    canvas.drawCircle(Offset(p.dx, p.dy - 1), 2.5, Paint()..color = dot);
    // The truck: a body, a cab and two wheels, on the line.
    final t = (progress ?? 0.5).clamp(0.0, 1.0);
    final cx = startX + dir * (14 + (len - 28) * t);
    final body = Paint()..color = truck;
    final rect = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, y - 3), width: 22, height: 12), const Radius.circular(2));
    canvas.drawRRect(rect, body);
    final cab = Rect.fromLTWH(rtl ? cx - 17 : cx + 11, y - 6, 6, 9);
    canvas.drawRect(cab, body);
    canvas.drawCircle(Offset(cx - 6, y + 4), 2.5, Paint()..color = line);
    canvas.drawCircle(Offset(cx + 6, y + 4), 2.5, Paint()..color = line);
  }

  @override
  bool shouldRepaint(RouteRibbonPainter o) => o.line != line || o.dot != dot || o.pin != pin || o.truck != truck || o.progress != progress || o.rtl != rtl;
}
