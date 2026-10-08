import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/load.dart';
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
          final ranked = LoadFit.rank(all, _profile);
          final shown = _onlyMine && hasRoutes ? [for (final f in ranked) if (f.route) f] : ranked;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 90), children: [
            if (hasRoutes)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilterChip(
                  key: const ValueKey('trpOnlyMine'),
                  label: Text(tr(context, 'trpOnlyMyRoutes')),
                  selected: _onlyMine,
                  onSelected: (v) => setState(() => _onlyMine = v),
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
