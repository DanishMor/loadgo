import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/design_tokens.dart';
import 'vehicle_catalog.dart';

/// E16: what the painter draws for a catalog type.
enum VehicleShape { bike, threeWheeler, open, closed, container, reefer, flatbed, lowBed, tanker, tipper, carrier, crane }

extension VehicleShapeOf on VehicleSpec {
  /// The shape follows the group first (two and three wheelers), then special types, then the first body type.
  VehicleShape get shape {
    if (group == 'two_wheeler') return VehicleShape.bike;
    if (group == 'three_wheeler') return VehicleShape.threeWheeler;
    if (lifts) return VehicleShape.crane;
    if (goods.contains('vehicles')) return VehicleShape.carrier;
    return switch (bodies.isEmpty ? 'closed' : bodies.first) {
      'open' => VehicleShape.open,
      'container' => VehicleShape.container,
      'refrigerated' => VehicleShape.reefer,
      'flatbed' => goods.contains('heavy') ? VehicleShape.lowBed : VehicleShape.flatbed,
      'tanker' => VehicleShape.tanker,
      'tipper' => VehicleShape.tipper,
      _ => VehicleShape.closed,
    };
  }
}

/// The colours of one drawing. Built from the theme's tokens, never raw colours.
@immutable
class VehicleInk {
  final Color body, side, line, accent, tyre, hub, glass;
  const VehicleInk({required this.body, required this.side, required this.line, required this.accent, required this.tyre, required this.hub, required this.glass});

  /// Light or dark, from the colour set of the look being shown.
  /// Tyres stay dark in every look: on a dark surface they take the chip grey and the light outline shows the shape.
  factory VehicleInk.of(DsColors c) {
    final dark = c.surface.computeLuminance() < 0.2;
    return VehicleInk(body: c.surface, side: c.chip, line: c.textStrong, accent: c.accent, tyre: dark ? c.chip : c.textStrong, hub: c.surface, glass: c.tint);
  }

  /// Gold outline on nothing: for the Midnight look's premium cards and the splash of a spec sheet.
  static const gold = VehicleInk(body: Colors.transparent, side: Colors.transparent, line: DsLuxe.gold, accent: DsLuxe.goldLight, tyre: Colors.transparent, hub: Colors.transparent, glass: Colors.transparent);

  /// One colour on nothing (silhouette tests and stamps).
  factory VehicleInk.mono(Color c) => VehicleInk(body: c, side: c, line: c, accent: c, tyre: c, hub: c, glass: c);

  @override
  bool operator ==(Object other) =>
      other is VehicleInk && other.body == body && other.side == side && other.line == line && other.accent == accent && other.tyre == tyre && other.hub == hub && other.glass == glass;

  @override
  int get hashCode => Object.hash(body, side, line, accent, tyre, hub, glass);
}

/// Draws one catalog vehicle in a single refined 3/4-side style on a 320 x 120 grid, scaled to fit and centred.
/// The cab faces left; a lighter top and rear face give the depth. No maker marks, no text.
class VehiclePainter extends CustomPainter {
  final VehicleSpec spec;
  final VehicleInk ink;
  const VehiclePainter(this.spec, this.ink);

  static const double w = 320, h = 120;
  static const double groundY = 108, wheelY = 97, chassisTop = 82, chassisBottom = 88;
  static const Offset depth = Offset(8, -5);
  static const double cabX = 12, cabW = 44;

  /// Where the cargo space starts and ends on the grid (x).
  static (double, double) cargoSpan(VehicleSpec v) {
    const start = cabX + cabW + 4;
    final len = 40 + 3.3 * math.min(v.lengthFt <= 0 ? 18 : v.lengthFt, 60);
    return (start, start + len);
  }

  /// The centre (x) of the visible wheel of each axle, front first. One per axle.
  static List<double> wheelCenters(VehicleSpec v) {
    switch (v.shape) {
      case VehicleShape.bike:
        return [70, 170];
      case VehicleShape.threeWheeler:
        return [52, 62 + 18 * v.lengthFt.clamp(3.0, 6.0)];
      case VehicleShape.crane:
        return [for (var i = 0; i < v.axles.length; i++) 40.0 + i * 70];
      default:
        break;
    }
    final (_, end) = cargoSpan(v);
    final xs = <double>[cabX + cabW / 2];
    // More steering axles with single tyres sit right behind the first one.
    var i = 1;
    while (i < v.axles.length && v.axles[i] == 2) {
      xs.add(xs.last + 24);
      i++;
    }
    final rear = v.axles.length - i;
    if (rear <= 0) return xs;
    if (rear <= 3) {
      for (var k = 0; k < rear; k++) {
        xs.add(end - 20 - 24.0 * (rear - 1 - k));
      }
    } else {
      // A tractor and trailer: two drive axles behind the cab, the rest under the trailer's end.
      xs.addAll([cabX + cabW + 22, cabX + cabW + 46]);
      final back = rear - 2;
      for (var k = 0; k < back; k++) {
        xs.add(end - 20 - 24.0 * (back - 1 - k));
      }
    }
    return xs;
  }

  Paint _fill(Color c) => Paint()..color = c..style = PaintingStyle.fill..isAntiAlias = true;
  Paint _line([double width = 2.5, Color? c]) => Paint()
    ..color = c ?? ink.line
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;

  void _shape(Canvas canvas, Path p, Color fill, {double width = 2.5}) {
    canvas.drawPath(p, _fill(fill));
    canvas.drawPath(p, _line(width));
  }

  /// A box with its top and rear faces drawn lighter for depth.
  void _box(Canvas canvas, Rect r, {Color? fill}) {
    final top = Path()..moveTo(r.left, r.top)..relativeLineTo(depth.dx, depth.dy)..lineTo(r.right + depth.dx, r.top + depth.dy)..lineTo(r.right, r.top)..close();
    final end = Path()..moveTo(r.right, r.top)..relativeLineTo(depth.dx, depth.dy)..lineTo(r.right + depth.dx, r.bottom + depth.dy)..lineTo(r.right, r.bottom)..close();
    _shape(canvas, top, ink.side);
    _shape(canvas, end, ink.side);
    _shape(canvas, Path()..addRRect(RRect.fromRectAndRadius(r, const Radius.circular(2))), fill ?? ink.body);
  }

  void _wheel(Canvas canvas, double x, int tyres, {double r = 10}) {
    final rr = tyres >= 4 ? r + 1.5 : r;
    // The far wheel peeks out behind (3/4 view).
    canvas.drawCircle(Offset(x + depth.dx * 0.6, wheelY + depth.dy * 0.6), rr, _fill(ink.side));
    canvas.drawCircle(Offset(x + depth.dx * 0.6, wheelY + depth.dy * 0.6), rr, _line(1.5));
    canvas.drawCircle(Offset(x, wheelY), rr, _fill(ink.tyre));
    canvas.drawCircle(Offset(x, wheelY), rr, _line(2));
    canvas.drawCircle(Offset(x, wheelY), rr * 0.45, _fill(ink.hub));
    canvas.drawCircle(Offset(x, wheelY), rr * 0.45, _line(1.5));
    if (tyres >= 4) canvas.drawCircle(Offset(x, wheelY), rr * 0.75, _line(1));
  }

  void _cab(Canvas canvas, {double top = 38, double x = cabX, double width = cabW}) {
    final cab = Path()
      ..moveTo(x, chassisBottom)
      ..lineTo(x, top + 16)
      ..lineTo(x + 9, top)
      ..lineTo(x + width, top)
      ..lineTo(x + width, chassisBottom)
      ..close();
    final roof = Path()..moveTo(x + 9, top)..relativeLineTo(depth.dx, depth.dy)..lineTo(x + width + depth.dx, top + depth.dy)..lineTo(x + width, top)..close();
    _shape(canvas, roof, ink.side);
    _shape(canvas, cab, ink.body);
    final glass = Path()
      ..moveTo(x + 4, top + 18)
      ..lineTo(x + 11, top + 6)
      ..lineTo(x + width - 7, top + 6)
      ..lineTo(x + width - 7, top + 20)
      ..close();
    _shape(canvas, glass, ink.glass, width: 1.5);
    // Door line, handle and a lamp in the accent colour.
    canvas.drawLine(Offset(x + width - 7, top + 24), Offset(x + width - 7, chassisBottom - 4), _line(1.2));
    canvas.drawLine(Offset(x + width - 14, top + 28), Offset(x + width - 10, top + 28), _line(2, ink.accent));
    canvas.drawCircle(Offset(x + 3, chassisBottom - 8), 2.2, _fill(ink.accent));
  }

  void _chassis(Canvas canvas, double from, double to) {
    _shape(canvas, Path()..addRect(Rect.fromLTRB(from, chassisTop, to, chassisBottom)), ink.side, width: 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width / w, size.height / h);
    canvas.save();
    canvas.translate((size.width - w * s) / 2, (size.height - h * s) / 2);
    canvas.scale(s);
    final wheels = wheelCenters(spec);
    switch (spec.shape) {
      case VehicleShape.bike:
        _bike(canvas, wheels);
      case VehicleShape.threeWheeler:
        _threeWheeler(canvas, wheels);
      case VehicleShape.crane:
        _crane(canvas, wheels);
      default:
        _truck(canvas, wheels);
    }
    canvas.restore();
  }

  void _truck(Canvas canvas, List<double> wheels) {
    final (x0, x1) = cargoSpan(spec);
    _chassis(canvas, cabX + 4, x1);
    final shape = spec.shape;
    final small = spec.group == 'lcv' && spec.lengthFt <= 8;
    switch (shape) {
      case VehicleShape.closed:
      case VehicleShape.container:
      case VehicleShape.reefer:
        final r = Rect.fromLTRB(x0, small ? 46 : 32, x1, chassisTop);
        _box(canvas, r);
        if (shape == VehicleShape.container) {
          for (var x = x0 + 8; x < x1 - 4; x += 9) {
            canvas.drawLine(Offset(x, r.top + 4), Offset(x, r.bottom - 4), _line(1));
          }
        } else {
          canvas.drawLine(Offset(x0 + 6, r.center.dy), Offset(x1 - 6, r.center.dy), _line(2, ink.accent));
        }
        if (shape == VehicleShape.reefer) {
          // The cooling unit on the front face.
          _shape(canvas, Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x0 + 3, r.top + 4, 14, 14), const Radius.circular(2))), ink.side, width: 1.5);
          canvas.drawCircle(Offset(x0 + 10, r.top + 11), 4, _line(1.2, ink.accent));
        }
        // Rear doors.
        canvas.drawLine(Offset(x1 - 3, r.top + 4), Offset(x1 - 3, r.bottom - 4), _line(1.2));
      case VehicleShape.open:
        final r = Rect.fromLTRB(x0, small ? 64 : 60, x1, chassisTop);
        _box(canvas, r);
        for (var x = x0 + 12; x < x1 - 6; x += 18) {
          canvas.drawLine(Offset(x, r.top + 3), Offset(x, r.bottom - 3), _line(1));
        }
        canvas.drawLine(Offset(x0 + 4, r.top + 5), Offset(x1 - 4, r.top + 5), _line(1.5, ink.accent));
      case VehicleShape.flatbed:
        _box(canvas, Rect.fromLTRB(x0, 74, x1, chassisTop));
        for (var x = x0 + 10; x < x1 - 6; x += 22) {
          canvas.drawCircle(Offset(x, 78), 1.6, _fill(ink.accent));
        }
      case VehicleShape.lowBed:
        // A gooseneck behind the cab, then a deck that sits low between the axle groups.
        final neck = Path()..moveTo(x0, 70)..lineTo(x0 + 30, 70)..lineTo(x0 + 40, 80)..lineTo(x1, 80)..lineTo(x1, chassisBottom)..lineTo(x0, chassisBottom)..close();
        _shape(canvas, neck, ink.body);
        canvas.drawLine(Offset(x0 + 44, 83), Offset(x1 - 6, 83), _line(1.5, ink.accent));
      case VehicleShape.tanker:
        final r = Rect.fromLTRB(x0, 40, x1, chassisTop - 2);
        final top = Path()..addRRect(RRect.fromRectAndRadius(r.shift(depth), Radius.circular(r.height / 2)));
        _shape(canvas, top, ink.side);
        _shape(canvas, Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(r.height / 2))), ink.body);
        canvas.drawLine(Offset(x0 + 14, r.center.dy), Offset(x1 - 14, r.center.dy), _line(2, ink.accent));
        for (final f in [0.3, 0.6]) {
          _shape(canvas, Path()..addRect(Rect.fromLTWH(x0 + (x1 - x0) * f, r.top - 5, 10, 5)), ink.side, width: 1.5);
        }
      case VehicleShape.tipper:
        final bin = Path()..moveTo(x0, 46)..lineTo(x1, 40)..lineTo(x1 - 6, chassisTop)..lineTo(x0 + 4, chassisTop)..close();
        final rim = Path()..moveTo(x0, 46)..relativeLineTo(depth.dx, depth.dy)..lineTo(x1 + depth.dx, 40 + depth.dy)..lineTo(x1, 40)..close();
        _shape(canvas, rim, ink.side);
        _shape(canvas, bin, ink.body);
        for (var x = x0 + 14; x < x1 - 10; x += 16) {
          canvas.drawLine(Offset(x, 47), Offset(x - 1, chassisTop - 3), _line(1));
        }
        canvas.drawLine(Offset(x0 + 6, 52), Offset(x1 - 8, 47), _line(2, ink.accent));
      case VehicleShape.carrier:
        _box(canvas, Rect.fromLTRB(x0, 74, x1, chassisTop));
        _box(canvas, Rect.fromLTRB(x0, 44, x1, 49));
        for (final deck in [74.0, 44.0]) {
          for (var x = x0 + 6; x + 40 < x1; x += 46) {
            _car(canvas, x, deck);
          }
        }
        for (final x in [x0 + 2, x1 - 4]) {
          canvas.drawLine(Offset(x, 49), Offset(x, 74), _line(2));
        }
      default:
        break;
    }
    _cab(canvas, top: small ? 46 : 38);
    for (var i = 0; i < wheels.length; i++) {
      _wheel(canvas, wheels[i], spec.axles[i]);
    }
  }

  /// A small generic car on a carrier deck (no make, no model).
  void _car(Canvas canvas, double x, double deckY) {
    final car = Path()
      ..moveTo(x, deckY - 3)
      ..lineTo(x, deckY - 11)
      ..quadraticBezierTo(x + 8, deckY - 12, x + 12, deckY - 19)
      ..lineTo(x + 28, deckY - 19)
      ..quadraticBezierTo(x + 33, deckY - 12, x + 40, deckY - 11)
      ..lineTo(x + 40, deckY - 3)
      ..close();
    _shape(canvas, car, ink.body, width: 1.5);
    for (final cx in [x + 9, x + 31]) {
      canvas.drawCircle(Offset(cx, deckY - 3), 3.5, _fill(ink.tyre));
    }
  }

  void _bike(Canvas canvas, List<double> wheels) {
    final (a, b) = (wheels[0], wheels[1]);
    // The delivery box sits on the carrier over the rear wheel.
    _box(canvas, Rect.fromLTRB(b - 28, 38, b + 10, 70));
    canvas.drawLine(Offset(b - 22, 54), Offset(b + 4, 54), _line(2, ink.accent));
    // Frame: rear wheel up to the seat, along to the steering head, fork down to the front wheel.
    final frame = Path()
      ..moveTo(b, wheelY)
      ..lineTo(b - 34, 74)
      ..lineTo(a + 30, 74)
      ..lineTo(a + 16, 56)
      ..lineTo(a, wheelY)
      ..moveTo(a + 10, 52)
      ..lineTo(a + 26, 52);
    canvas.drawPath(frame, _line(4));
    // Engine and seat.
    _shape(canvas, Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(a + 36, 76, 34, 14), const Radius.circular(4))), ink.side);
    _shape(canvas, Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(b - 58, 66, 30, 8), const Radius.circular(4))), ink.body);
    canvas.drawCircle(Offset(a + 18, 62), 2.5, _fill(ink.accent));
    _wheel(canvas, a, 1, r: 14);
    _wheel(canvas, b, 1, r: 14);
  }

  void _threeWheeler(Canvas canvas, List<double> wheels) {
    final open = spec.heightFt == 0;
    // The cargo bed follows the catalog length (a 5.5 ft auto is longer than a 4.5 ft e-rickshaw).
    final end = 88 + 18 * spec.lengthFt.clamp(3.0, 6.0);
    _chassis(canvas, 40, end);
    final cargo = Rect.fromLTRB(88, open ? 66 : 46, end, chassisTop);
    _box(canvas, cargo);
    if (!open) canvas.drawLine(Offset(cargo.left + 6, cargo.center.dy), Offset(cargo.right - 6, cargo.center.dy), _line(2, ink.accent));
    final cab = Path()
      ..moveTo(30, chassisBottom)
      ..lineTo(30, 62)
      ..quadraticBezierTo(32, 40, 56, 38)
      ..lineTo(84, 38)
      ..lineTo(84, chassisBottom)
      ..close();
    _shape(canvas, cab, ink.body);
    _shape(canvas, Path()..moveTo(38, 60)..quadraticBezierTo(40, 46, 56, 45)..lineTo(76, 45)..lineTo(76, 60)..close(), ink.glass, width: 1.5);
    canvas.drawCircle(const Offset(33, 74), 2.2, _fill(ink.accent));
    _wheel(canvas, wheels[0], spec.axles[0], r: 9);
    _wheel(canvas, wheels[1], spec.axles[1], r: 10);
  }

  void _crane(Canvas canvas, List<double> wheels) {
    _chassis(canvas, 16, 190);
    _box(canvas, const Rect.fromLTRB(70, 62, 190, chassisTop));
    _cab(canvas, top: 50, width: 40);
    // The boom, its pivot and a hook on a line.
    final pivot = const Offset(150, 60);
    const tip = Offset(250, 14);
    canvas.drawLine(pivot, tip, _line(9));
    canvas.drawLine(pivot, tip, _line(5, ink.accent));
    canvas.drawCircle(pivot, 6, _fill(ink.side));
    canvas.drawCircle(pivot, 6, _line(2));
    canvas.drawLine(tip, const Offset(250, 58), _line(1.5));
    final hook = Path()..moveTo(250, 58)..lineTo(250, 66)..arcToPoint(const Offset(243, 66), radius: const Radius.circular(4));
    canvas.drawPath(hook, _line(2.5));
    for (var i = 0; i < wheels.length; i++) {
      _wheel(canvas, wheels[i], spec.axles[i]);
    }
  }

  @override
  bool shouldRepaint(VehiclePainter old) => old.spec.id != spec.id || old.ink != ink;
}

/// A catalog vehicle drawn at [width] (height is 3/8 of it), named for screen readers.
class VehicleArt extends StatelessWidget {
  final VehicleSpec spec;
  final double width;

  /// Gold outline instead of the theme's colours.
  final bool gold;

  const VehicleArt(this.spec, {super.key, this.width = 160, this.gold = false});

  @override
  Widget build(BuildContext context) {
    final ink = gold ? VehicleInk.gold : VehicleInk.of(context.ds);
    return Semantics(
      image: true,
      label: tr(context, spec.nameKey),
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: SizedBox(width: width, height: width * VehiclePainter.h / VehiclePainter.w, child: CustomPaint(painter: VehiclePainter(spec, ink))),
        ),
      ),
    );
  }
}
