import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../errors/error_text.dart';
import '../l10n/l10n.dart';
import '../services/vehicle_type_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/common.dart';
import '../widgets/ds/app_button.dart';
import '../widgets/ds/app_top_bar.dart';
import '../widgets/ds/route_ribbon.dart';
import '../widgets/ds/skeleton.dart';
import '../widgets/ds/status_badge.dart';
import '../widgets/live_stream.dart' show ErrorState;
import 'lane_rfq.dart';

StatusTone _tone(String s) => switch (s) { 'open' => StatusTone.progress, 'awarded' => StatusTone.success, _ => StatusTone.neutral };

Widget _rfqCard(BuildContext context, LaneRfq r, {VoidCallback? onTap, Widget? trailing}) {
  final c = context.ds;
  return Padding(
    padding: const EdgeInsets.only(bottom: DsSpace.s2),
    child: AppCard(
      key: ValueKey('lr_${r.id}'),
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        RouteRibbon(from: r.fromCity, to: r.toCity),
        const SizedBox(height: DsSpace.s2),
        Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s1, crossAxisAlignment: WrapCrossAlignment.center, children: [
          StatusBadge(label: tr(context, 'tdrStatus_${r.status}'), tone: _tone(r.status)),
          Text(trf(context, 'tdrVolume', {'n': r.tripsPerMonth, 'm': r.months, 'type': r.vehicleType}), style: DsType.bodySmall.copyWith(color: c.text)),
          if (r.closesAt != null && r.status == 'open') Text(trf(context, 'tdrCloses', {'date': formatDate(r.closesAt!)}), style: DsType.caption.copyWith(color: c.textMuted)),
        ]),
        if (r.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: DsSpace.s1), child: Text(r.note, style: DsType.bodySmall.copyWith(color: c.textMuted))),
        if (r.awardedRatePaise != null) Padding(padding: const EdgeInsets.only(top: DsSpace.s1), child: Text(trf(context, 'tdrAwardedRate', {'amount': formatPaise(r.awardedRatePaise!)}), style: DsType.label.copyWith(color: c.success))),
        ?trailing,
      ]),
    ),
  );
}

/// E30 (flag laneRfq): the business side: my tenders, a new one, and the bids on each.
class LaneTendersScreen extends StatelessWidget {
  final String ownerName;
  final Stream<List<LaneRfq>> Function()? mine;
  const LaneTendersScreen({super.key, required this.ownerName, this.mine});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Scaffold(
      appBar: AppTopBar(title: tr(context, 'tdrTitle')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('tdrNew'),
        onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => _NewTenderSheet(ownerName: ownerName)),
        icon: const Icon(Icons.add_rounded),
        label: Text(tr(context, 'tdrNew')),
      ),
      body: StreamBuilder<List<LaneRfq>>(
        stream: (mine ?? LaneRfqService.watchMine)(),
        builder: (context, snap) {
          if (snap.hasError) return ErrorState(error: snap.error);
          if (!snap.hasData) return const Padding(padding: EdgeInsets.all(DsSpace.gutter), child: SkeletonList(count: 3));
          final list = snap.data!;
          return ListView(padding: const EdgeInsets.fromLTRB(DsSpace.gutter, DsSpace.gutter, DsSpace.gutter, 96), children: [
            Text(tr(context, 'tdrHelp'), style: DsType.bodySmall.copyWith(color: c.textMuted)),
            const SizedBox(height: DsSpace.s3),
            if (list.isEmpty) Text(tr(context, 'tdrNone'), key: const ValueKey('tdrNone'), style: DsType.body.copyWith(color: c.textMuted)),
            for (final r in list) _rfqCard(context, r, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LaneTenderBidsScreen(rfq: r)))),
          ]);
        },
      ),
    );
  }
}

class _NewTenderSheet extends StatefulWidget {
  final String ownerName;
  const _NewTenderSheet({required this.ownerName});

  @override
  State<_NewTenderSheet> createState() => _NewTenderSheetState();
}

class _NewTenderSheetState extends State<_NewTenderSheet> {
  final _from = TextEditingController();
  final _to = TextEditingController();
  final _trips = TextEditingController(text: '10');
  final _note = TextEditingController();
  String? _type;
  int _months = 3;
  int _closeDays = 7;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_from, _to, _trips, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final trips = int.tryParse(_trips.text.trim());
    if (_from.text.trim().length < 2 || _to.text.trim().length < 2 || _type == null || trips == null || trips < 1 || trips > 500) {
      setState(() => _error = tr(context, 'tdrFillAll'));
      return;
    }
    setState(() => _busy = true);
    try {
      await LaneRfqService.create(
        ownerName: widget.ownerName,
        fromCity: _from.text,
        toCity: _to.text,
        vehicleType: _type!,
        tripsPerMonth: trips,
        months: _months,
        closesAt: DateTime.now().add(Duration(days: _closeDays)),
        note: _note.text,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final types = VehicleTypeService.ids;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(DsSpace.gutter, 0, DsSpace.gutter, DsSpace.gutter + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(header: true, child: Text(tr(context, 'tdrNew'), style: DsType.title)),
          const SizedBox(height: DsSpace.s3),
          TextField(key: const ValueKey('tdrFrom'), controller: _from, decoration: InputDecoration(labelText: tr(context, 'tdrFrom')), inputFormatters: [LengthLimitingTextInputFormatter(60)]),
          TextField(key: const ValueKey('tdrTo'), controller: _to, decoration: InputDecoration(labelText: tr(context, 'tdrTo')), inputFormatters: [LengthLimitingTextInputFormatter(60)]),
          DropdownButtonFormField<String>(
            key: const ValueKey('tdrType'),
            initialValue: _type,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr(context, 'wzQ3')),
            items: [for (final t in types) DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _type = v),
          ),
          TextField(
            key: const ValueKey('tdrTrips'),
            controller: _trips,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
            decoration: InputDecoration(labelText: tr(context, 'tdrTripsPerMonth')),
          ),
          const SizedBox(height: DsSpace.s2),
          Text(trf(context, 'tdrMonths', {'n': _months})),
          Slider(key: const ValueKey('tdrMonthsSlider'), value: _months.toDouble(), min: 1, max: 12, divisions: 11, label: '$_months', onChanged: (v) => setState(() => _months = v.round())),
          Text(trf(context, 'tdrCloseIn', {'n': _closeDays})),
          Slider(key: const ValueKey('tdrCloseSlider'), value: _closeDays.toDouble(), min: 1, max: 30, divisions: 29, label: '$_closeDays', onChanged: (v) => setState(() => _closeDays = v.round())),
          TextField(key: const ValueKey('tdrNote'), controller: _note, maxLines: 2, decoration: InputDecoration(labelText: tr(context, 'tdrNote')), inputFormatters: [LengthLimitingTextInputFormatter(300)]),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: DsSpace.s2), child: Text(_error!, key: const ValueKey('tdrError'), style: DsType.bodySmall.copyWith(color: context.ds.error))),
          const SizedBox(height: DsSpace.s3),
          AppButton(key: const ValueKey('tdrPost'), label: tr(context, 'tdrPost'), loading: _busy, onPressed: _busy ? null : _save),
        ]),
      ),
    );
  }
}

/// The owner sees every bid, lowest rate first, and awards one or closes the tender.
class LaneTenderBidsScreen extends StatelessWidget {
  final LaneRfq rfq;
  final Stream<List<LaneBid>> Function(String id)? bids;
  final Future<void> Function(String id, LaneBid bid)? award;
  final Future<void> Function(String id)? close;
  const LaneTenderBidsScreen({super.key, required this.rfq, this.bids, this.award, this.close});

  Future<void> _confirm(BuildContext context, String text, Future<void> Function() act) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(content: Text(text), actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr(c, 'cancel'))),
        FilledButton(key: const ValueKey('tdrConfirm'), onPressed: () => Navigator.pop(c, true), child: Text(tr(c, 'tdrYes'))),
      ]),
    );
    if (ok != true || !context.mounted) return;
    try {
      await act();
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) showSnack(context, errorText(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final open = rfq.status == 'open';
    return Scaffold(
      appBar: AppTopBar(title: tr(context, 'tdrBidsTitle')),
      body: StreamBuilder<List<LaneBid>>(
        stream: (bids ?? LaneRfqService.watchBids)(rfq.id),
        builder: (context, snap) {
          final list = snap.data ?? const <LaneBid>[];
          return ListView(padding: const EdgeInsets.all(DsSpace.gutter), children: [
            _rfqCard(context, rfq),
            const SizedBox(height: DsSpace.s3),
            Text(tr(context, 'tdrRecordsOnly'), style: DsType.caption.copyWith(color: c.textMuted)),
            const SizedBox(height: DsSpace.s3),
            if (snap.hasError) ErrorState(compact: true, error: snap.error),
            if (!snap.hasData && !snap.hasError) const Center(child: CircularProgressIndicator()),
            if (snap.hasData && list.isEmpty) Text(tr(context, 'tdrNoBids'), key: const ValueKey('tdrNoBids'), style: DsType.body.copyWith(color: c.textMuted)),
            for (final b in list)
              Padding(
                padding: const EdgeInsets.only(bottom: DsSpace.s2),
                child: AppCard(
                  key: ValueKey('tdrBid_${b.bidderId}'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s1, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text(formatPaise(b.ratePaise), style: DsType.title.copyWith(color: c.textStrong)),
                      Text(tr(context, 'tdrPerTrip'), style: DsType.caption.copyWith(color: c.textMuted)),
                      if (rfq.awardedTo == b.bidderId) StatusBadge(label: tr(context, 'tdrStatus_awarded'), tone: StatusTone.success),
                    ]),
                    Text(b.bidderName, style: DsType.body.copyWith(color: c.text)),
                    if (b.note.isNotEmpty) Text(b.note, style: DsType.bodySmall.copyWith(color: c.textMuted)),
                    if (open)
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                          key: ValueKey('tdrAward_${b.bidderId}'),
                          onPressed: () => _confirm(context, trf(context, 'tdrAwardConfirm', {'name': b.bidderName, 'amount': formatPaise(b.ratePaise)}), () => (award ?? LaneRfqService.award)(rfq.id, b)),
                          child: Text(tr(context, 'tdrAward')),
                        ),
                      ),
                  ]),
                ),
              ),
            if (open)
              AppButton(
                key: const ValueKey('tdrClose'),
                label: tr(context, 'tdrCloseTender'),
                kind: AppButtonKind.secondary,
                onPressed: () => _confirm(context, tr(context, 'tdrCloseConfirm'), () => (close ?? LaneRfqService.close)(rfq.id)),
              ),
          ]);
        },
      ),
    );
  }
}

/// E30 (flag laneRfq): the transporter or driver side: open tenders and one rate per tender.
class OpenTendersScreen extends StatelessWidget {
  final String bidderName;
  final String? myUid;
  final Stream<List<LaneRfq>> Function()? open;
  final Future<void> Function(String id, int ratePaise, String note)? place;
  final DateTime Function() now;
  const OpenTendersScreen({super.key, required this.bidderName, this.myUid, this.open, this.place, this.now = DateTime.now});

  Future<void> _bid(BuildContext context, LaneRfq r) async {
    final got = await showDialog<(int?, String)>(context: context, builder: (_) => const _RateDialog());
    if (got == null || !context.mounted) return;
    final (rupees, text) = got;
    if (rupees == null || rupees < 1) {
      showSnack(context, tr(context, 'invalidNumber'));
      return;
    }
    try {
      await (place ?? (id, p, n) => LaneRfqService.placeBid(id, bidderName: bidderName, ratePaise: p, note: n))(r.id, rupees * 100, text);
      if (context.mounted) showSnack(context, tr(context, 'tdrRateSent'));
    } catch (e) {
      if (context.mounted) showSnack(context, errorText(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Scaffold(
      appBar: AppTopBar(title: tr(context, 'tdrOpenTitle')),
      body: StreamBuilder<List<LaneRfq>>(
        stream: (open ?? LaneRfqService.watchOpen)(),
        builder: (context, snap) {
          if (snap.hasError) return ErrorState(error: snap.error);
          if (!snap.hasData) return const Padding(padding: EdgeInsets.all(DsSpace.gutter), child: SkeletonList(count: 3));
          final at = now();
          final list = [for (final r in snap.data!) if (r.openAt(at) && r.ownerId != myUid) r];
          return ListView(padding: const EdgeInsets.all(DsSpace.gutter), children: [
            Text(tr(context, 'tdrOpenHelp'), style: DsType.bodySmall.copyWith(color: c.textMuted)),
            const SizedBox(height: DsSpace.s3),
            if (list.isEmpty) Text(tr(context, 'tdrNoOpen'), key: const ValueKey('tdrNoOpen'), style: DsType.body.copyWith(color: c.textMuted)),
            for (final r in list)
              _rfqCard(context, r,
                  trailing: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(key: ValueKey('tdrBidOn_${r.id}'), onPressed: () => _bid(context, r), child: Text(tr(context, 'tdrSendRate'))),
                  )),
          ]);
        },
      ),
    );
  }
}

/// The rate dialog owns its text fields, so they live exactly as long as the dialog (closing animation included).
class _RateDialog extends StatefulWidget {
  const _RateDialog();

  @override
  State<_RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends State<_RateDialog> {
  final _rate = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _rate.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr(context, 'tdrYourRate')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              key: const ValueKey('tdrRate'),
              controller: _rate,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)],
              decoration: InputDecoration(prefixText: '₹ ', helperText: tr(context, 'tdrPerTrip')),
            ),
            TextField(key: const ValueKey('tdrBidNote'), controller: _note, decoration: InputDecoration(labelText: tr(context, 'tdrNote')), inputFormatters: [LengthLimitingTextInputFormatter(200)]),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr(context, 'cancel'))),
          FilledButton(key: const ValueKey('tdrSendRate'), onPressed: () => Navigator.pop(context, (int.tryParse(_rate.text.trim()), _note.text)), child: Text(tr(context, 'tdrSendRate'))),
        ],
      );
}
