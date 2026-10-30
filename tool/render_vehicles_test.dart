// E16: draws every catalog vehicle with the parametric painter into three contact sheets (Signature, Midnight,
// gold outline), so the art can be reviewed without a phone:
//   flutter test tool/render_vehicles_test.dart                 -> docs/gallery/vehicles
//   flutter test tool/render_vehicles_test.dart --dart-define=OUT=C:\temp\v
// It builds no app and opens no emulator.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/theme/design_tokens.dart';
import 'package:transport_app/core/vehicles/vehicle_catalog.dart';
import 'package:transport_app/core/vehicles/vehicle_painter.dart';

import 'render_kit_test.dart' as r;

void main() {
  testWidgets('draw the vehicle gallery', (t) async {
    await t.runAsync(r.loadFonts);
    const out = String.fromEnvironment('OUT', defaultValue: 'docs/gallery/vehicles');
    Directory(out).createSync(recursive: true);
    final all = VehicleCatalog.parse(File(VehicleCatalog.asset).readAsStringSync());
    const cols = 3, cellW = 320.0, cellH = 150.0;
    final rows = (all.length / cols).ceil();
    for (final (name, ink, bg, text) in [
      ('signature', VehicleInk.of(DsColors.signature), DsColors.signature.bg, DsColors.signature.textMuted),
      ('midnight', VehicleInk.of(DsColors.midnight), DsColors.midnight.bg, DsColors.midnight.textMuted),
      ('gold', VehicleInk.gold, DsLuxe.ink, DsLuxe.goldLight),
    ]) {
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      canvas.drawRect(Rect.fromLTWH(0, 0, cols * cellW, rows * cellH), Paint()..color = bg);
      for (var i = 0; i < all.length; i++) {
        final v = all[i];
        canvas.save();
        canvas.translate((i % cols) * cellW, (i ~/ cols) * cellH);
        VehiclePainter(v, ink).paint(canvas, const Size(cellW, 120));
        final label = TextPainter(
          text: TextSpan(text: '${T.get(v.nameKey, AppLanguage.english)}  (${v.wheels} wheels)', style: DsType.bodySmall.copyWith(color: text)),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: cellW - 16);
        label.paint(canvas, const Offset(8, 124));
        canvas.restore();
      }
      await t.runAsync(() async {
        final img = await rec.endRecording().toImage((cols * cellW).toInt(), (rows * cellH).toInt());
        final png = (await img.toByteData(format: ui.ImageByteFormat.png))!;
        File('$out/$name.png').writeAsBytesSync(png.buffer.asUint8List());
        img.dispose();
      });
    }
    expect(File('$out/signature.png').lengthSync(), greaterThan(10000));
  });
}
