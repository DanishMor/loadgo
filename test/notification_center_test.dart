import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/app_notification.dart';
import 'package:transport_app/core/models/user_settings.dart';
import 'package:transport_app/core/notifications/notifications_screen.dart';
import 'package:transport_app/core/reminders/reminders.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/notification_service.dart';
import 'package:transport_app/core/services/settings_service.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;

  setUp(() async {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'u1');
    SettingsService.prefs.value = const NotificationPrefs();
    await db.collection('users').doc('u1').set({'phone': '+91'});
    int n = 0;
    Future<void> add(String type, {String message = 'm', bool read = false}) => db.collection('notifications').add({
          'userId': 'u1', 'type': type, 'message': '$message${n++}', 'relatedId': 'b1', 'read': read, 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 5, 8, n)),
        });
    await add(NotificationType.statusChanged);
    await add(NotificationType.paymentMarked);
    await add(NotificationType.ratingReceived, read: true);
    await add(NotificationType.accidentReported);
  });

  tearDown(() => SettingsService.prefs.value = const NotificationPrefs());

  test('MASTER-5 Task 29: notifications sit under Today / Yesterday / Earlier', () {
    final now = DateTime(2026, 10, 8, 10);
    expect(NotifGroup.of(DateTime(2026, 10, 8, 0, 1), now), 0);
    expect(NotifGroup.of(DateTime(2026, 10, 7, 23, 59), now), 1);
    expect(NotifGroup.of(DateTime(2026, 10, 6, 12), now), 2);
    expect(NotifGroup.of(null, now), 2);
    expect(NotifGroup.of(DateTime(2026, 10, 9), now), 0, reason: 'a time a little ahead (clock skew) counts as today');
    for (final k in NotifGroup.keys) {
      expect(T.get(k, AppLanguage.tamil).trim(), isNotEmpty);
    }
  });

  test('categories of notification types and reminders', () {
    expect(NotifCategory.ofType(NotificationType.loadAccepted), NotifCategory.bookings);
    expect(NotifCategory.ofType(NotificationType.paymentConfirmed), NotifCategory.payments);
    expect(NotifCategory.ofType(NotificationType.ratingReceived), NotifCategory.ratings);
    expect(NotifCategory.ofReminder(ReminderKind.tripDelayed), NotifCategory.bookings);
    expect(NotifCategory.ofReminder(ReminderKind.counterWaiting), NotifCategory.offers);
    expect(NotifCategory.ofReminder(ReminderKind.vehicleDocs), NotifCategory.reminders);
  });

  test('prefs: five switches round-trip; safety alerts cannot be muted', () {
    const off = NotificationPrefs(bookingUpdates: false, payments: false, ratings: false, promotions: false, reminders: false);
    expect(off.toMap(), {'bookingUpdates': false, 'ratings': false, 'promotions': false, 'payments': false, 'reminders': false});
    expect(NotificationPrefs.fromMap(off.toMap()).isOn(NotifCategory.payments), isFalse);
    expect(NotificationPrefs.fromMap({'ratings': false}).payments, isTrue, reason: 'missing means on');
    expect(off.allows(NotificationType.statusChanged), isFalse);
    expect(off.allows(NotificationType.paymentMarked), isFalse);
    expect(off.allows(NotificationType.accidentReported), isTrue);
    expect(off.allows(NotificationType.breakdownReported), isTrue);
    expect(off.allowsReminder(ReminderKind.vehicleDocs), isFalse);
    expect(const NotificationPrefs().set(NotifCategory.reminders, false).allowsReminder(ReminderKind.serviceDue), isFalse);
    expect(const NotificationPrefs().set(NotifCategory.reminders, false).allowsReminder(ReminderKind.pickupSoon), isTrue);
  });

  test('the unread count honours the switches, the center stream does not need them', () async {
    expect(await NotificationService.watchUnreadCount().first, 3);
    SettingsService.prefs.value = const NotificationPrefs(payments: false, bookingUpdates: false);
    expect(await NotificationService.watchUnreadCount().first, 1, reason: 'only the accident alert stays');
    expect((await NotificationService.watchMine(applyPrefs: false).first).length, 4);
  });

  testWidgets('center: category chips filter, a switch hides a category at once, reminders respect it', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const vehicleDocs = Reminder(kind: ReminderKind.vehicleDocs, id: 'docs', args: {'n': 2}, priority: 3);
    const delayed = Reminder(kind: ReminderKind.tripDelayed, id: 'late', args: {'route': 'A → B', 'minutes': 90}, relatedId: 'b1', priority: 0);
    await tester.pumpWidget(MaterialApp(home: NotificationsScreen(onOpenBooking: (_) {}, isDriver: true, reminders: Stream.value(const [vehicleDocs, delayed]))));
    await settle(tester);
    expect(find.byKey(const ValueKey('notifReminder_docs')), findsOneWidget);
    expect(find.byKey(const ValueKey('notifReminder_late')), findsOneWidget);
    expect(find.text('Payments'), findsWidgets);

    // Payments chip: reminders of other categories go, so do other notifications.
    await tester.tap(find.byKey(const ValueKey('notifCat_payments')));
    await settle(tester);
    expect(find.byKey(const ValueKey('notifReminder_docs')), findsNothing);
    expect(find.byKey(const ValueKey('notifReminder_late')), findsNothing);

    await tester.ensureVisible(find.byKey(const ValueKey('notifCat_reminders')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('notifCat_reminders')));
    await settle(tester);
    expect(find.byKey(const ValueKey('notifReminder_docs')), findsOneWidget);
    expect(find.byKey(const ValueKey('notifReminder_late')), findsNothing);

    // Mute the reminders category from the settings sheet.
    await tester.tap(find.byKey(const ValueKey('notifSettings')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('notifSwitch_reminders')));
    await settle(tester);
    expect(SettingsService.prefs.value.reminders, isFalse);
    expect((await db.collection('users').doc('u1').get())['notificationPrefs']['reminders'], false);
    expect(find.text('Safety alerts (accident, breakdown) are always on.'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10)); // dismiss the sheet
    await settle(tester);
    expect(find.byKey(const ValueKey('notifCat_reminders')), findsNothing, reason: 'muted category has no chip');
    expect(find.byKey(const ValueKey('notifReminder_docs')), findsNothing);
    expect(find.byKey(const ValueKey('notifReminder_late')), findsOneWidget, reason: 'back on All');
  });
}
