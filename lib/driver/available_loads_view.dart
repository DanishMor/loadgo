import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/models/saved_search.dart';
import '../core/widgets/saved_search_menu.dart';
import '../core/widgets/load_filter_sheet.dart';

import '../core/matching/nearest.dart';
import '../core/models/load.dart';
import '../core/services/user_service.dart';
import '../core/models/load_filter.dart';
import '../core/widgets/common.dart';
import '../core/l10n/l10n.dart';
import '../core/widgets/paged_live_stream.dart';
import 'accept_load.dart';
import '../core/widgets/load_card.dart';
import 'favourite_routes_screen.dart';
import 'make_offer.dart';
import '../core/voice/voice_input.dart';
import '../core/voice/voice_parser.dart';
import 'recommended_loads.dart';
import '../core/services/match_service.dart';
import '../core/matching/load_ranker.dart' show PlannedRoute;

/// Accept button wired to the full accept flow, with its own busy state.
class AcceptLoadButton extends StatefulWidget {
  final Load load;
  final ValueChanged<String>? onAccepted;

  const AcceptLoadButton({super.key, required this.load, this.onAccepted});

  @override
  State<AcceptLoadButton> createState() => _AcceptLoadButtonState();
}

class _AcceptLoadButtonState extends State<AcceptLoadButton> {
  bool _busy = false;

  Future<void> _accept() async {
    final bookingId = await acceptLoadFlow(
      context,
      widget.load,
      onRetry: _accept,
      onBusy: (busy) {
        if (mounted) setState(() => _busy = busy);
      },
    );
    if (bookingId != null) widget.onAccepted?.call(bookingId);
  }

  Future<void> _saveRoute() async {
    try {
      final ok = await MatchService.addFavourite(widget.load.pickup, widget.load.drop);
      if (mounted) showSnack(context, tr(context, ok ? 'routeSaved' : 'routesFull'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _acceptButton()),
        const SizedBox(width: 8),
        MakeOfferButton(load: widget.load),
        IconButton(
          key: ValueKey('saveRoute_${widget.load.id}'),
          tooltip: tr(context, 'saveRoute'),
          icon: const Icon(Icons.star_border_rounded),
          onPressed: _saveRoute,
        ),
      ],
    );
  }

  Widget _acceptButton() {
    return SizedBox(
      height: 46,
      child: FilledButton.icon(
        onPressed: _busy ? null : _accept,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.check_circle_outline_rounded),
        label: Text(tr(context, 'accept'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// Driver "Loads" tab: live list of open loads with pickup search and
/// vehicle type / minimum budget filters.
class AvailableLoadsView extends StatefulWidget {
  final PagedStreamFactory<Load> loads;
  final ValueChanged<String>? onAccepted;

  /// Where the driver is. When null it is read from the profile's last
  /// saved location; without either the list keeps its newest-first order.
  final LatLng? origin;

  /// Live loads around the driver (geohash range queries). They are merged
  /// into the page and the whole list is sorted by distance, so close loads
  /// show first even if they are not among the newest.
  final Stream<List<Load>> Function(LatLng origin)? nearby;

  const AvailableLoadsView({super.key, required this.loads, this.onAccepted, this.origin, this.nearby});

  @override
  State<AvailableLoadsView> createState() => _AvailableLoadsViewState();
}

class _AvailableLoadsViewState extends State<AvailableLoadsView> {
  final _searchCtrl = TextEditingController();
  LoadFilter _filter = LoadFilter.none;
  late LatLng? _origin = widget.origin;
  StreamSubscription<List<Load>>? _nearSub;
  List<Load> _nearby = const [];

  @override
  void initState() {
    super.initState();
    if (_origin == null) {
      _loadOrigin();
    } else {
      _watchNearby();
    }
  }

  void _watchNearby() {
    final o = _origin;
    if (o == null || widget.nearby == null) return;
    _nearSub?.cancel();
    _nearSub = widget.nearby!(o).listen((l) {
      if (mounted) setState(() => _nearby = l);
    }, onError: (_) {});
  }

  /// The loaded page plus the nearby loads, without duplicates.
  List<Load> _withNearby(List<Load> page) {
    if (_nearby.isEmpty) return page;
    final ids = {for (final l in page) l.id};
    return [...page, for (final l in _nearby) if (ids.add(l.id)) l];
  }

  Future<void> _loadOrigin() async {
    try {
      final here = UserService.lastLocationOf(await UserService.getUser());
      if (here != null && mounted) {
        setState(() => _origin = here);
        _watchNearby();
      }
    } catch (_) {
      // No profile yet: keep the default order.
    }
  }

  /// Nearest pickup first once the driver's position is known.
  List<NearLoad> _ordered(List<Load> loads) {
    final o = _origin;
    return o == null ? [for (final l in loads) NearLoad(l, null)] : sortNearestFirst(loads, o);
  }

  Widget _distanceChip(int? km) {
    if (km == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        const Icon(Icons.near_me_rounded, size: 15, color: AppColors.primary),
        const SizedBox(width: 4),
        Text(trf(context, 'kmAway', {'n': km}),
            key: ValueKey('kmAway_$km'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
      ]),
    );
  }

  /// A spoken "Delhi se Jaipur" or a city name fills the pickup search with
  /// the pickup city (or the spoken words when no city is recognised).
  void _heardPlace(String text) {
    final route = VoiceParser.parseRoute(text);
    final place = route.from ?? text.trim();
    _searchCtrl.text = place;
    setState(() => _filter = _filter.copyWith(pickupQuery: place));
  }

  @override
  void dispose() {
    _nearSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _clearAll() {
    _searchCtrl.clear();
    setState(() => _filter = LoadFilter.none);
  }

  Future<void> _planRoute() async {
    final user = await UserService.getUser();
    if (!mounted) return;
    final current = PlannedRoute.fromUser(user);
    final from = TextEditingController(text: current?.from ?? '');
    final to = TextEditingController(text: current?.to ?? '');
    final result = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(c, 'plannedRoute')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(key: const ValueKey('routeFrom'), controller: from, decoration: InputDecoration(labelText: tr(c, 'routeFrom')), inputFormatters: [LengthLimitingTextInputFormatter(100)]),
          TextField(key: const ValueKey('routeTo'), controller: to, decoration: InputDecoration(labelText: tr(c, 'routeTo')), inputFormatters: [LengthLimitingTextInputFormatter(100)]),
        ]),
        actions: [
          if (current != null) TextButton(key: const ValueKey('routeClear'), onPressed: () => Navigator.pop(c, false), child: Text(tr(c, 'remove'))),
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr(c, 'cancel'))),
          FilledButton(key: const ValueKey('routeSave'), onPressed: () => Navigator.pop(c, true), child: Text(tr(c, 'save'))),
        ],
      ),
    );
    final f = from.text, t = to.text;
    if (result == null || !mounted) return;
    try {
      await MatchService.setPlannedRoute(from: result ? f : null, to: result ? t : null);
      if (mounted) showSnack(context, tr(context, 'settingsSaved'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'invalidRoute'));
    }
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<LoadFilter>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      builder: (_) => LoadFilterSheet(initial: _filter),
    );
    if (result != null && mounted) setState(() => _filter = result.copyWith(pickupQuery: _searchCtrl.text));
  }

  Widget _activeChips() {
    InputChip chip(String label, LoadFilter Function() cleared) =>
        InputChip(label: Text(label), onDeleted: () => setState(() => _filter = cleared()));
    final f = _filter;
    final chips = <Widget>[
      if (f.dropQuery.trim().isNotEmpty) chip('→ ${f.dropQuery.trim()}', () => f.copyWith(dropQuery: '')),
      if (f.vehicleType != null) chip(f.vehicleType!, () => f.copyWith(vehicleType: () => null)),
      if (f.minBudget != null) chip('≥ ${formatRupees(f.minBudget!)}', () => f.copyWith(minBudget: () => null)),
      if (f.maxBudget != null) chip('≤ ${formatRupees(f.maxBudget!)}', () => f.copyWith(maxBudget: () => null)),
      if (f.minWeight != null) chip('≥ ${formatNum(f.minWeight!)} T', () => f.copyWith(minWeight: () => null)),
      if (f.maxWeight != null) chip('≤ ${formatNum(f.maxWeight!)} T', () => f.copyWith(maxWeight: () => null)),
      if (f.fromDate != null) chip('${formatDate(f.fromDate!)} →', () => f.copyWith(fromDate: () => null)),
      if (f.toDate != null) chip('→ ${formatDate(f.toDate!)}', () => f.copyWith(toDate: () => null)),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Wrap(spacing: 8, runSpacing: 4, children: chips),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _filter.sheetFilterCount;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Row(children: [
              Expanded(
                child: Text(tr(context, 'availableLoads'),
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.title)),
              ),
              IconButton(
                key: const ValueKey('plannedRoute'),
                tooltip: tr(context, 'plannedRoute'),
                icon: const Icon(Icons.alt_route_rounded, color: AppColors.primary),
                onPressed: _planRoute,
              ),
              IconButton(
                key: const ValueKey('openFavourites'),
                tooltip: tr(context, 'favouriteRoutes'),
                icon: const Icon(Icons.star_rounded, color: AppColors.warning),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FavouriteRoutesScreen())),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    textInputAction: TextInputAction.search,
                    onChanged: (v) => setState(() => _filter = _filter.copyWith(pickupQuery: v)),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: VoiceMicButton(onText: _heardPlace),
                      hintText: tr(context, 'searchPickup'),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ), inputFormatters: [LengthLimitingTextInputFormatter(100)]),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: tr(context, 'filters'),
                  onPressed: _openFilters,
                  icon: Badge(
                    isLabelVisible: count > 0,
                    label: Text('$count'),
                    child: const Icon(Icons.tune_rounded),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SavedSearchMenu(
              kind: SearchKind.loads,
              canSave: !_filter.isEmpty,
              currentFilter: () => _filter.toMap(),
              onApply: (m) {
                final f = LoadFilter.fromMap(m);
                _searchCtrl.text = f.pickupQuery;
                setState(() => _filter = f);
              },
            ),
          ),
          _activeChips(),
          const SizedBox(height: 8),
          Expanded(
            child: PagedLiveStream<Load>(
              stream: widget.loads,
              builder: (context, page, loadMore) {
                final all = _withNearby(page);
                final list = _ordered(_filter.apply(all));
                if (all.isEmpty) {
                  return EmptyState(icon: Icons.inventory_2_rounded, title: tr(context, 'noAvailableLoads'));
                }
                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.filter_alt_off_rounded,
                    title: tr(context, 'noLoadsMatch'),
                    action: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton(onPressed: _clearAll, child: Text(tr(context, 'clearFilters'))),
                        ?loadMore,
                      ],
                    ),
                  );
                }
                final showRecommended = _filter.isEmpty;
                final offset = showRecommended ? 1 : 0;
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                  itemCount: list.length + offset + (loadMore == null ? 0 : 1),
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    if (showRecommended && i == 0) {
                      return RecommendedLoads(
                        loads: all,
                        cardBuilder: (m) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MatchReasonChips(reasons: m.reasons),
                            LoadCard(
                              key: ValueKey('rec_${m.load.id}'),
                              load: m.load,
                              networkShare: true,
                              action: AcceptLoadButton(load: m.load, onAccepted: widget.onAccepted),
                            ),
                          ],
                        ),
                      );
                    }
                    final k = i - offset;
                    if (k == list.length) return loadMore!;
                    final item = list[k];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _distanceChip(item.km),
                        LoadCard(
                          key: ValueKey(item.load.id),
                          load: item.load,
                          networkShare: true,
                          action: AcceptLoadButton(load: item.load, onAccepted: widget.onAccepted),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
