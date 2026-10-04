import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/paged.dart';
import 'package:transport_app/features/bookings/booking_list_view.dart';
import 'package:transport_app/features/bookings/customer_bookings_view.dart';
import 'package:transport_app/features/loads/available_loads_view.dart';
import 'package:transport_app/core/services/connectivity_service.dart';
import 'package:transport_app/core/widgets/live_stream.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  test('loadErrorKey maps errors to friendly messages', () {
    expect(loadErrorKey(FirebaseException(plugin: 'firestore', code: 'unavailable')), 'errorNetwork');
    expect(loadErrorKey(FirebaseException(plugin: 'firestore', code: 'permission-denied')), 'errorNoAccess');
    expect(loadErrorKey(FirebaseException(plugin: 'firestore', code: 'internal')), 'errorGeneric');
    expect(loadErrorKey(TimeoutException('x')), 'errorNetwork');
    expect(loadErrorKey(StateError('x')), 'errorGeneric');
  });

  testWidgets('error shows a friendly message and Retry re-subscribes', (tester) async {
    var calls = 0;
    Stream<List<int>> factory() {
      calls++;
      return calls == 1
          ? Stream.error(FirebaseException(plugin: 'firestore', code: 'unavailable', message: 'raw internal text'))
          : Stream.value([1, 2, 3]);
    }

    await tester.pumpWidget(host(LiveStream<List<int>>(stream: factory, builder: (_, d) => Text('items ${d.length}'))));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't connect. Check your internet and try again."), findsOneWidget);
    expect(find.textContaining('raw internal text'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('items 3'), findsOneWidget);
  });

  testWidgets('a stream that never emits shows the slow hint instead of spinning forever', (tester) async {
    final never = StreamController<int>();
    addTearDown(never.close);
    await tester.pumpWidget(host(LiveStream<int>(stream: () => never.stream, builder: (_, d) => Text('$d'))));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(seconds: 16));
    expect(find.text('This is taking longer than usual.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    // Late data still replaces the hint.
    never.add(7);
    await tester.pump();
    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('compact variant renders an inline retry card', (tester) async {
    await tester.pumpWidget(host(LiveStream<int>(
      stream: () => Stream.error(StateError('boom')),
      compact: true,
      builder: (_, d) => Text('$d'),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Something went wrong while loading.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  group('list screens: empty and error states', () {
    final failing = FirebaseException(plugin: 'firestore', code: 'unavailable');

    testWidgets('Available Loads', (tester) async {
      await tester.pumpWidget(host(AvailableLoadsView(loads: (_) => Stream.value(const Paged<Load>.all([])))));
      await tester.pumpAndSettle();
      expect(find.text('No open loads right now'), findsOneWidget);

      await tester.pumpWidget(host(AvailableLoadsView(key: UniqueKey(), loads: (_) => Stream.error(failing))));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('Trips (driver)', (tester) async {
      await tester.pumpWidget(host(BookingListView(
          title: 'Trips', bookings: (_) => Stream.value(const Paged<Booking>.all([])), emptyTitle: 'No trips', onOpen: (_) {})));
      await tester.pumpAndSettle();
      expect(find.text('No trips'), findsOneWidget);

      await tester.pumpWidget(host(BookingListView(
          key: UniqueKey(), title: 'Trips', bookings: (_) => Stream.error(failing), emptyTitle: 'No trips', onOpen: (_) {})));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('Bookings (customer)', (tester) async {
      await tester.pumpWidget(host(CustomerBookingsView(
          bookings: (_) => Stream.value(const Paged<Booking>.all([])), onOpenTracking: (_) {}, onOpenInvoice: (_) {})));
      await tester.pumpAndSettle();
      expect(find.text('No bookings yet'), findsOneWidget);

      await tester.pumpWidget(host(CustomerBookingsView(
          key: UniqueKey(), bookings: (_) => Stream.error(failing), onOpenTracking: (_) {}, onOpenInvoice: (_) {})));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('offline', () {
    tearDown(() => ConnectivityService.online.value = true);

    testWidgets('shows a clear no-internet message with Retry while nothing has loaded', (tester) async {
      ConnectivityService.online.value = false;
      await tester.pumpWidget(host(LiveStream<int>(
        stream: () => StreamController<int>().stream,
        builder: (_, d) => Text('$d'),
      )));
      await tester.pump();
      expect(find.text('No internet connection. Connect and try again.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('a network error while offline is reported as offline, and data still wins', (tester) async {
      ConnectivityService.online.value = false;
      await tester.pumpWidget(host(LiveStream<int>(
        stream: () => Stream.error(StateError('x')),
        builder: (_, d) => Text('$d'),
      )));
      await tester.pumpAndSettle();
      expect(find.text('No internet connection. Connect and try again.'), findsOneWidget);

      await tester.pumpWidget(host(LiveStream<int>(
        key: UniqueKey(),
        stream: () => Stream.value(7),
        builder: (_, d) => Text('cached $d'),
      )));
      await tester.pumpAndSettle();
      expect(find.text('cached 7'), findsOneWidget);
    });

    testWidgets('offline banner follows connectivity', (tester) async {
      await tester.pumpWidget(host(const OfflineBanner()));
      expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);
      ConnectivityService.online.value = false;
      await tester.pump();
      expect(find.text("You're offline. Showing saved data."), findsOneWidget);
    });
  });
}
