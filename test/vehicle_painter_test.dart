import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/theme/design_tokens.dart';
import 'package:transport_app/core/vehicles/vehicle_catalog.dart';
import 'package:transport_app/core/vehicles/vehicle_painter.dart';

/// E16: the parametric vehicle painter. Silhouettes are kept in test/goldens/vehicles (alpha masks, 160 x 60) and
/// compared with a small tolerance, so anti-aliasing differences between Windows and the Linux CI do not fail it.
/// After a deliberate change to the drawing: flutter test test/vehicle_painter_test.dart --dart-define=UPDATE_SILHOUETTES=true
const _update = bool.fromEnvironment('UPDATE_SILHOUETTES');
const _gw = 160, _gh = 60;

Future<Uint8List> _rgba(WidgetTester t, VehicleSpec v, VehicleInk ink, int w, int h) async {
  late Uint8List out;
  await t.runAsync(() async {
    final rec = ui.PictureRecorder();
    VehiclePainter(v, ink).paint(Canvas(rec), Size(w.toDouble(), h.toDouble()));
    final img = await rec.endRecording().toImage(w, h);
    out = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
    img.dispose();
  });
  return out;
}

void main() {
  final all = VehicleCatalog.parse(File(VehicleCatalog.asset).readAsStringSync());
  VehicleSpec v(String id) => VehicleCatalog.byId(all, id)!;

  test('each catalog type gets the shape it should', () {
    expect(v('bike').shape, VehicleShape.bike);
    expect(v('auto_3w').shape, VehicleShape.threeWheeler);
    expect(v('lcv_14ft').shape, VehicleShape.open);
    expect(v('icv_24ft').shape, VehicleShape.closed);
    expect(v('box_32ft_mxl').shape, VehicleShape.container);
    expect(v('reefer').shape, VehicleShape.reefer);
    expect(v('trailer_flatbed').shape, VehicleShape.flatbed);
    expect(v('low_bed').shape, VehicleShape.lowBed);
    expect(v('tanker').shape, VehicleShape.tanker);
    expect(v('tipper').shape, VehicleShape.tipper);
    expect(v('car_carrier').shape, VehicleShape.carrier);
    expect(v('hydra_crane').shape, VehicleShape.crane);
  });

  test('one visible wheel per axle, front to back, inside the drawing, cab axle first', () {
    for (final s in all) {
      final xs = VehiclePainter.wheelCenters(s);
      expect(xs.length, s.axles.length, reason: s.id);
      for (var i = 1; i < xs.length; i++) {
        expect(xs[i] - xs[i - 1], greaterThanOrEqualTo(20), reason: '${s.id}: wheels overlap');
      }
      expect(xs.first, greaterThan(10));
      expect(xs.last + 14, lessThan(VehiclePainter.w), reason: s.id);
    }
    // A longer truck has its rear axle further back.
    expect(VehiclePainter.wheelCenters(v('icv_22ft')).last, greaterThan(VehiclePainter.wheelCenters(v('lcv_14ft')).last));
  });

  testWidgets('every vehicle stays inside its canvas (nothing drawn on the outer border)', (t) async {
    for (final s in all) {
      final px = await _rgba(t, s, VehicleInk.mono(DsBrand.white), 320, 120);
      var onEdge = 0;
      for (var x = 0; x < 320; x++) {
        if (px[(x) * 4 + 3] > 0 || px[(119 * 320 + x) * 4 + 3] > 0) onEdge++;
      }
      for (var y = 0; y < 120; y++) {
        if (px[(y * 320) * 4 + 3] > 0 || px[(y * 320 + 319) * 4 + 3] > 0) onEdge++;
      }
      expect(onEdge, 0, reason: s.id);
    }
  });

  testWidgets('silhouettes match the stored ones (at most 1.5% of pixels differ)', (t) async {
    Directory('test/goldens/vehicles').createSync(recursive: true);
    for (final s in all) {
      final file = File('test/goldens/vehicles/${s.id}.png');
      final px = await _rgba(t, s, VehicleInk.mono(DsBrand.white), _gw, _gh);
      if (_update || !file.existsSync()) {
        await t.runAsync(() async {
          final buf = await ui.ImmutableBuffer.fromUint8List(px);
          final desc = ui.ImageDescriptor.raw(buf, width: _gw, height: _gh, pixelFormat: ui.PixelFormat.rgba8888);
          final img = (await (await desc.instantiateCodec()).getNextFrame()).image;
          file.writeAsBytesSync((await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());
        });
        continue;
      }
      late Uint8List stored;
      await t.runAsync(() async {
        final img = (await (await ui.instantiateImageCodec(file.readAsBytesSync())).getNextFrame()).image;
        stored = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
      });
      var diff = 0;
      for (var i = 3; i < px.length; i += 4) {
        if ((px[i] > 127) != (stored[i] > 127)) diff++;
      }
      expect(diff / (_gw * _gh), lessThanOrEqualTo(0.015), reason: '${s.id}: $diff pixels differ (run with UPDATE_SILHOUETTES=true after a deliberate change)');
    }
  });

  test('different types really look different (no two silhouettes stored equal)', () {
    final seen = <String, String>{};
    for (final s in all) {
      final f = File('test/goldens/vehicles/${s.id}.png');
      if (!f.existsSync()) continue;
      final key = f.readAsBytesSync().join(',');
      expect(seen[key], isNull, reason: '${s.id} looks the same as ${seen[key]}');
      seen[key] = s.id;
    }
  });

  test('ink comes from the theme tokens; Midnight keeps tyres dark; gold draws outlines only', () {
    final light = VehicleInk.of(DsColors.signature), dark = VehicleInk.of(DsColors.midnight);
    expect(light.body, DsColors.signature.surface);
    expect(dark.body, DsColors.midnight.surface);
    expect(dark.tyre.computeLuminance(), lessThan(0.2));
    expect(light.tyre.computeLuminance(), lessThan(0.2));
    expect(VehicleInk.gold.line, DsLuxe.gold);
    expect(VehicleInk.gold.body.a, 0);
  });

  test('repaints only when the vehicle or the ink changes', () {
    final a = VehiclePainter(v('tanker'), VehicleInk.of(DsColors.signature));
    expect(a.shouldRepaint(VehiclePainter(v('tanker'), VehicleInk.of(DsColors.signature))), isFalse);
    expect(a.shouldRepaint(VehiclePainter(v('tipper'), VehicleInk.of(DsColors.signature))), isTrue);
    expect(a.shouldRepaint(VehiclePainter(v('tanker'), VehicleInk.gold)), isTrue);
  });

  test('painting all 27 vehicles is cheap (budget: under 150 ms on a laptop, LowEndMode safe)', () {
    final sw = Stopwatch()..start();
    for (var round = 0; round < 3; round++) {
      for (final s in all) {
        final rec = ui.PictureRecorder();
        VehiclePainter(s, VehicleInk.of(DsColors.signature)).paint(Canvas(rec), const Size(320, 120));
        rec.endRecording().dispose();
      }
    }
    expect(sw.elapsedMilliseconds / 3, lessThan(150));
  });

  testWidgets('VehicleArt is one image named in the reader language, in light and dark', (t) async {
    final handle = t.ensureSemantics();
    for (final b in Brightness.values) {
      await t.pumpWidget(LanguageScope(
        notifier: ValueNotifier(AppLanguage.hindi),
        child: MaterialApp(theme: AppTheme.build(b, style: ThemeStyle.signature), home: Scaffold(body: Center(child: VehicleArt(v('lcv_14ft'), width: 200)))),
      ));
      expect(find.bySemanticsLabel(T.get('vc_lcv_14ft', AppLanguage.hindi)), findsOneWidget);
      expect(t.getSize(find.byType(CustomPaint).last), const Size(200, 75));
      expect(t.takeException(), isNull);
    }
    handle.dispose();
  });
}
