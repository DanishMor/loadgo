import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';

/// Pictures for empty and error screens, drawn in code (no image files, so
/// they cost nothing to download, work offline and follow light / dark).
enum IllustrationKind {
  /// Nothing here yet: an open box.
  emptyBox,

  /// A search found nothing.
  noResults,

  /// No internet.
  noNetwork,

  /// Something went wrong.
  error,

  /// Done: a ticked circle.
  success,

  /// No trips: a truck on a road.
  noTrips,

  /// Safe and private: a shield with a tick.
  shield,

  /// E11 onboarding 1: post a load from the phone.
  onboardPost,

  /// E11 onboarding 2: offers arrive, the best one ticked.
  onboardOffers,

  /// E11 onboarding 3: follow the trip from pickup to drop.
  onboardTrack,

  /// E11: no notifications yet, a quiet bell.
  noNotifications,
}

/// One of the [IllustrationKind] pictures at [width] (height is 3/4 of it).
/// Decorative: screen readers skip it, so always put the meaning in text beside it.
class IllustrationView extends StatelessWidget {
  final IllustrationKind kind;
  final double width;

  const IllustrationView(this.kind, {super.key, this.width = 160});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: width * 0.75,
        child: CustomPaint(painter: IllustrationPainter(kind, c)),
      ),
    );
  }
}

/// Draws a picture on a 160 x 120 canvas, scaled to fit.
class IllustrationPainter extends CustomPainter {
  final IllustrationKind kind;
  final DsColors c;
  const IllustrationPainter(this.kind, this.c);

  static const double w = 160, h = 120;

  Paint _fill(Color color) => Paint()..color = color..style = PaintingStyle.fill;
  Paint _line(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / w, size.height / h);
    // A soft shape behind every picture, and the ground it stands on.
    canvas.drawOval(Rect.fromCenter(center: const Offset(80, 58), width: 120, height: 92), _fill(c.tint));
    canvas.drawOval(Rect.fromCenter(center: const Offset(80, 106), width: 90, height: 8), _fill(c.chip));
    switch (kind) {
      case IllustrationKind.emptyBox:
        _emptyBox(canvas);
      case IllustrationKind.noResults:
        _noResults(canvas);
      case IllustrationKind.noNetwork:
        _noNetwork(canvas);
      case IllustrationKind.error:
        _error(canvas);
      case IllustrationKind.success:
        _success(canvas);
      case IllustrationKind.noTrips:
        _noTrips(canvas);
      case IllustrationKind.shield:
        _shield(canvas);
      case IllustrationKind.onboardPost:
        _onboardPost(canvas);
      case IllustrationKind.onboardOffers:
        _onboardOffers(canvas);
      case IllustrationKind.onboardTrack:
        _onboardTrack(canvas);
      case IllustrationKind.noNotifications:
        _noNotifications(canvas);
    }
    canvas.restore();
  }

  void _emptyBox(Canvas canvas) {
    final body = RRect.fromRectAndRadius(const Rect.fromLTWH(48, 52, 64, 44), const Radius.circular(4));
    canvas.drawRRect(body, _fill(c.surface));
    canvas.drawRRect(body, _line(c.primary, 3));
    // Open flaps.
    final left = Path()..moveTo(48, 52)..lineTo(36, 40)..lineTo(70, 40)..lineTo(80, 52)..close();
    final right = Path()..moveTo(112, 52)..lineTo(124, 40)..lineTo(90, 40)..lineTo(80, 52)..close();
    for (final p in [left, right]) {
      canvas.drawPath(p, _fill(c.chip));
      canvas.drawPath(p, _line(c.primary, 3));
    }
    canvas.drawLine(const Offset(64, 68), const Offset(96, 68), _line(c.accentStrong, 3));
    // Little sparkles.
    _spark(canvas, const Offset(32, 28), 5);
    _spark(canvas, const Offset(130, 24), 4);
  }

  void _spark(Canvas canvas, Offset o, double r) {
    final p = _line(c.accentStrong, 2);
    canvas.drawLine(o.translate(-r, 0), o.translate(r, 0), p);
    canvas.drawLine(o.translate(0, -r), o.translate(0, r), p);
  }

  void _noResults(Canvas canvas) {
    canvas.drawCircle(const Offset(72, 54), 28, _fill(c.surface));
    canvas.drawCircle(const Offset(72, 54), 28, _line(c.primary, 6));
    canvas.drawLine(const Offset(93, 75), const Offset(118, 100), _line(c.accentStrong, 9));
    // A small "?" inside the glass.
    final q = Path()
      ..moveTo(64, 46)
      ..quadraticBezierTo(64, 38, 72, 38)
      ..quadraticBezierTo(80, 38, 80, 46)
      ..quadraticBezierTo(80, 52, 72, 55)
      ..lineTo(72, 59);
    canvas.drawPath(q, _line(c.textMuted, 4));
    canvas.drawCircle(const Offset(72, 68), 2.5, _fill(c.textMuted));
  }

  void _noNetwork(Canvas canvas) {
    final cloud = Path()
      ..addOval(Rect.fromCircle(center: const Offset(64, 62), radius: 20))
      ..addOval(Rect.fromCircle(center: const Offset(88, 54), radius: 26))
      ..addOval(Rect.fromCircle(center: const Offset(108, 66), radius: 17))
      ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(46, 62, 78, 22), const Radius.circular(11)));
    canvas.drawPath(cloud, _fill(c.surface));
    canvas.drawPath(cloud, _line(c.textMuted, 3));
    // Wi-fi arcs.
    for (final r in [8.0, 15.0, 22.0]) {
      canvas.drawArc(Rect.fromCircle(center: const Offset(86, 80), radius: r), math.pi * 1.2, math.pi * 0.6, false, _line(c.primary, 3));
    }
    canvas.drawCircle(const Offset(86, 80), 2.5, _fill(c.primary));
    // The slash.
    canvas.drawLine(const Offset(52, 30), const Offset(122, 100), _line(c.error, 5));
  }

  void _error(Canvas canvas) {
    final tri = Path()..moveTo(80, 24)..lineTo(120, 92)..lineTo(40, 92)..close();
    canvas.drawPath(tri, _fill(c.errorBg));
    canvas.drawPath(tri, _line(c.error, 6));
    canvas.drawLine(const Offset(80, 46), const Offset(80, 70), _line(c.error, 6));
    canvas.drawCircle(const Offset(80, 82), 3.5, _fill(c.error));
  }

  void _success(Canvas canvas) {
    canvas.drawCircle(const Offset(80, 58), 34, _fill(c.successBg));
    canvas.drawCircle(const Offset(80, 58), 34, _line(c.success, 6));
    final tick = Path()..moveTo(64, 58)..lineTo(76, 70)..lineTo(98, 46);
    canvas.drawPath(tick, _line(c.success, 8));
  }

  void _shield(Canvas canvas) {
    final body = Path()
      ..moveTo(80, 20)
      ..lineTo(118, 33)
      ..lineTo(118, 62)
      ..cubicTo(118, 84, 102, 97, 80, 104)
      ..cubicTo(58, 97, 42, 84, 42, 62)
      ..lineTo(42, 33)
      ..close();
    canvas.drawPath(body, _fill(c.surface));
    canvas.drawPath(body, _line(c.primary, 6));
    canvas.drawPath(Path()..moveTo(64, 62)..lineTo(76, 74)..lineTo(98, 48), _line(c.success, 8));
  }

  void _noTrips(Canvas canvas) {
    // Road.
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(20, 86, 120, 16), const Radius.circular(8)), _fill(c.textMuted));
    for (var x = 30.0; x < 130; x += 22) {
      canvas.drawLine(Offset(x, 94), Offset(x + 10, 94), _line(c.surface, 3));
    }
    // Truck: box, cab, window, wheels.
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(34, 48, 56, 34), const Radius.circular(4)), _fill(c.primary));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(94, 58, 28, 24), const Radius.circular(5)), _fill(c.accent));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(106, 62, 12, 10), const Radius.circular(2)), _fill(c.surface));
    for (final x in [52.0, 108.0]) {
      canvas.drawCircle(Offset(x, 84), 8, _fill(c.text));
      canvas.drawCircle(Offset(x, 84), 3, _fill(c.surface));
    }
  }

  void _onboardPost(Canvas canvas) {
    // A phone with a parcel on its screen and a "+" to post it.
    final phone = RRect.fromRectAndRadius(const Rect.fromLTWH(56, 18, 48, 86), const Radius.circular(8));
    canvas.drawRRect(phone, _fill(c.surface));
    canvas.drawRRect(phone, _line(c.primary, 3));
    canvas.drawLine(const Offset(74, 26), const Offset(86, 26), _line(c.border, 3));
    final box = RRect.fromRectAndRadius(const Rect.fromLTWH(66, 46, 28, 22), const Radius.circular(3));
    canvas.drawRRect(box, _fill(c.chip));
    canvas.drawRRect(box, _line(c.primary, 2.5));
    canvas.drawLine(const Offset(80, 46), const Offset(80, 68), _line(c.primary, 2));
    canvas.drawCircle(const Offset(80, 86), 8, _fill(c.accent));
    canvas.drawLine(const Offset(76, 86), const Offset(84, 86), _line(c.onAccent, 2.5));
    canvas.drawLine(const Offset(80, 82), const Offset(80, 90), _line(c.onAccent, 2.5));
    _spark(canvas, const Offset(36, 34), 5);
    _spark(canvas, const Offset(126, 28), 4);
  }

  void _onboardOffers(Canvas canvas) {
    // Three offer cards; the front one is ticked.
    for (var i = 2; i >= 0; i--) {
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(38.0 + i * 6, 30.0 + i * 18, 84 - i * 12.0, 30), const Radius.circular(6));
      canvas.drawRRect(r, _fill(c.surface));
      canvas.drawRRect(r, _line(i == 0 ? c.primary : c.inputBorder, i == 0 ? 3 : 2));
    }
    canvas.drawCircle(const Offset(54, 45), 7, _fill(c.accentStrong));
    canvas.drawLine(const Offset(68, 41), const Offset(98, 41), _line(c.textMuted, 3));
    canvas.drawLine(const Offset(68, 50), const Offset(88, 50), _line(c.border, 3));
    canvas.drawCircle(const Offset(112, 34), 10, _fill(c.successBg));
    canvas.drawPath(Path()..moveTo(107, 34)..lineTo(111, 38)..lineTo(118, 30), _line(c.success, 3));
  }

  void _onboardTrack(Canvas canvas) {
    // A curved route from a dot to a pin, a small truck on it.
    final route = Path()
      ..moveTo(36, 88)
      ..cubicTo(56, 40, 104, 96, 122, 40);
    for (final m in route.computeMetrics()) {
      for (double d = 0; d < m.length; d += 10) {
        canvas.drawPath(m.extractPath(d, d + 5), _line(c.primary, 3));
      }
      final mid = m.getTangentForOffset(m.length * 0.5)!.position;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: mid.translate(0, -6), width: 22, height: 12), const Radius.circular(2)), _fill(c.primary));
      canvas.drawRect(Rect.fromLTWH(mid.dx + 11, mid.dy - 9, 6, 9), _fill(c.primary));
    }
    canvas.drawCircle(const Offset(36, 88), 7, _fill(c.primary));
    final pin = Path()
      ..moveTo(122, 46)
      ..lineTo(114, 34)
      ..arcToPoint(const Offset(130, 34), radius: const Radius.circular(8.5), clockwise: true)
      ..close();
    canvas.drawPath(pin, _fill(c.accentStrong));
    canvas.drawCircle(const Offset(122, 31), 3, _fill(c.surface));
  }

  void _noNotifications(Canvas canvas) {
    // A bell at rest, with a small "z z" beside it.
    final bell = Path()
      ..moveTo(60, 84)
      ..lineTo(100, 84)
      ..cubicTo(94, 78, 94, 72, 94, 60)
      ..cubicTo(94, 46, 88, 36, 80, 36)
      ..cubicTo(72, 36, 66, 46, 66, 60)
      ..cubicTo(66, 72, 66, 78, 60, 84)
      ..close();
    canvas.drawPath(bell, _fill(c.surface));
    canvas.drawPath(bell, _line(c.primary, 3));
    canvas.drawCircle(const Offset(80, 90), 5, _fill(c.accentStrong));
    canvas.drawLine(const Offset(80, 30), const Offset(80, 36), _line(c.primary, 3));
    final z = _line(c.textMuted, 2.5);
    canvas.drawPath(Path()..moveTo(108, 34)..lineTo(118, 34)..lineTo(108, 44)..lineTo(118, 44), z);
    canvas.drawPath(Path()..moveTo(122, 20)..lineTo(129, 20)..lineTo(122, 27)..lineTo(129, 27), z);
  }

  @override
  bool shouldRepaint(IllustrationPainter old) => old.kind != kind || old.c != c;
}
