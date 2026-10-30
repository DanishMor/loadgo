import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n.dart';
import '../pricing/fare_calculator.dart';
import '../theme/design_tokens.dart';
import '../widgets/common.dart';
import '../widgets/ds/route_ribbon.dart';
import '../widgets/fare_breakdown.dart' show surgeLabelKey;
import 'quote_summary.dart';

/// E31: the words of a fare line for a shared quote, the same as the price card shows.
String quoteLineLabel(BuildContext context, FareBreakdown f, String chargeKey) => switch (chargeKey) {
      'baseFare' => tr(context, 'fareBase'),
      'distanceCharge' => trf(context, 'fareDistance', {'km': f.distanceKm}),
      'rentalCharge' => tr(context, 'fareRental'),
      'extraKmCharge' => tr(context, 'fareExtraKm'),
      'extraHourCharge' => tr(context, 'fareExtraHours'),
      'helperCharge' => tr(context, 'fareHelpers'),
      'itemHandlingCharge' => tr(context, 'fareItemHandling'),
      'floorCharge' => tr(context, 'fareFloors'),
      'packingCharge' => tr(context, 'farePacking'),
      'loadingCharge' => tr(context, 'fareLoading'),
      'unloadingCharge' => tr(context, 'fareUnloading'),
      'waitingCharge' => tr(context, 'fareWaiting'),
      'extraStopCharge' => tr(context, 'fareExtraStops'),
      'minimumFareAdjustment' => tr(context, 'fareMinimum'),
      'surgeCharge' => trf(context, surgeLabelKey(f.surgeKind), {'p': f.surgePercent}),
      'platformFee' => trf(context, 'farePlatform', {'p': formatNum(f.platformFeePercent)}),
      'gst' => trf(context, 'fareGst', {'p': formatNum(f.gstPercent)}),
      _ => chargeKey,
    };

Map<String, String> quoteLabels(BuildContext context) => {
      'route': tr(context, 'qsRoute'),
      'goods': tr(context, 'qsGoods'),
      'vehicle': tr(context, 'qsVehicle'),
      'when': tr(context, 'wzWhen'),
      'total': tr(context, 'fareTotal'),
      'ref': tr(context, 'qsRef'),
      'note': tr(context, 'qsNote'),
    };

enum QuoteShareKind { image, pdf, text }

/// E31 (flag quoteShare): a preview of the summary card and three ways to send it. [onShare] is a test hook.
Future<void> showQuoteShare(BuildContext context, QuoteSummary s, {Future<void> Function(QuoteShareKind kind, Uint8List? bytes, String text)? onShare}) =>
    showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => _QuoteShareSheet(summary: s, onShare: onShare));

class _QuoteShareSheet extends StatefulWidget {
  final QuoteSummary summary;
  final Future<void> Function(QuoteShareKind kind, Uint8List? bytes, String text)? onShare;
  const _QuoteShareSheet({required this.summary, this.onShare});

  @override
  State<_QuoteShareSheet> createState() => _QuoteShareSheetState();
}

class _QuoteShareSheetState extends State<_QuoteShareSheet> {
  final _card = GlobalKey();
  bool _busy = false;

  Future<Uint8List?> _png() async {
    final boundary = _card.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  Future<void> _go(QuoteShareKind kind) async {
    setState(() => _busy = true);
    final labels = quoteLabels(context);
    final text = widget.summary.asText(labels);
    try {
      Uint8List? bytes;
      if (kind == QuoteShareKind.image) bytes = await _png();
      if (kind == QuoteShareKind.pdf) bytes = await widget.summary.toPdf(labels);
      if (widget.onShare != null) {
        await widget.onShare!(kind, bytes, text);
      } else if (kind == QuoteShareKind.pdf && bytes != null) {
        await Printing.sharePdf(bytes: bytes, filename: 'quote-${widget.summary.reference.isEmpty ? 'load20' : widget.summary.reference}.pdf');
      } else if (kind == QuoteShareKind.image && bytes != null) {
        await SharePlus.instance.share(ShareParams(files: [XFile.fromData(bytes, mimeType: 'image/png', name: 'quote.png')], text: text));
      } else {
        await SharePlus.instance.share(ShareParams(text: text));
      }
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'qsFailed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final s = widget.summary;
    Widget line(String k, String v, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(k, style: (strong ? DsType.subtitle : DsType.bodySmall).copyWith(color: strong ? c.textStrong : c.textMuted))),
            Flexible(child: Text(v, textAlign: TextAlign.end, style: (strong ? DsType.subtitle : DsType.bodySmall).copyWith(color: c.textStrong))),
          ]),
        );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(DsSpace.gutter, 0, DsSpace.gutter, DsSpace.gutter),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          RepaintBoundary(
            key: _card,
            child: Container(
              key: const ValueKey('qsCard'),
              padding: const EdgeInsets.all(DsSpace.s4),
              decoration: BoxDecoration(color: c.surface, borderRadius: DsRadius.all(DsRadius.lg), border: Border.all(color: c.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(s.title, style: DsType.title.copyWith(color: c.textStrong)),
                const SizedBox(height: DsSpace.s2),
                RouteRibbon(from: s.pickup, to: s.drop),
                const SizedBox(height: DsSpace.s2),
                if (s.goods.isNotEmpty) line(tr(context, 'qsGoods'), '${s.goods}${s.weightTons == null ? '' : ', ${formatNum(s.weightTons!)} T'}'),
                line(tr(context, 'qsVehicle'), s.vehicle),
                if (s.when.isNotEmpty) line(tr(context, 'wzWhen'), s.when),
                const Divider(),
                for (final (l, p) in s.lines) line(l, formatPaise(p)),
                line(tr(context, 'fareTotal'), formatPaise(s.pricePaise), strong: true),
                if (s.reference.isNotEmpty) line(tr(context, 'qsRef'), s.reference),
                const SizedBox(height: DsSpace.s2),
                Text(tr(context, 'qsNote'), style: DsType.caption.copyWith(color: c.textMuted)),
              ]),
            ),
          ),
          const SizedBox(height: DsSpace.s3),
          Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s2, children: [
            FilledButton.icon(key: const ValueKey('qsImage'), onPressed: _busy ? null : () => _go(QuoteShareKind.image), icon: const Icon(Icons.image_outlined), label: Text(tr(context, 'qsImage'))),
            OutlinedButton.icon(key: const ValueKey('qsPdf'), onPressed: _busy ? null : () => _go(QuoteShareKind.pdf), icon: const Icon(Icons.picture_as_pdf_outlined), label: Text(tr(context, 'qsPdf'))),
            TextButton.icon(key: const ValueKey('qsText'), onPressed: _busy ? null : () => _go(QuoteShareKind.text), icon: const Icon(Icons.notes_rounded), label: Text(tr(context, 'qsText'))),
          ]),
        ]),
      ),
    );
  }
}
