import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../models/load.dart';
import '../models/saved_place.dart';
import '../models/support_ticket.dart';
import '../navigation/app_routes.dart';
import '../services/booking_service.dart';
import '../services/load_service.dart';
import '../services/saved_place_service.dart';
import '../services/support_service.dart';
import '../settings/help_screen.dart';
import '../share/share_links.dart';
import '../support/support_screens.dart';
import '../widgets/common.dart';
import 'global_search.dart';
import 'recent_searches.dart';

/// App-wide search (both apps): the user's bookings, loads, tickets, saved
/// places, cities and help topics in sections, recent searches, and a pasted
/// load link opens that load. Typing is debounced.
class GlobalSearchScreen extends StatefulWidget {
  final bool isDriver;
  final String initialQuery;
  final Duration debounce;

  /// Test hooks; default to the live streams.
  final Stream<List<Booking>>? bookings;
  final Stream<List<Load>>? loads;
  final Stream<List<SupportTicket>>? tickets;
  final Stream<List<SavedPlace>>? places;

  const GlobalSearchScreen({
    super.key,
    required this.isDriver,
    this.initialQuery = '',
    this.debounce = const Duration(milliseconds: 250),
    this.bookings,
    this.loads,
    this.tickets,
    this.places,
  });

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  static const maxInput = 200;
  static final _cities = GlobalSearch.cities();

  late final _ctrl = TextEditingController(text: widget.initialQuery);
  final _subs = <StreamSubscription<dynamic>>[];
  Timer? _timer;
  late String _query = widget.initialQuery;
  final _expanded = <SearchKind>{};
  List<String> _recent = const [];

  List<Booking> _bookings = const [];
  List<Load> _loads = const [];
  List<SupportTicket> _tickets = const [];
  List<SavedPlace> _places = const [];

  @override
  void initState() {
    super.initState();
    void listen<D>(Stream<D> s, void Function(D) set) => _subs.add(s.listen((v) {
          if (mounted) setState(() => set(v));
        }, onError: (_) {}));
    listen(widget.bookings ?? (widget.isDriver ? BookingService.watchForDriver() : BookingService.watchForCustomer()), (v) => _bookings = v);
    listen(widget.loads ?? (widget.isDriver ? LoadService.watchOpenPage(50).map((p) => p.items) : LoadService.watchMine()), (v) => _loads = v);
    listen(widget.tickets ?? SupportService.watchMine(), (v) => _tickets = v);
    if (!widget.isDriver) listen(widget.places ?? SavedPlaceService.watchMine(), (v) => _places = v);
    RecentSearches.load().then((r) {
      if (mounted) setState(() => _recent = r);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _ctrl.dispose();
    super.dispose();
  }

  void _typed(String text) {
    setState(() {}); // the clear button follows the field at once
    _timer?.cancel();
    _timer = Timer(widget.debounce, () {
      if (mounted) setState(() => _query = text);
    });
  }

  void _setQuery(String text) {
    _timer?.cancel();
    _ctrl.text = text;
    _ctrl.selection = TextSelection.collapsed(offset: text.length);
    setState(() {
      _query = text;
      _expanded.clear();
    });
  }

  GlobalSearch _index() => GlobalSearch([
        for (final b in _bookings) GlobalSearch.fromBooking(b),
        for (final l in _loads) GlobalSearch.fromLoad(l),
        for (final t in _tickets) GlobalSearch.fromTicket(t),
        if (!widget.isDriver) ...[for (final p in _places) GlobalSearch.fromPlace(p), ..._cities],
        ...GlobalSearch.helpTopics([for (final i in HelpFaq.forRole(widget.isDriver ? HelpFaq.driver : null)) (i, tr(context, 'faqQ$i'), tr(context, 'faqA$i'))]),
      ]);

  Future<void> _remember() async {
    final r = await RecentSearches.add(_query);
    if (mounted) setState(() => _recent = r);
  }

  void _open(SearchEntry e) {
    _remember();
    final nav = Navigator.of(context);
    switch (e.kind) {
      case SearchKind.booking:
        AppRoutes.openBooking?.call(context, e.id, isDriver: widget.isDriver);
      case SearchKind.load:
        AppRoutes.openLoad?.call(context, e.id, isDriver: widget.isDriver);
      case SearchKind.ticket:
        nav.push(MaterialPageRoute(builder: (_) => TicketDetailScreen(ticketId: e.id)));
      case SearchKind.place:
      case SearchKind.city:
        AppRoutes.openPostLoad?.call(context, pickup: e.title);
      case SearchKind.help:
        nav.push(MaterialPageRoute(builder: (_) => HelpScreen(openFaq: int.tryParse(e.id))));
    }
  }

  String _sectionTitle(SearchKind k) => tr(context, switch (k) {
        SearchKind.booking => 'searchBookingsHeader',
        SearchKind.load => widget.isDriver ? 'gsOpenLoads' : 'searchLoadsHeader',
        SearchKind.ticket => 'gsTickets',
        SearchKind.place => 'gsPlaces',
        SearchKind.city => 'gsCities',
        SearchKind.help => 'gsHelp',
      });

  IconData _icon(SearchKind k) => switch (k) {
        SearchKind.booking => Icons.local_shipping_rounded,
        SearchKind.load => Icons.inventory_2_outlined,
        SearchKind.ticket => Icons.support_agent_rounded,
        SearchKind.place => Icons.place_outlined,
        SearchKind.city => Icons.location_city_rounded,
        SearchKind.help => Icons.help_outline_rounded,
      };

  Widget _hit(SearchEntry e) => AppCard(
        key: ValueKey('hit_${e.kind.name}_${e.id}'),
        onTap: () => _open(e),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: Icon(_icon(e.kind), color: AppColors.primary),
          title: Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: e.subtitle.isEmpty ? null : Text(e.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      );

  Widget _recentBlock() {
    if (_recent.isEmpty) {
      return EmptyState(icon: Icons.search_rounded, title: tr(context, 'gsHint'));
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(child: Text(tr(context, 'gsRecent'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        TextButton(
          key: const ValueKey('clearRecent'),
          onPressed: () async {
            await RecentSearches.clear();
            if (mounted) setState(() => _recent = const []);
          },
          child: Text(tr(context, 'clear')),
        ),
      ]),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (var i = 0; i < _recent.length; i++)
          ActionChip(
            key: ValueKey('recent_$i'),
            avatar: const Icon(Icons.history_rounded, size: 18),
            label: Text(_recent[i]),
            onPressed: () => _setQuery(_recent[i]),
          ),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim();
    final sharedId = ShareLinks.parseLoadId(q);
    final search = _index();
    final sections = sharedId != null ? const <SearchSection>[] : search.search(q);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          key: const ValueKey('globalSearchField'),
          controller: _ctrl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(hintText: tr(context, 'search'), border: InputBorder.none, filled: false),
          inputFormatters: [LengthLimitingTextInputFormatter(maxInput)],
          onChanged: _typed,
          onSubmitted: (v) {
            _setQuery(v);
            _remember();
          },
        ),
        actions: [
          if (_ctrl.text.isNotEmpty)
            IconButton(key: const ValueKey('clearSearch'), tooltip: tr(context, 'clear'), onPressed: () => _setQuery(''), icon: const Icon(Icons.close_rounded)),
        ],
      ),
      body: q.isEmpty
          ? _recentBlock()
          : sharedId != null
              ? ListView(padding: const EdgeInsets.all(16), children: [
                  AppCard(
                    key: const ValueKey('openShared'),
                    onTap: () {
                      _remember();
                      AppRoutes.openLoad?.call(context, sharedId, isDriver: widget.isDriver);
                    },
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.link_rounded, color: AppColors.primary),
                      title: Text(tr(context, 'gsOpenShared')),
                      subtitle: Text(sharedId, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.chevron_right_rounded),
                    ),
                  ),
                ])
              : sections.isEmpty
                  ? EmptyState(icon: Icons.search_off_rounded, title: trf(context, 'searchNoResults', {'q': q}))
                  : ListView(padding: const EdgeInsets.all(16), children: [
                      for (final s in sections) ...[
                        Text(_sectionTitle(s.kind), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 8),
                        for (final h in _expanded.contains(s.kind) ? search.all(q, s.kind) : s.hits) Padding(padding: const EdgeInsets.only(bottom: 8), child: _hit(h.entry)),
                        if (s.total > s.hits.length && !_expanded.contains(s.kind))
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              key: ValueKey('showAll_${s.kind.name}'),
                              onPressed: () => setState(() => _expanded.add(s.kind)),
                              child: Text(trf(context, 'gsShowAll', {'n': s.total})),
                            ),
                          ),
                        const SizedBox(height: 8),
                      ],
                    ]),
    );
  }
}
