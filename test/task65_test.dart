import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/l10n/problem_report_strings.dart';
import 'package:transport_app/core/models/support_ticket.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/error_log_service.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/settings/help_screen.dart';
import 'package:transport_app/core/support/problem_report.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;

  setUp(() {
    languageNotifier.value = AppLanguage.english;
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'u1');
    FeaturesService.reset();
    ErrorLogService.reset();
  });

  group('ProblemReport.build', () {
    test('every kind maps to a ticket the rules accept', () {
      const cats = ['booking_issue', 'payment', 'dispute', 'safety', 'account', 'other'];
      for (final k in ProblemKind.values) {
        final r = ProblemReport.build(k, 'text');
        expect(cats, contains(r.category), reason: k.name);
        expect(r.subject.length, inInclusiveRange(3, 100));
        expect(r.description.length, lessThanOrEqualTo(1000));
      }
    });

    test('payment and safety use their own category; safety is urgent', () {
      expect(ProblemReport.build(ProblemKind.payment, '').category, TicketCategory.payment);
      final s = ProblemReport.build(ProblemKind.safety, '');
      expect((s.category, s.priority), (TicketCategory.safety, TicketPriority.urgent));
      expect(ProblemReport.build(ProblemKind.appBroke, '').priority, TicketPriority.normal);
      expect(ProblemReport.build(ProblemKind.otherPerson, '').category, TicketCategory.bookingIssue);
    });

    test('the description holds the words, screen, version, role, booking and last error', () {
      final r = ProblemReport.build(ProblemKind.appBroke, '  It closed  ', screen: 'trip', bookingId: 'b1', role: 'driver', lastError: 'Null check failed', version: '1.2.3+4');
      expect(r.description, 'It closed\n\nScreen: trip\nApp: 1.2.3+4\nRole: driver\nBooking: b1\nLast error: Null check failed');
    });

    test('no text: only the technical lines; long text and error are cut', () {
      final r = ProblemReport.build(ProblemKind.slow, '   ', version: 'v');
      expect(r.description, 'App: v');
      final long = ProblemReport.build(ProblemKind.other, 'x' * 900, lastError: 'e' * 400, screen: 's' * 300);
      expect(long.description.length, lessThanOrEqualTo(1000));
      expect(long.description.contains('e' * 151), isFalse);
    });

    test('never contains a phone number field', () {
      final r = ProblemReport.build(ProblemKind.other, 'hi', screen: 'help', role: 'customer');
      expect(r.description.contains('+91'), isFalse);
    });
  });

  group('ErrorLogService.lastError', () {
    test('keeps the newest cleaned message even when nothing is written', () async {
      expect(ErrorLogService.lastError, isNull);
      await ErrorLogService.logSampled(StateError('boom for ravi@example.com 9876543210'), null);
      expect(ErrorLogService.lastError, 'Bad state: boom for #');
      await ErrorLogService.logSampled('second', null);
      expect(ErrorLogService.lastError, 'second');
    });
  });

  group('the sheet', () {
    Future<void> open(WidgetTester t) async {
      t.view.physicalSize = const Size(800, 2000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(home: LanguageScope(notifier: languageNotifier, child: const Scaffold(body: ReportProblemButton(bookingId: 'b1', screen: 'trip', role: 'driver')))));
      await t.tap(find.byKey(const ValueKey('reportProblem')));
      await t.pumpAndSettle();
    }

    testWidgets('sending without a kind asks to pick one', (t) async {
      await open(t);
      await t.tap(find.byKey(const ValueKey('prSend')));
      await t.pumpAndSettle();
      expect(find.text('Pick what went wrong first'), findsOneWidget);
      expect((await t.runAsync(() => db.collection('tickets').get()))!.docs, isEmpty);
    });

    testWidgets('a report becomes a support ticket for the booking', (t) async {
      await t.runAsync(() => db.collection('bookings').doc('b1').set({'driverId': 'u1', 'customerId': 'c1', 'status': 'in_transit', 'pickup': 'A', 'drop': 'B'}));
      await open(t);
      await t.tap(find.byKey(const ValueKey('prKind_payment')));
      await t.enterText(find.byKey(const ValueKey('prText')), 'Customer says paid but I got nothing');
      await t.tap(find.byKey(const ValueKey('prSend')));
      await settle(t);
      final docs = (await t.runAsync(() => db.collection('tickets').get()))!.docs;
      final d = docs.single.data();
      expect((d['category'], d['bookingId'], d['userId'], d['status']), ('payment', 'b1', 'u1', 'open'));
      expect(d['subject'], 'Problem: payment');
      expect(d['description'], contains('Customer says paid but I got nothing'));
      expect(d['description'], contains('Screen: trip'));
      expect(find.byKey(const ValueKey('prSend')), findsNothing, reason: 'sheet closed');
    });

    testWidgets('the feature switch hides the button', (t) async {
      FeaturesService.notifier.value = const Features(flags: {FeatureKey.problemReport: false});
      await t.pumpWidget(MaterialApp(home: LanguageScope(notifier: languageNotifier, child: const Scaffold(body: ReportProblemButton()))));
      expect(find.byKey(const ValueKey('reportProblem')), findsNothing);
    });

    testWidgets('Help has the entry', (t) async {
      await t.pumpWidget(MaterialApp(home: LanguageScope(notifier: languageNotifier, child: const HelpScreen())));
      await t.scrollUntilVisible(find.byKey(const ValueKey('helpProblem')), 300, scrollable: find.byType(Scrollable).first);
      expect(find.byKey(const ValueKey('helpProblem')), findsOneWidget);
    });
  });

  test('problem report strings: a label for every kind, 12 languages', () {
    for (final k in ProblemKind.values) {
      expect(problemReportStrings.containsKey('prKind_${k.name}'), isTrue, reason: k.name);
    }
    for (final e in problemReportStrings.entries) {
      expect(e.value.length, 12, reason: e.key);
      expect(e.value.every((s) => s.trim().isNotEmpty), isTrue, reason: e.key);
    }
  });
}
