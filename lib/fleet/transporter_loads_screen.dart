import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/load.dart';
import '../core/models/load_filter.dart';
import '../core/models/saved_search.dart';
import '../core/transporter/bulk_bid.dart';
import '../core/widgets/load_filter_sheet.dart';
import '../core/widgets/saved_search_menu.dart';
import '../core/widgets/trip_cost_widgets.dart';
import '../core/services/pricing_service.dart';
import '../core/models/offer.dart';
import '../core/models/risk.dart';
import '../core/models/vehicle.dart';
import '../core/navigation/app_routes.dart';
import '../core/services/load_service.dart';
import '../core/services/offer_service.dart';
import '../core/services/rate_limit_service.dart';
import '../core/services/vehicle_service.dart';
import '../core/transporter/transporter_logic.dart';
import '../core/services/transporter_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';
import '../core/widgets/logistics_labels.dart';

/// Open loads for a transporter: look, bid for the company (the vehicle and
/// driver are assigned after the customer picks the bid), and post a load
/// (tagged "Posted by transporter").
class TransporterLoadsScreen extends StatefulWidget {
  /// Injectable for tests.
  final Stream<List<Load>>? loads;
  final Future<List<Vehicle>> Function()? vehicles;
  final Future<TransporterProfile> Function()? profile;

  const TransporterLoadsScreen({super.key, this.loads, this.vehicles, this.profile});

  @override
  State<TransporterLoadsScreen> createState() => _TransporterLoadsScreenState();
}

class _TransporterLoadsScreenState extends State<TransporterLoadsScreen> {
  late final Stream<List<Load>> _loads = (widget.loads ?? LoadService.watchOpen()).asBroadcastStream();
  String? _busyId;
  bool _onlyMine = false;
  LoadFilter _filter = LoadFilter.none;
  bool _selecting = false;
  final Set<String> _selected = {};
  bool _bulkBusy = false;
  TransporterProfile _profile = const TransporterProfile();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final p = await (widget.profile ?? TransporterService.loadProfile)();
      if (mounted) setState(() => _profile = p);
    } catch (_) {
      // Offline: the list simply stays in its normal order.
    }
  }

  /// Own active vehicles plus the ones members attached.
  Future<List<Vehicle>> _myVehicles() async {
    if (widget.vehicles != null) return widget.vehicles!();
    final own = await VehicleService.fetchMyActive();
    final attached = await TransporterService.watchAttached().first;
    final byId = {for (final v in [...own, ...attached]) v.id: v};
    return byId.values.where((v) => v.isActive).toList();
  }

  Future<void> _bid(Load load) async {
    setState(() => _busyId = load.id);
    try {
      final all = (await _myVehicles()).where((v) => v.canTakeBooking && v.capacity >= load.weight).toList();
      if (!mounted) return;
      if (all.isEmpty) {
        showSnack(context, tr(context, 'trpNoVehicle'));
        return;
      }
      final vehicle = await showDialog<Vehicle>(
        context: context,
        builder: (c) => SimpleDialog(
          title: Text(tr(c, 'trpBidVehicle')),
          children: [
            for (final v in all)
              SimpleDialogOption(
                key: ValueKey('bidVehicle_${v.id}'),
                onPressed: () => Navigator.of(c).pop(v),
                child: Text('${v.number} • ${vehicleTypeLabel(c, v.type)}${v.attachedTo != null ? ' • ${tr(c, 'trpAttachedChip')}' : ''}'),
              ),
          ],
        ),
      );
      if (vehicle == null || !mounted) return;
      final price = await askPricePaise(context,
          title: tr(context, 'trpBid'), label: tr(context, 'yourPrice'), initialPaise: load.estimate?.total, note: tr(context, 'trpBidNote'));
      if (price == null || !mounted) return;
      await OfferService.send(load: load, vehicle: vehicle, pricePaise: price, asCompany: true);
      if (mounted) showSnack(context, tr(context, 'trpBidSent'));
    } on AccountRestrictedException {
      if (mounted) showSnack(context, tr(context, 'accountRestricted'));
    } on RateLimitException catch (e) {
      if (mounted) showSnack(context, trf(context, 'rateLimited', {'m': e.minutesLeft}));
    } on OfferOutOfRangeException catch (e) {
      if (mounted) showSnack(context, trf(context, 'offerOutOfRange', {'min': e.minPaise ~/ 100, 'max': e.maxPaise ~/ 100}));
    } on OfferExistsException {
      if (mounted) showSnack(context, tr(context, 'offerExists'));
    } on OfferStateException {
      if (mounted) showSnack(context, tr(context, 'loadUnavailable'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _openFilters() async {
    final r = await showLoadFilterSheet(context, _filter);
    if (r != null && mounted) setState(() => _filter = r);
  }

  int? _runningCost(Load l, Vehicle v) {
    final km = l.estimate?.distanceKm ?? PricingService.estimateRouteKm(l.route);
    if (km == null || km <= 0) return null;
    return tripCostFor(farePaise: l.estimate?.total ?? 0, km: km, vehicleType: v.type, from: l.pickup, to: l.drop).runningCost;
  }

  /// Bid on the selected loads under the markup and margin rule chosen in the dialog.
  Future<void> _bulkBid(List<Load> loads) async {
    final vehicles = await _myVehicles();
    if (!mounted) return;
    var markup = 5, margin = 10;
    final go = await showDialog<List<BulkBidItem>>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        final items = BulkBid.plan(loads, vehicles, markupPercent: markup, minMarginPercent: margin, runningCost: _runningCost, now: DateTime.now());
        final will = [for (final i in items) if (i.willBid) i];
        final skipped = [for (final i in items) if (!i.willBid) i];
        return AlertDialog(
          title: Text(tr(c, 'bbTitle')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(trf(c, 'bbMarkup', {'p': markup}), style: const TextStyle(fontWeight: FontWeight.w700)),
              Wrap(spacing: 6, children: [
                for (final m in BulkBid.markupChoices) ChoiceChip(key: ValueKey('bbMarkup_$m'), label: Text('$m%'), selected: markup == m, onSelected: (_) => set(() => markup = m)),
              ]),
              const SizedBox(height: 10),
              Text(trf(c, 'bbMargin', {'p': margin}), style: const TextStyle(fontWeight: FontWeight.w700)),
              Wrap(spacing: 6, children: [
                for (final m in BulkBid.marginChoices) ChoiceChip(key: ValueKey('bbMargin_$m'), label: Text('$m%'), selected: margin == m, onSelected: (_) => set(() => margin = m)),
              ]),
              const SizedBox(height: 12),
              Text(trf(c, 'bbWillBid', {'n': will.length}), key: const ValueKey('bbWill'), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.success)),
              for (final i in will) Text('${i.load.pickup} → ${i.load.drop}: ${formatPaise(i.pricePaise!)}', style: const TextStyle(fontSize: 13)),
              if (skipped.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(trf(c, 'bbSkipped', {'n': skipped.length}), key: const ValueKey('bbSkipped'), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.warning)),
                for (final i in skipped) Text('${i.load.pickup} → ${i.load.drop}: ${tr(c, 'bbWhy_${i.skip!.name}')}', style: TextStyle(fontSize: 13, color: AppColors.muted)),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text(tr(c, 'cancel'))),
            FilledButton(key: const ValueKey('bbSend'), onPressed: will.isEmpty ? null : () => Navigator.pop(c, will), child: Text(trf(c, 'bbSend', {'n': will.length}))),
          ],
        );
      }),
    );
    if (go == null || !mounted) return;
    setState(() => _bulkBusy = true);
    var sent = 0, dup = 0, fail = 0;
    int? waitMinutes;
    for (var k = 0; k < go.length; k++) {
      final i = go[k];
      try {
        await OfferService.send(load: i.load, vehicle: i.vehicle!, pricePaise: i.pricePaise!, asCompany: true);
        sent++;
      } on OfferExistsException {
        dup++;
      } on RateLimitException catch (e) {
        waitMinutes = e.minutesLeft;
        fail += go.length - k;
        break;
      } on AccountRestrictedException {
        fail += go.length - k;
        break;
      } catch (_) {
        fail++;
      }
    }
    if (!mounted) return;
    setState(() {
      _bulkBusy = false;
      _selecting = false;
      _selected.clear();
    });
    showSnack(context, waitMinutes != null ? trf(context, 'bbStoppedRate', {'m': waitMinutes}) : trf(context, 'bbDone', {'sent': sent, 'dup': dup, 'fail': fail}));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: AppRoutes.openPostLoad == null
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('trpPostLoadButton'),
              onPressed: () => AppRoutes.openPostLoad!(context),
              icon: const Icon(Icons.add_rounded),
              label: Text(tr(context, 'trpPostLoad')),
            ),
      body: LiveStream<List<Load>>(
        stream: () => _loads,
        builder: (context, all) {
          if (all.isEmpty) return EmptyState(icon: Icons.inventory_2_outlined, title: tr(context, 'trpNoLoads'));
          final hasRoutes = _profile.routes.isNotEmpty;
          final ranked = LoadFit.rank(_filter.apply(all), _profile);
          final shown = _onlyMine && hasRoutes ? [for (final f in ranked) if (f.route) f] : ranked;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 90), children: [
            Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (hasRoutes)
                FilterChip(
                  key: const ValueKey('trpOnlyMine'),
                  label: Text(tr(context, 'trpOnlyMyRoutes')),
                  selected: _onlyMine,
                  onSelected: (v) => setState(() => _onlyMine = v),
                ),
              ActionChip(
                key: const ValueKey('trpFilters'),
                avatar: Badge(isLabelVisible: !_filter.isEmpty, label: Text('${_filter.sheetFilterCount + (_filter.pickupQuery.trim().isEmpty ? 0 : 1)}'), child: const Icon(Icons.tune_rounded, size: 18)),
                label: Text(tr(context, 'filters')),
                onPressed: _openFilters,
              ),
              FilterChip(
                key: const ValueKey('bbSelect'),
                label: Text(tr(context, 'bbSelect')),
                selected: _selecting,
                onSelected: (v) => setState(() {
                  _selecting = v;
                  if (!v) _selected.clear();
                }),
              ),
            ]),
            SavedSearchMenu(
              kind: SearchKind.loads,
              canSave: !_filter.isEmpty,
              currentFilter: () => _filter.toMap(),
              onApply: (m) => setState(() => _filter = LoadFilter.fromMap(m)),
            ),
            if (_selecting && _selected.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: FilledButton.icon(
                  key: const ValueKey('bbBidOn'),
                  onPressed: _bulkBusy ? null : () => _bulkBid([for (final f in shown) if (_selected.contains(f.load.id)) f.load]),
                  icon: const Icon(Icons.gavel_rounded),
                  label: Text(trf(context, 'bbBidOn', {'n': _selected.length})),
                ),
              ),
            if (shown.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(tr(context, 'trpNoLoads'), textAlign: TextAlign.center)),
            for (final fit in shown)
              Builder(builder: (context) {
                final l = fit.load;
                return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  key: ValueKey('trpLoad_${l.id}'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (_selecting)
                      CheckboxListTile(
                        key: ValueKey('bbPick_${l.id}'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _selected.contains(l.id),
                        onChanged: (v) => setState(() => v == true ? (_selected.length < BulkBid.maxLoads ? _selected.add(l.id) : null) : _selected.remove(l.id)),
                        title: Text('${l.pickup} → ${l.drop}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      )
                    else
                      Text('${l.pickup} → ${l.drop}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text('${l.cargoType} • ${formatNum(l.weight)} T • ${vehicleTypeLabel(context, l.vehicleType)}', style: TextStyle(color: AppColors.muted)),
                    if (l.estimate != null) Text(formatPaise(l.estimate!.total), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
                    if (l.postedByTransporter || fit.route || fit.vehicleType)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(spacing: 6, runSpacing: 4, children: [
                          if (l.postedByTransporter) StatusChip(label: tr(context, 'trpPostedBy'), color: AppColors.primary),
                          if (fit.route) StatusChip(key: ValueKey('fitRoute_${l.id}'), label: tr(context, 'trpFitRoute'), color: AppColors.success),
                          if (fit.vehicleType) StatusChip(label: tr(context, 'trpFitType'), color: AppColors.success),
                        ]),
                      ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 44,
                      child: OutlinedButton.icon(
                        key: ValueKey('trpBidButton_${l.id}'),
                        onPressed: _busyId == null ? () => _bid(l) : null,
                        icon: const Icon(Icons.gavel_rounded),
                        label: Text(tr(context, 'trpBid')),
                      ),
                    ),
                  ]),
                ),
              );
              }),
          ]);
        },
      ),
    );
  }
}
