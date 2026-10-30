import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../theme/design_tokens.dart';
import '../widgets/common.dart';
import '../widgets/ds/app_button.dart';
import '../widgets/ds/app_text_field.dart';
import '../widgets/ds/app_top_bar.dart';
import '../widgets/ds/illustrations.dart';
import '../widgets/ds/sheet_kit.dart' show QuickChipRow;
import '../widgets/ds/skeleton.dart';
import 'vehicle_catalog.dart';
import 'vehicle_painter.dart';
import 'what_fits.dart';

/// E17: the vehicle catalog screens. Everything shown comes from the catalog asset (no reads, works offline);
/// all numbers carry the "approximate" note. [onPick] is set when a booking asks the person to choose one.
typedef VehiclePick = void Function(VehicleSpec v);
typedef CatalogLoader = Future<List<VehicleSpec>> Function();

/// 4.0 -> "4", 2.5 -> "2.5".
String fmtNum(double d) => d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(d * 10 == (d * 10).roundToDouble() ? 1 : 2);

String payloadText(BuildContext context, VehicleSpec v) => trf(context, 'vcuTons', {'min': fmtNum(v.minTons), 'max': fmtNum(v.maxTons)});

String sizeText(BuildContext context, VehicleSpec v) {
  String ft(double d) => trf(context, 'vcuFeet', {'n': fmtNum(d)});
  return '${ft(v.lengthFt)} x ${ft(v.widthFt)} x ${v.open ? tr(context, 'vcuOpenTop') : ft(v.heightFt)}';
}

/// The note under every number on these screens.
class ApproxNote extends StatelessWidget {
  const ApproxNote({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.info_outline_rounded, size: 18, color: c.textMuted),
      const SizedBox(width: DsSpace.s2),
      Expanded(child: Text(tr(context, 'vcuApprox'), style: DsType.bodySmall.copyWith(color: c.textMuted))),
    ]);
  }
}

/// Price band 1..5 as rupee signs, the rest faded; read out as "Price level 3 of 5".
class PriceBand extends StatelessWidget {
  final int band;
  const PriceBand(this.band, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Semantics(
      label: '${tr(context, 'vcuPrice')} $band / 5',
      child: ExcludeSemantics(
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '₹' * band, style: DsType.label.copyWith(color: c.textStrong)),
          TextSpan(text: '₹' * (5 - band), style: DsType.label.copyWith(color: c.border)),
        ])),
      ),
    );
  }
}

class VehicleCatalogScreen extends StatefulWidget {
  final VehiclePick? onPick;
  final CatalogLoader? load;
  const VehicleCatalogScreen({super.key, this.onPick, this.load});

  @override
  State<VehicleCatalogScreen> createState() => _VehicleCatalogScreenState();
}

class _VehicleCatalogScreenState extends State<VehicleCatalogScreen> {
  late Future<List<VehicleSpec>> _future;
  final _compare = <String>{};

  @override
  void initState() {
    super.initState();
    _future = (widget.load ?? VehicleCatalog.load)();
  }

  void _toggle(VehicleSpec v) {
    if (!_compare.contains(v.id) && _compare.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'vcuCompareMax'))));
      return;
    }
    setState(() {
      if (!_compare.remove(v.id)) _compare.add(v.id);
    });
  }

  void _retry() {
    final next = (widget.load ?? VehicleCatalog.load)();
    setState(() {
      _future = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<VehicleSpec>>(
      future: _future,
      builder: (context, snap) {
        final all = snap.data ?? const <VehicleSpec>[];
        return Scaffold(
          appBar: AppTopBar(title: tr(context, 'vcuTitle'), actions: [
            if (all.isNotEmpty)
              IconButton(
                key: const ValueKey('vcWhatFits'),
                tooltip: tr(context, 'vcuFitTitle'),
                icon: const Icon(Icons.calculate_outlined),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => WhatFitsScreen(all: all, onPick: widget.onPick))),
              ),
          ]),
          bottomNavigationBar: _compare.length >= 2
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(DsSpace.gutter),
                    child: AppButton(
                      key: const ValueKey('vcCompareGo'),
                      label: trf(context, 'vcuCompareN', {'n': _compare.length}),
                      icon: Icons.compare_arrows_rounded,
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VehicleCompareScreen(vehicles: [for (final v in all) if (_compare.contains(v.id)) v]))),
                    ),
                  ),
                )
              : null,
          body: switch (snap.connectionState) {
            ConnectionState.done when all.isEmpty => EmptyState(
                icon: Icons.local_shipping_outlined,
                illustration: IllustrationKind.error,
                title: tr(context, 'vcuLoadError'),
                action: AppButton(
                  key: const ValueKey('vcRetry'),
                  label: tr(context, 'retry'),
                  expand: false,
                  onPressed: _retry,
                ),
              ),
            ConnectionState.done => ListView.separated(
                key: const ValueKey('vcList'),
                padding: const EdgeInsets.all(DsSpace.gutter),
                itemCount: all.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: DsSpace.s3),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const ApproxNote(),
                      const SizedBox(height: DsSpace.s2),
                      Text(tr(context, 'vcuCompareHint'), style: DsType.bodySmall.copyWith(color: context.ds.textMuted)),
                    ]);
                  }
                  final v = all[i - 1];
                  return VehicleCard(
                    spec: v,
                    selected: _compare.contains(v.id),
                    onToggleCompare: () => _toggle(v),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VehicleSpecScreen(spec: v, onPick: widget.onPick))),
                  );
                },
              ),
            _ => const SkeletonList(),
          },
        );
      },
    );
  }
}

/// One catalog row: the drawing, the name, what it carries and its size, with a compare tick.
class VehicleCard extends StatelessWidget {
  final VehicleSpec spec;
  final VoidCallback onTap;
  final bool selected;
  final VoidCallback? onToggleCompare;

  const VehicleCard({super.key, required this.spec, required this.onTap, this.selected = false, this.onToggleCompare});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final name = tr(context, spec.nameKey);
    return Semantics(
      button: true,
      label: trf(context, 'vcuOpen', {'name': name}),
      excludeSemantics: false,
      child: AppCard(
        key: ValueKey('vc_${spec.id}'),
        onTap: onTap,
        padding: const EdgeInsets.all(DsSpace.s3),
        child: Row(children: [
          VehicleArt(spec, width: 96),
          const SizedBox(width: DsSpace.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: DsType.subtitle.copyWith(color: c.textStrong)),
              const SizedBox(height: DsSpace.s1),
              Text('${tr(context, spec.lifts ? 'vcuLifts' : 'vcuPayload')}: ${payloadText(context, spec)}', style: DsType.bodySmall.copyWith(color: c.text)),
              if (!spec.lifts) Text(sizeText(context, spec), style: DsType.bodySmall.copyWith(color: c.textMuted)),
              const SizedBox(height: DsSpace.s1),
              PriceBand(spec.priceBand),
            ]),
          ),
          if (onToggleCompare != null)
            Checkbox(
              key: ValueKey('vcCmp_${spec.id}'),
              value: selected,
              semanticLabel: trf(context, 'vcuPickCompare', {'name': name}),
              onChanged: (_) => onToggleCompare!(),
            ),
        ]),
      ),
    );
  }
}

class VehicleSpecScreen extends StatelessWidget {
  final VehicleSpec spec;
  final VehiclePick? onPick;
  const VehicleSpecScreen({super.key, required this.spec, this.onPick});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: DsSpace.s1),
          child: MergeSemantics(
            child: Wrap(spacing: DsSpace.s2, children: [
              Text('$label:', style: DsType.body.copyWith(color: c.textMuted)),
              Text(value, style: DsType.body.copyWith(color: c.textStrong, fontWeight: FontWeight.w700)),
            ]),
          ),
        );
    Widget chips(List<String> labels) => Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s2, children: [
          for (final l in labels) Chip(label: Text(l, style: DsType.bodySmall.copyWith(color: c.text)), backgroundColor: c.chip, side: BorderSide.none),
        ]);
    return Scaffold(
      appBar: AppTopBar(title: tr(context, spec.nameKey)),
      bottomNavigationBar: onPick == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(DsSpace.gutter),
                child: AppButton(key: const ValueKey('vcPick'), label: tr(context, 'vcuPick'), icon: Icons.check_rounded, onPressed: () => onPick!(spec)),
              ),
            ),
      body: ListView(padding: const EdgeInsets.all(DsSpace.gutter), children: [
        Center(child: VehicleArt(spec, width: 300)),
        const SizedBox(height: DsSpace.s4),
        Text(tr(context, 'vcuChooseWhen'), style: DsType.label.copyWith(color: c.textMuted)),
        const SizedBox(height: DsSpace.s1),
        Text(tr(context, spec.whenKey), style: DsType.body.copyWith(color: c.textStrong)),
        const SizedBox(height: DsSpace.s4),
        row(tr(context, spec.lifts ? 'vcuLifts' : 'vcuPayload'), payloadText(context, spec)),
        if (!spec.lifts) ...[
          row(tr(context, 'vcuLength'), trf(context, 'vcuFeet', {'n': fmtNum(spec.lengthFt)})),
          row(tr(context, 'vcuWidth'), trf(context, 'vcuFeet', {'n': fmtNum(spec.widthFt)})),
          row(tr(context, 'vcuHeight'), spec.open ? tr(context, 'vcuOpenTop') : trf(context, 'vcuFeet', {'n': fmtNum(spec.heightFt)})),
          if (!spec.open) row(tr(context, 'vcuVolume'), trf(context, 'vcuCft', {'n': spec.volumeCft.round()})),
        ],
        row(tr(context, 'vcuWheels'), '${spec.wheels}'),
        Padding(padding: const EdgeInsets.symmetric(vertical: DsSpace.s1), child: Row(children: [Text('${tr(context, 'vcuPrice')}: ', style: DsType.body.copyWith(color: c.textMuted)), PriceBand(spec.priceBand)])),
        const SizedBox(height: DsSpace.s3),
        Text(tr(context, 'vcuBody'), style: DsType.label.copyWith(color: c.textMuted)),
        const SizedBox(height: DsSpace.s1),
        chips([for (final b in spec.bodies) tr(context, 'body_$b')]),
        const SizedBox(height: DsSpace.s3),
        Text(tr(context, 'vcuGoods'), style: DsType.label.copyWith(color: c.textMuted)),
        const SizedBox(height: DsSpace.s1),
        chips([for (final g in spec.goods) tr(context, 'vcGoods_$g')]),
        if (!spec.lifts) ...[
          const SizedBox(height: DsSpace.s5),
          Text(tr(context, 'vcuSizeTitle'), style: DsType.subtitle.copyWith(color: c.textStrong)),
          const SizedBox(height: DsSpace.s2),
          SizeComparison(spec: spec),
        ],
        const SizedBox(height: DsSpace.s4),
        const ApproxNote(),
      ]),
    );
  }
}

/// The load space drawn from the side at true scale next to a person (5.5 ft), a car (13 x 5 ft) and a door
/// (7 x 3 ft). The picture is read out as one sentence.
class SizeComparison extends StatelessWidget {
  final VehicleSpec spec;
  const SizeComparison({super.key, required this.spec});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final h = spec.open ? 2.0 : spec.heightFt;
    return Semantics(
      image: true,
      label: trf(context, 'vcuSizeSay', {'l': fmtNum(spec.lengthFt), 'h': spec.open ? tr(context, 'vcuOpenTop') : fmtNum(spec.heightFt)}),
      child: ExcludeSemantics(
        child: LayoutBuilder(builder: (context, box) {
          final labels = [tr(context, 'vcuPerson'), tr(context, 'vcuCar'), tr(context, 'vcuDoor')];
          return SizedBox(
            width: box.maxWidth,
            height: 150,
            child: CustomPaint(painter: SizeComparisonPainter(lengthFt: spec.lengthFt, heightFt: h, open: spec.open, c: c, labels: labels, textScaler: MediaQuery.textScalerOf(context))),
          );
        }),
      ),
    );
  }
}

class SizeComparisonPainter extends CustomPainter {
  final double lengthFt, heightFt;
  final bool open;
  final DsColors c;
  final List<String> labels;
  final TextScaler textScaler;
  const SizeComparisonPainter({required this.lengthFt, required this.heightFt, required this.open, required this.c, required this.labels, this.textScaler = TextScaler.noScaling});

  static const person = (1.6, 5.5), car = (13.0, 5.0), door = (3.0, 7.0);
  static const gapFt = 2.0;

  /// Feet to pixels: everything (load space, person, car, door and the gaps) fits the width and height.
  static double scaleFor(Size size, double lengthFt, double heightFt) {
    final totalW = lengthFt + person.$1 + car.$1 + door.$1 + gapFt * 4;
    final tallest = [heightFt, person.$2, car.$2, door.$2].reduce((a, b) => a > b ? a : b);
    final byW = size.width / totalW, byH = (size.height - 28) / tallest;
    return byW < byH ? byW : byH;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = scaleFor(size, lengthFt, heightFt);
    final ground = size.height - 24;
    final line = Paint()..color = c.textStrong..style = PaintingStyle.stroke..strokeWidth = 2;
    final fill = Paint()..color = c.tint;
    final soft = Paint()..color = c.chip;
    canvas.drawLine(Offset(0, ground), Offset(size.width, ground), Paint()..color = c.border..strokeWidth = 1);
    var x = gapFt * s;
    // The load space.
    final box = Rect.fromLTWH(x, ground - heightFt * s, lengthFt * s, heightFt * s);
    canvas.drawRect(box, fill);
    if (open) {
      canvas.drawLine(box.topLeft, box.bottomLeft, line);
      canvas.drawLine(box.bottomLeft, box.bottomRight, line);
      canvas.drawLine(box.bottomRight, box.topRight, line);
    } else {
      canvas.drawRect(box, line);
    }
    x = box.right + gapFt * s;
    // A person: head and body.
    final pw = person.$1 * s, ph = person.$2 * s;
    canvas.drawCircle(Offset(x + pw / 2, ground - ph + pw * 0.35), pw * 0.35, soft);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, ground - ph + pw * 0.75, pw, ph - pw * 0.75), Radius.circular(pw * 0.4)), soft);
    _label(canvas, labels[0], x + pw / 2, ground);
    x += pw + gapFt * s;
    // A car.
    final cw = car.$1 * s, ch = car.$2 * s;
    final carPath = Path()
      ..moveTo(x, ground - ch * 0.15)
      ..lineTo(x, ground - ch * 0.5)
      ..lineTo(x + cw * 0.22, ground - ch * 0.55)
      ..lineTo(x + cw * 0.35, ground - ch)
      ..lineTo(x + cw * 0.72, ground - ch)
      ..lineTo(x + cw * 0.85, ground - ch * 0.55)
      ..lineTo(x + cw, ground - ch * 0.5)
      ..lineTo(x + cw, ground - ch * 0.15)
      ..close();
    canvas.drawPath(carPath, soft);
    _label(canvas, labels[1], x + cw / 2, ground);
    x += cw + gapFt * s;
    // A door.
    final dw = door.$1 * s, dh = door.$2 * s;
    canvas.drawRect(Rect.fromLTWH(x, ground - dh, dw, dh), soft);
    _label(canvas, labels[2], x + dw / 2, ground);
  }

  void _label(Canvas canvas, String text, double cx, double ground) {
    final tp = TextPainter(text: TextSpan(text: text, style: DsType.bodySmall.copyWith(color: c.textMuted)), textDirection: TextDirection.ltr, textScaler: textScaler, maxLines: 1, ellipsis: '…')
      ..layout(maxWidth: 80);
    tp.paint(canvas, Offset(cx - tp.width / 2, ground + 4));
  }

  @override
  bool shouldRepaint(SizeComparisonPainter old) => old.lengthFt != lengthFt || old.heightFt != heightFt || old.open != open || old.c != c || old.labels.join() != labels.join();
}

/// Two or three vehicles side by side, one section per measure (safe at large text and in narrow phones).
class VehicleCompareScreen extends StatelessWidget {
  final List<VehicleSpec> vehicles;
  const VehicleCompareScreen({super.key, required this.vehicles});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    Widget section(String title, String Function(VehicleSpec v) value) => Padding(
          padding: const EdgeInsets.only(bottom: DsSpace.s4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: DsType.label.copyWith(color: c.textMuted)),
            for (final v in vehicles)
              MergeSemantics(
                child: Padding(
                  padding: const EdgeInsets.only(top: DsSpace.s1),
                  child: Wrap(spacing: DsSpace.s2, children: [
                    Text(tr(context, v.nameKey), style: DsType.body.copyWith(color: c.text)),
                    Text(value(v), style: DsType.body.copyWith(color: c.textStrong, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
          ]),
        );
    return Scaffold(
      appBar: AppTopBar(title: tr(context, 'vcuCompareTitle')),
      body: ListView(padding: const EdgeInsets.all(DsSpace.gutter), children: [
        Wrap(spacing: DsSpace.s3, runSpacing: DsSpace.s3, children: [
          for (final v in vehicles)
            SizedBox(
              width: 140,
              child: Column(children: [
                VehicleArt(v, width: 140),
                Text(tr(context, v.nameKey), textAlign: TextAlign.center, style: DsType.bodySmall.copyWith(color: c.textStrong)),
              ]),
            ),
        ]),
        const SizedBox(height: DsSpace.s4),
        section(tr(context, 'vcuPayload'), (v) => payloadText(context, v)),
        section(tr(context, 'vcuLength'), (v) => v.lifts ? '-' : trf(context, 'vcuFeet', {'n': fmtNum(v.lengthFt)})),
        section(tr(context, 'vcuHeight'), (v) => v.lifts ? '-' : (v.open ? tr(context, 'vcuOpenTop') : trf(context, 'vcuFeet', {'n': fmtNum(v.heightFt)}))),
        section(tr(context, 'vcuVolume'), (v) => v.open || v.lifts ? '-' : trf(context, 'vcuCft', {'n': v.volumeCft.round()})),
        section(tr(context, 'vcuWheels'), (v) => '${v.wheels}'),
        section(tr(context, 'vcuPrice'), (v) => '${'₹' * v.priceBand} (${v.priceBand}/5)'),
        const ApproxNote(),
      ]),
    );
  }
}

/// Weight (required), space and longest item (optional), kind of goods (optional) -> the vehicles that fit.
class WhatFitsScreen extends StatefulWidget {
  final List<VehicleSpec> all;
  final VehiclePick? onPick;
  const WhatFitsScreen({super.key, required this.all, this.onPick});

  @override
  State<WhatFitsScreen> createState() => _WhatFitsScreenState();
}

class _WhatFitsScreenState extends State<WhatFitsScreen> {
  final _weight = TextEditingController(), _volume = TextEditingController(), _longest = TextEditingController();
  String? _goods;
  String? _weightError, _volumeError, _longestError;
  List<VehicleSpec>? _result;

  @override
  void dispose() {
    _weight.dispose();
    _volume.dispose();
    _longest.dispose();
    super.dispose();
  }

  /// null for empty, NaN for something that is not a number.
  static double? _num(String s) {
    final t = s.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t) ?? double.nan;
  }

  void _go() {
    final w = _num(_weight.text), vol = _num(_volume.text), len = _num(_longest.text);
    setState(() {
      _weightError = (w == null || w.isNaN || w <= 0 || w > 1000) ? tr(context, 'vcuFitBadWeight') : null;
      _volumeError = (vol != null && (vol.isNaN || vol < 0)) ? tr(context, 'vcuFitBadNumber') : null;
      _longestError = (len != null && (len.isNaN || len < 0)) ? tr(context, 'vcuFitBadNumber') : null;
      if (_weightError != null || _volumeError != null || _longestError != null) {
        _result = null;
        return;
      }
      _result = whatFits(widget.all, FitRequest(tons: w!, volumeCft: vol, longestFt: len, goods: _goods));
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final numbers = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')), LengthLimitingTextInputFormatter(7)];
    final result = _result;
    return Scaffold(
      appBar: AppTopBar(title: tr(context, 'vcuFitTitle')),
      body: ListView(padding: const EdgeInsets.all(DsSpace.gutter), children: [
        AppTextField(key: const ValueKey('vcFitWeight'), label: tr(context, 'vcuFitWeight'), controller: _weight, error: _weightError, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: numbers, textInputAction: TextInputAction.next),
        const SizedBox(height: DsSpace.s3),
        AppTextField(key: const ValueKey('vcFitVolume'), label: tr(context, 'vcuFitVolume'), controller: _volume, error: _volumeError, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: numbers, textInputAction: TextInputAction.next),
        const SizedBox(height: DsSpace.s3),
        AppTextField(key: const ValueKey('vcFitLongest'), label: tr(context, 'vcuFitLongest'), controller: _longest, error: _longestError, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: numbers, onSubmitted: (_) => _go()),
        const SizedBox(height: DsSpace.s3),
        Text(tr(context, 'vcuFitGoods'), style: DsType.label.copyWith(color: c.textMuted)),
        const SizedBox(height: DsSpace.s1),
        QuickChipRow<String?>(
          padding: EdgeInsets.zero,
          options: [(null, tr(context, 'vcuFitAny')), for (final g in VehicleCatalog.goodsKinds) (g, tr(context, 'vcGoods_$g'))],
          selected: _goods,
          onChanged: (g) => setState(() => _goods = g),
        ),
        const SizedBox(height: DsSpace.s4),
        AppButton(key: const ValueKey('vcFitGo'), label: tr(context, 'vcuFitGo'), icon: Icons.local_shipping_rounded, onPressed: _go),
        const SizedBox(height: DsSpace.s4),
        if (result != null && result.isEmpty)
          Semantics(liveRegion: true, child: Text(tr(context, 'vcuFitNone'), key: const ValueKey('vcFitNone'), style: DsType.body.copyWith(color: c.textStrong))),
        if (result != null && result.isNotEmpty) ...[
          Semantics(liveRegion: true, header: true, child: Text(tr(context, 'vcuFitBest'), style: DsType.label.copyWith(color: c.accentStrong))),
          const SizedBox(height: DsSpace.s1),
          for (final v in result.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: DsSpace.s3),
              child: VehicleCard(spec: v, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VehicleSpecScreen(spec: v, onPick: widget.onPick)))),
            ),
          const ApproxNote(),
        ],
      ]),
    );
  }
}
