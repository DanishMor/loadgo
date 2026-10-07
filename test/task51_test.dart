import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/l10n/global_search_strings.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/saved_place.dart';
import 'package:transport_app/core/models/support_ticket.dart';
import 'package:transport_app/core/navigation/app_routes.dart';
import 'package:transport_app/core/search/global_search.dart';
import 'package:transport_app/core/search/global_search_screen.dart';
import 'package:transport_app/core/search/recent_searches.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/settings/help_screen.dart';
import 'package:transport_app/core/share/share_links.dart';
import 'package:transport_app/core/support/support_screens.dart';
import 'package:transport_app/core/widgets/load_by_id_screen.dart';
import 'package:transport_app/route_hooks.dart';

import 'test_utils.dart';

final db = FakeFirebaseFirestore();

Future<Booking> booking(String id, {String pickup = 'Pune', String drop = 'Mumbai', String driver = 'Ravi Kumar', String vehicle = 'MH12AB1234'}) async {
  await db.collection('bookings').doc(id).set({
    'driverId': 'd1', 'customerId': 'c1', 'status': 'accepted', 'pickup': pickup, 'drop': drop, 'cargoType': 'FMCG', 'weight': 5,
    'vehicleType': '20ft', 'vehicleNumber': vehicle, 'driverName': driver, 'timeline': {}, 'createdAt': Timestamp.now(),
  });
  return Booking.fromDoc(await db.collection('bookings').doc(id).get());
}

Future<Load> load(String id, {String pickup = 'Delhi', String drop = 'Jaipur', String cargo = 'Steel', String status = 'open'}) async {
  await db.collection('loads').doc(id).set({
    'shipperId': 'c1', 'pickup': pickup, 'drop': drop, 'cargoType': cargo, 'weight': 5, 'vehicleType': '20ft', 'status': status, 'notes': '', 'pickupDate': Timestamp.now(),
  });
  return Load.fromDoc(await db.collection('loads').doc(id).get());
}

Future<SupportTicket> ticket(String id, String subject) async {
  await db.collection('tickets').doc(id).set({
    'userId': 'c1', 'category': 'payment', 'priority': 'normal', 'status': 'open', 'subject': subject, 'description': 'UPI link did not open', 'createdAt': Timestamp.now(), 'updatedAt': Timestamp.now(),
  });
  return SupportTicket.fromDoc(await db.collection('tickets').doc(id).get());
}

Future<SavedPlace> place(String id, String name, String address) async {
  await db.collection('places').doc(id).set({'label': 'home', 'name': name, 'address': address});
  return SavedPlace.fromDoc(await db.collection('places').doc(id).get());
}

Widget app(Widget child) => MaterialApp(home: LanguageScope(notifier: languageNotifier, child: child));

void main() {
  setUp(() {
    languageNotifier.value = AppLanguage.english;
    SharedPreferences.setMockInitialValues({});
    Backend.useFakes(db: db, uid: () => 'c1');
    AppRoutes.openBooking = null;
    AppRoutes.openLoad = null;
    AppRoutes.openPostLoad = null;
  });

  group('GlobalSearch ranking', () {
    SearchEntry e(String title, {String sub = '', List<String> kw = const [], SearchKind kind = SearchKind.load, String id = 'x'}) =>
        SearchEntry(kind: kind, id: id, title: title, subtitle: sub, keywords: kw);

    test('exact beats prefix beats word-prefix beats contains', () {
      expect(GlobalSearch.score('delhi', e('Delhi')), GlobalSearch.exact + GlobalSearch.titleBonus);
      expect(GlobalSearch.score('del', e('Delhi')), GlobalSearch.prefix + GlobalSearch.titleBonus);
      expect(GlobalSearch.score('mum', e('Delhi → Mumbai')), GlobalSearch.wordPrefix);
      expect(GlobalSearch.score('umba', e('Delhi → Mumbai')), GlobalSearch.contains + GlobalSearch.titleBonus);
      expect(GlobalSearch.score('umba', e('A → B', sub: 'Mumbai depot')), GlobalSearch.contains);
      expect(GlobalSearch.score('xyz', e('Delhi')), 0);
      final order = [for (final q in ['delhi', 'del', 'elh']) GlobalSearch.score(q, e('Delhi'))];
      expect(order[0], greaterThan(order[1]));
      expect(order[1], greaterThan(order[2]));
    });

    test('several words in any order, each starting some word', () {
      expect(GlobalSearch.score('del mum', e('Delhi → Mumbai')), GlobalSearch.wordPrefix);
      expect(GlobalSearch.score('mum del', e('Delhi → Mumbai')), GlobalSearch.wordPrefix);
      expect(GlobalSearch.score('del xyz', e('Delhi → Mumbai')), 0);
    });

    test('keywords and subtitle count, a title match adds a bonus, punctuation and case are ignored', () {
      expect(GlobalSearch.score('steel', e('A → B', sub: 'Steel · 20ft')), greaterThan(0));
      expect(GlobalSearch.score('bombay', e('Mumbai', kw: ['Bombay'])), GlobalSearch.exact);
      expect(GlobalSearch.score('MUMBAI!!', e('mumbai')), GlobalSearch.exact + GlobalSearch.titleBonus);
      expect(GlobalSearch.score('   ', e('x')), 0);
      expect(GlobalSearch.score('', e('x')), 0);
    });

    test('Hindi text is searchable', () {
      expect(GlobalSearch.score('नमस्ते', e('नमस्ते दोस्त')), GlobalSearch.prefix + GlobalSearch.titleBonus);
    });

    test('sections come in kind order, best first, capped, with a total', () {
      final idx = GlobalSearch([
        e('Delhi depot', kind: SearchKind.place, id: 'p1'),
        e('Delhi', kind: SearchKind.city, id: 'Delhi'),
        for (var i = 0; i < 7; i++) e('Delhi → Town$i', kind: SearchKind.load, id: 'l$i'),
        e('Delhi → Agra', kind: SearchKind.booking, id: 'b1'),
      ]);
      final s = idx.search('delhi');
      expect(s.map((x) => x.kind), [SearchKind.booking, SearchKind.load, SearchKind.place, SearchKind.city]);
      final loads = s.firstWhere((x) => x.kind == SearchKind.load);
      expect(loads.hits.length, 5);
      expect(loads.total, 7);
      expect(idx.all('delhi', SearchKind.load).length, 7);
      expect(idx.search('delhi', perKind: 2).first.hits.length, 1);
      expect(idx.search('   '), isEmpty);
      expect(idx.search('zzz'), isEmpty);
    });

    test('equal scores are ordered by title', () {
      final idx = GlobalSearch([e('Delhi B', id: '2'), e('Delhi A', id: '1')]);
      expect(idx.search('delhi').single.hits.map((h) => h.entry.id), ['1', '2']);
    });
  });

  group('entry makers', () {
    test('booking, load, ticket, place, cities and help topics', () async {
      final b = GlobalSearch.fromBooking(await booking('b1'));
      expect(b.title, 'Pune → Mumbai');
      expect(b.subtitle, 'FMCG · Ravi Kumar');
      expect(GlobalSearch.score('mh12', b), greaterThan(0));
      expect(GlobalSearch.score('accepted', b), greaterThan(0));
      final l = GlobalSearch.fromLoad(await load('l1'));
      expect(l.kind, SearchKind.load);
      expect(GlobalSearch.score('steel', l), greaterThan(0));
      final t = GlobalSearch.fromTicket(await ticket('t1', 'Payment problem'));
      expect(GlobalSearch.score('upi', t), greaterThan(0), reason: 'the description is searchable');
      final p = GlobalSearch.fromPlace(await place('p1', 'Home', '12 MG Road'));
      expect(GlobalSearch.score('mg road', p), greaterThan(0));
      final cities = GlobalSearch.cities();
      expect(cities.any((c) => c.id == 'Mumbai'), isTrue);
      expect(GlobalSearch.score('bombay', cities.firstWhere((c) => c.id == 'Mumbai')), greaterThan(0));
      final h = GlobalSearch.helpTopics([(3, 'How do I pay?', 'Pay the driver by UPI')]);
      expect(h.single.id, '3');
      expect(GlobalSearch.score('upi', h.single), greaterThan(0));
    });
  });

  group('RecentSearches', () {
    test('newest first, repeats move up, max 8, short ones ignored', () async {
      expect(await RecentSearches.load(), isEmpty);
      await RecentSearches.add('delhi');
      await RecentSearches.add('x');
      await RecentSearches.add('  pune   mumbai ');
      await RecentSearches.add('DELHI');
      expect(await RecentSearches.load(), ['DELHI', 'pune mumbai']);
      for (var i = 0; i < 12; i++) {
        await RecentSearches.add('query $i');
      }
      final l = await RecentSearches.load();
      expect(l.length, RecentSearches.max);
      expect(l.first, 'query 11');
      await RecentSearches.clear();
      expect(await RecentSearches.load(), isEmpty);
    });
  });

  group('GlobalSearchScreen', () {
    late Booking b1;
    late Load l1;
    late SupportTicket t1;
    late SavedPlace p1;

    setUp(() async {
      b1 = await booking('b1');
      l1 = await load('l1');
      t1 = await ticket('t1', 'Payment problem');
      p1 = await place('p1', 'Delhi warehouse', 'Okhla');
    });

    Future<void> open(WidgetTester t, {bool driver = false, Duration debounce = Duration.zero, List<Load>? loads, String initial = ''}) async {
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(app(GlobalSearchScreen(
        isDriver: driver,
        debounce: debounce,
        initialQuery: initial,
        bookings: Stream.value([b1]),
        loads: Stream.value(loads ?? [l1]),
        tickets: Stream.value([t1]),
        places: Stream.value([p1]),
      )));
      await settle(t);
    }

    Future<void> type(WidgetTester t, String text) async {
      await t.enterText(find.byKey(const ValueKey('globalSearchField')), text);
      await settle(t);
    }

    testWidgets('empty: a hint, no results yet', (t) async {
      await open(t);
      expect(find.text('Search bookings, loads, tickets, places and help'), findsOneWidget);
      expect(find.byKey(const ValueKey('hit_booking_b1')), findsNothing);
    });

    testWidgets('results appear in sections with headers', (t) async {
      await open(t);
      await type(t, 'delhi');
      expect(find.byKey(const ValueKey('hit_load_l1')), findsOneWidget);
      expect(find.byKey(const ValueKey('hit_place_p1')), findsOneWidget);
      expect(find.byKey(const ValueKey('hit_city_Delhi')), findsOneWidget);
      expect(find.text('My loads'), findsOneWidget);
      expect(find.text('Saved places'), findsOneWidget);
      expect(find.text('Cities'), findsOneWidget);
      await type(t, 'ravi');
      expect(find.byKey(const ValueKey('hit_booking_b1')), findsOneWidget);
      await type(t, 'payment');
      expect(find.byKey(const ValueKey('hit_ticket_t1')), findsOneWidget);
    });

    testWidgets('help topics are found by their question and answer words', (t) async {
      await open(t);
      await type(t, 'otp');
      expect(find.text('Help topics'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w.key is ValueKey && (w.key as ValueKey).value.toString().startsWith('hit_help_')), findsWidgets);
    });

    testWidgets('typing is debounced', (t) async {
      await open(t, debounce: const Duration(milliseconds: 300));
      await t.enterText(find.byKey(const ValueKey('globalSearchField')), 'ravi');
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('hit_booking_b1')), findsNothing);
      await t.enterText(find.byKey(const ValueKey('globalSearchField')), 'rav');
      await t.pump(const Duration(milliseconds: 250));
      expect(find.byKey(const ValueKey('hit_booking_b1')), findsNothing, reason: 'the timer restarted');
      await t.pump(const Duration(milliseconds: 100));
      await t.pump();
      expect(find.byKey(const ValueKey('hit_booking_b1')), findsOneWidget);
    });

    testWidgets('no result says so', (t) async {
      await open(t);
      await type(t, 'qqqq');
      expect(find.text('Nothing found for "qqqq"'), findsOneWidget);
    });

    testWidgets('a driver searches own trips and open loads, not cities or places', (t) async {
      await open(t, driver: true);
      await type(t, 'delhi');
      expect(find.byKey(const ValueKey('hit_load_l1')), findsOneWidget);
      expect(find.byKey(const ValueKey('hit_place_p1')), findsNothing);
      expect(find.byKey(const ValueKey('hit_city_Delhi')), findsNothing);
      expect(find.text('Open loads'), findsOneWidget);
      expect(find.text('My loads'), findsNothing);
    });

    testWidgets('show all expands a capped section', (t) async {
      final many = [for (var i = 0; i < 8; i++) await load('m$i', pickup: 'Surat', drop: 'Town$i')];
      await open(t, loads: many);
      await type(t, 'surat');
      expect(find.byKey(const ValueKey('hit_load_m0')), findsOneWidget);
      expect(find.byKey(const ValueKey('hit_load_m7')), findsNothing);
      expect(find.text('Show all 8'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('showAll_load')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('hit_load_m7')), findsOneWidget);
      expect(find.byKey(const ValueKey('showAll_load')), findsNothing);
    });

    testWidgets('tapping hits goes through AppRoutes', (t) async {
      final calls = <String>[];
      AppRoutes.openBooking = (c, id, {required isDriver}) => calls.add('booking:$id:$isDriver');
      AppRoutes.openLoad = (c, id, {required isDriver}) => calls.add('load:$id:$isDriver');
      AppRoutes.openPostLoad = (c, {pickup, drop}) => calls.add('post:$pickup');
      await open(t);
      await type(t, 'delhi');
      await t.tap(find.byKey(const ValueKey('hit_load_l1')));
      await t.tap(find.byKey(const ValueKey('hit_place_p1')));
      await t.tap(find.byKey(const ValueKey('hit_city_Delhi')));
      await type(t, 'ravi');
      await t.tap(find.byKey(const ValueKey('hit_booking_b1')));
      expect(calls, ['load:l1:false', 'post:Delhi warehouse', 'post:Delhi', 'booking:b1:false']);
    });

    testWidgets('a driver opens a booking as a driver', (t) async {
      final calls = <String>[];
      AppRoutes.openBooking = (c, id, {required isDriver}) => calls.add('booking:$id:$isDriver');
      await open(t, driver: true);
      await type(t, 'ravi');
      await t.tap(find.byKey(const ValueKey('hit_booking_b1')));
      expect(calls, ['booking:b1:true']);
    });

    testWidgets('a ticket opens its thread; a help hit opens that question', (t) async {
      await open(t);
      await type(t, 'payment problem');
      await t.tap(find.byKey(const ValueKey('hit_ticket_t1')));
      await t.pumpAndSettle();
      expect(find.byType(TicketDetailScreen), findsOneWidget);
      Navigator.of(t.element(find.byType(TicketDetailScreen))).pop();
      await t.pumpAndSettle();
      await type(t, 'faq');
      // Open the first help hit, whatever it is.
      final help = find.byWidgetPredicate((w) => w.key is ValueKey && (w.key as ValueKey).value.toString().startsWith('hit_help_'));
      if (help.evaluate().isEmpty) await type(t, 'cancel');
      await t.tap(help.first);
      await t.pumpAndSettle();
      expect(find.byType(HelpScreen), findsOneWidget);
    });

    testWidgets('a pasted load link offers to open that load', (t) async {
      final calls = <String>[];
      AppRoutes.openLoad = (c, id, {required isDriver}) => calls.add('$id:$isDriver');
      await open(t, driver: true);
      await type(t, ShareLinks.loadLink('abc123'));
      expect(find.byKey(const ValueKey('openShared')), findsOneWidget);
      expect(find.text('Open the shared load'), findsOneWidget);
      expect(find.byKey(const ValueKey('hit_load_l1')), findsNothing);
      await t.tap(find.byKey(const ValueKey('openShared')));
      expect(calls, ['abc123:true']);
      await type(t, 'https://example.com/other/path');
      expect(find.byKey(const ValueKey('openShared')), findsNothing);
    });

    testWidgets('recent searches: remembered on opening a hit, shown when empty, tappable, clearable', (t) async {
      AppRoutes.openLoad = (c, id, {required isDriver}) {};
      await open(t);
      await type(t, 'delhi');
      await t.tap(find.byKey(const ValueKey('hit_load_l1')));
      await t.pumpAndSettle();
      expect(await t.runAsync(RecentSearches.load), ['delhi']);
      await t.pumpWidget(const SizedBox()); // a fresh screen
      await open(t);
      expect(find.text('Recent searches'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('recent_0')));
      await settle(t);
      expect(find.byKey(const ValueKey('hit_load_l1')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('clearSearch')));
      await settle(t);
      expect(find.byKey(const ValueKey('clearRecent')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('clearRecent')));
      await settle(t);
      expect(find.text('Search bookings, loads, tickets, places and help'), findsOneWidget);
      expect(await t.runAsync(RecentSearches.load), isEmpty);
    });

    testWidgets('submitting from the keyboard remembers the search', (t) async {
      await open(t);
      await t.enterText(find.byKey(const ValueKey('globalSearchField')), 'surat');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await settle(t);
      expect(await t.runAsync(RecentSearches.load), ['surat']);
    });

    testWidgets('the clear button empties the field', (t) async {
      await open(t);
      await type(t, 'delhi');
      await t.tap(find.byKey(const ValueKey('clearSearch')));
      await settle(t);
      expect(t.widget<TextField>(find.byKey(const ValueKey('globalSearchField'))).controller!.text, '');
      expect(find.byKey(const ValueKey('hit_load_l1')), findsNothing);
    });

    testWidgets('fits 360x640 at 1.6x text', (t) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(1.6)), child: child!),
        home: LanguageScope(
          notifier: languageNotifier,
          child: GlobalSearchScreen(isDriver: false, debounce: Duration.zero, initialQuery: 'delhi', bookings: Stream.value([b1]), loads: Stream.value([l1]), tickets: Stream.value([t1]), places: Stream.value([p1])),
        ),
      ));
      await settle(t);
      expect(t.takeException(), isNull);
    });
  });

  group('LoadByIdScreen and the shared-link plumbing', () {
    testWidgets('an open load shows its card and the action', (t) async {
      final l = await load('s1');
      await t.pumpWidget(app(LoadByIdScreen(loadId: 's1', stream: () => Stream.value(l), action: (x) => Text('ACTION ${x.id}'))));
      await settle(t);
      expect(find.byKey(const ValueKey('sharedLoad_s1')), findsOneWidget);
      expect(find.text('ACTION s1'), findsOneWidget);
    });

    testWidgets('a taken load shows the card without the action; a missing one says it is gone', (t) async {
      final l = await load('s2', status: 'matched');
      await t.pumpWidget(app(LoadByIdScreen(loadId: 's2', stream: () => Stream.value(l), action: (x) => const Text('ACTION'))));
      await settle(t);
      expect(find.byKey(const ValueKey('sharedLoad_s2')), findsOneWidget);
      expect(find.text('ACTION'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(app(LoadByIdScreen(loadId: 'none', stream: () => Stream.value(null))));
      await settle(t);
      expect(find.byKey(const ValueKey('loadGone')), findsOneWidget);
      expect(find.text('This load is not available any more'), findsOneWidget);
    });

    test('LoadService.watchById: the load, or null when missing', () async {
      await load('w1');
      expect((await LoadService.watchById('w1').first)!.id, 'w1');
      expect(await LoadService.watchById('nope').first, isNull);
    });

    test('registerRouteHooks fills every hook', () {
      registerRouteHooks();
      expect(AppRoutes.openBooking, isNotNull);
      expect(AppRoutes.openLoad, isNotNull);
      expect(AppRoutes.openPostLoad, isNotNull);
    });

    testWidgets('Help can open with one question expanded', (t) async {
      await t.pumpWidget(app(const HelpScreen(openFaq: 2)));
      await t.pumpAndSettle();
      expect(find.text(globalSearchStrings.isEmpty ? '' : 'x'), findsNothing);
      expect(t.widget<ExpansionTile>(find.byKey(const ValueKey('faq2'))).initiallyExpanded, isTrue);
      expect(t.widget<ExpansionTile>(find.byKey(const ValueKey('faq1'))).initiallyExpanded, isFalse);
    });
  });

  test('every new string has 12 non-empty languages and the same placeholders', () {
    final ph = RegExp(r'\{(\w+)\}');
    for (final e in globalSearchStrings.entries) {
      expect(e.value.length, 12, reason: e.key);
      expect(e.value.every((s) => s.trim().isNotEmpty), isTrue, reason: e.key);
      final want = ph.allMatches(e.value[0]).map((m) => m[1]).toSet();
      for (var i = 1; i < 12; i++) {
        expect(ph.allMatches(e.value[i]).map((m) => m[1]).toSet(), want, reason: '${e.key}/$i');
      }
    }
  });
}
