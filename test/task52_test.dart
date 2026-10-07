import 'dart:math' show Random;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_health_screen.dart';
import 'package:transport_app/admin/admin_lists.dart';
import 'package:transport_app/admin/admin_templates_screen.dart';
import 'package:transport_app/core/admin/admin_export.dart';
import 'package:transport_app/core/admin/reply_templates.dart';
import 'package:transport_app/core/admin/staff_roles.dart';
import 'package:transport_app/core/l10n/admin_tools_strings.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/admin_console_service.dart';
import 'package:transport_app/core/services/admin_user_service.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/crash_service.dart';
import 'package:transport_app/core/services/error_log_service.dart';
import 'package:transport_app/core/services/reply_template_service.dart';
import 'package:transport_app/core/support/support_screens.dart';

import 'test_utils.dart';

Widget host(Widget child) => MaterialApp(home: LanguageScope(notifier: languageNotifier, child: child));

void tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() {
    languageNotifier.value = AppLanguage.english;
    db = FakeFirebaseFirestore();
    uid = 'admin1';
    Backend.useFakes(db: db, uid: () => uid);
    ErrorLogService.reset();
  });

  group('ReplyTemplate', () {
    test('parse keeps valid items, skips junk, caps at 20', () {
      final doc = {
        'items': [
          {'id': 'a', 'title': ' Hello ', 'text': ' Hi there '},
          {'id': 'b', 'title': '', 'text': 'x'},
          {'id': 'c', 'title': 'x'},
          'junk',
          null,
          for (var i = 0; i < 30; i++) {'id': 'n$i', 'title': 'T$i', 'text': 'x'},
        ],
      };
      final list = ReplyTemplate.parse(doc);
      expect(list.length, 20);
      expect(list.first.title, 'Hello');
      expect(list.first.text, 'Hi there');
      expect(ReplyTemplate.parse(null), isEmpty);
      expect(ReplyTemplate.parse({'items': 'x'}), isEmpty);
    });

    test('check', () {
      expect(ReplyTemplate.check('a', 'b'), isNull);
      expect(ReplyTemplate.check('  ', 'b'), 'empty');
      expect(ReplyTemplate.check('a', ' '), 'empty');
      expect(ReplyTemplate.check('a' * 41, 'b'), 'long');
      expect(ReplyTemplate.check('a' * 40, 'b' * 500), isNull);
      expect(ReplyTemplate.check('a', 'b' * 501), 'long');
    });

    test('defaults are valid', () {
      expect(ReplyTemplate.defaults.length, 4);
      for (final t in ReplyTemplate.defaults) {
        expect(ReplyTemplate.check(t.title, t.text), isNull);
      }
    });
  });

  group('ReplyTemplateService', () {
    test('built-in defaults until something is saved', () async {
      expect((await ReplyTemplateService.load()).length, 4);
    });

    test('add, edit, remove; the saved list replaces the defaults; each save is audited', () async {
      var list = await ReplyTemplateService.upsert(title: 'Thanks', text: 'Thank you');
      expect(list.length, 5, reason: 'defaults + the new one are saved together');
      final id = list.last.id;
      list = await ReplyTemplateService.upsert(id: id, title: 'Thanks!', text: 'Thank you very much');
      expect(list.length, 5);
      expect(list.last.title, 'Thanks!');
      expect((await ReplyTemplateService.load()).last.text, 'Thank you very much');
      list = await ReplyTemplateService.remove(id);
      expect(list.length, 4);
      final audit = (await db.collection('audit_events').where('type', isEqualTo: 'config_change').get()).docs;
      expect(audit.length, 3);
      expect(audit.every((d) => (d['data'] as Map)['doc'] == 'reply_templates'), isTrue);
    });

    test('bad input and the 20 limit', () async {
      expect(() => ReplyTemplateService.upsert(title: '', text: 'x'), throwsA(isA<TemplateException>().having((e) => e.reason, 'reason', 'empty')));
      expect(() => ReplyTemplateService.upsert(title: 'a', text: 'x' * 501), throwsA(isA<TemplateException>().having((e) => e.reason, 'reason', 'long')));
      await db.collection('config').doc('reply_templates').set({
        'items': [for (var i = 0; i < 20; i++) {'id': 'n$i', 'title': 'T$i', 'text': 'x'}],
      });
      expect(() => ReplyTemplateService.upsert(title: 'one more', text: 'x'), throwsA(isA<TemplateException>().having((e) => e.reason, 'reason', 'limit')));
      expect((await ReplyTemplateService.upsert(id: 'n3', title: 'changed', text: 'x')).length, 20);
    });

    test('an empty saved list stays empty (not the defaults)', () async {
      await db.collection('config').doc('reply_templates').set({'items': []});
      expect(await ReplyTemplateService.load(), isEmpty);
    });
  });

  group('AdminExport', () {
    test('masking', () {
      expect(AdminExport.maskPhone('+91 98765 43210'), '**********10');
      expect(AdminExport.maskPhone('12'), '**');
      expect(AdminExport.maskPhone('1'), '*');
      expect(AdminExport.maskPhone(null), '');
      expect(AdminExport.maskEmail('ravi@example.com'), 'r***@example.com');
      expect(AdminExport.maskEmail('nope'), '***');
      expect(AdminExport.maskEmail(''), '');
    });

    test('cells are quoted, and a leading = + - @ cannot become a formula', () {
      expect(AdminExport.cell('a,b'), '"a,b"');
      expect(AdminExport.cell('say "hi"'), '"say ""hi"""');
      expect(AdminExport.cell('=SUM(A1)'), "'=SUM(A1)");
      expect(AdminExport.cell('+91'), "'+91");
      expect(AdminExport.cell('-5'), '-5', reason: 'a plain number stays a number');
      expect(AdminExport.cell(null), '');
      expect(AdminExport.cell(0), '0');
    });

    test('users CSV: masked phone and e-mail, no KYC numbers', () {
      final csv = AdminExport.usersCsv([
        ('u1', {'role': 'driver', 'name': 'Ravi, K', 'phone': '+919876543210', 'email': 'ravi@example.com', 'riskTier': 'review', 'verificationStatus': 'approved', 'cancelCount': 2, 'createdAt': Timestamp.fromDate(DateTime(2026, 3, 9)), 'driverKyc': {'panNumber': 'ABCDE1234F', 'licenceNumber': 'DL123'}}),
        ('u2', <String, dynamic>{}),
      ]).split('\n');
      expect(csv[0], AdminExport.usersHeader);
      expect(csv[1], 'u1,driver,"Ravi, K",**********10,r***@example.com,review,approved,,2,2026-03-09');
      expect(csv[2], 'u2,,,,,normal,,,0,');
      expect(csv.join('\n').contains('ABCDE1234F'), isFalse);
      expect(csv.join('\n').contains('9876543210'), isFalse);
    });

    test('bookings CSV: rupees from paise, cancel info, ids only', () async {
      Future<Booking> mk(String id, Map<String, Object?> extra) async {
        await db.collection('bookings').doc(id).set({
          'driverId': 'd1', 'customerId': 'c1', 'status': 'delivered', 'pickup': 'Delhi', 'drop': 'Jaipur', 'cargoType': 'Steel, tubes', 'vehicleType': '20ft',
          'vehicleNumber': 'MH12AB1234', 'driverName': 'Ravi', 'driverPhone': '+919800000000', 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 2)), ...extra,
        });
        return Booking.fromDoc(await db.collection('bookings').doc(id).get());
      }

      final a = await mk('b1', {'agreedFarePaise': 123456});
      final b = await mk('b2', {'status': 'cancelled', 'cancellation': {'by': 'driver', 'chargePaise': 0, 'reason': 'vehicle_problem'}});
      final csv = AdminExport.bookingsCsv([a, b]).split('\n');
      expect(csv[0], AdminExport.bookingsHeader);
      expect(csv[1], 'b1,2026-10-02,delivered,Delhi,Jaipur,"Steel, tubes",20ft,MH12AB1234,1234.56,pending,d1,c1,,');
      expect(csv[2], 'b2,2026-10-02,cancelled,Delhi,Jaipur,"Steel, tubes",20ft,MH12AB1234,,pending,d1,c1,driver,vehicle_problem');
      expect(csv.join('\n').contains('9800000000'), isFalse);
      expect(csv.join('\n').contains('Ravi'), isFalse);
    });
  });

  group('AdminConsoleService exports and health', () {
    test('usersCsv masks; bookingsCsv filters by status', () async {
      await db.collection('users').doc('u1').set({'name': 'A', 'phone': '+919999999999', 'role': 'customer'});
      final csv = await AdminConsoleService.usersCsv();
      expect(csv.contains('9999999999'), isFalse);
      expect(csv, contains('u1,customer,A,**********99'));
      for (final e in {'x1': 'delivered', 'x2': 'cancelled'}.entries) {
        await db.collection('bookings').doc(e.key).set({'status': e.value, 'pickup': 'A', 'drop': 'B', 'createdAt': Timestamp.now()});
      }
      expect((await AdminConsoleService.bookingsCsv()).split('\n').length, 3);
      final only = (await AdminConsoleService.bookingsCsv(status: 'cancelled')).split('\n');
      expect(only.length, 2);
      expect(only[1], startsWith('x2,'));
    });

    test('health counts', () async {
      await db.collection('users').doc('u1').set({'name': 'A'});
      await db.collection('users').doc('u2').set({'name': 'B'});
      await db.collection('loads').doc('l1').set({'status': 'open'});
      await db.collection('bookings').doc('b1').set({'status': 'accepted'});
      for (final s in ['open', 'in_progress', 'closed']) {
        await db.collection('tickets').add({'status': s});
      }
      await db.collection('deletion_requests').doc('u1').set({'status': 'pending'});
      await db.collection('deletion_requests').doc('u2').set({'status': 'done'});
      final h = await AdminConsoleService.health();
      expect([h.users, h.loads, h.bookings, h.openTickets, h.pendingDeletions], [2, 1, 1, 2, 1]);
    });
  });

  group('bulk tier change', () {
    Future<void> seedUsers(Map<String, String> tiers) async {
      for (final e in tiers.entries) {
        await db.collection('users').doc(e.key).set({'name': e.key, 'riskTier': e.value});
      }
    }

    Future<String> tier(String id) async => (await db.collection('users').doc(id).get())['riskTier'] as String;

    test('hold: restricted, a reason is needed, self / banned / already-held are skipped, each audited', () async {
      final current = {'u1': 'normal', 'u2': 'review', 'u3': 'restricted', 'u4': 'banned', 'admin1': 'normal', 'u5': 'suspended'};
      await seedUsers(current);
      expect(() => AdminUserService.bulkSetTier(current, 'restricted', action: UserAction.bulkHold, reason: 'ab'), throwsA(isA<UserActionException>()));
      final r = await AdminUserService.bulkSetTier(current, 'restricted', action: UserAction.bulkHold, reason: ' burst of loads ');
      expect((r.changed, r.skipped), (3, 3));
      expect([await tier('u1'), await tier('u2'), await tier('u3'), await tier('u4'), await tier('admin1'), await tier('u5')], ['restricted', 'restricted', 'restricted', 'banned', 'normal', 'restricted']);
      final u1 = (await db.collection('users').doc('u1').get()).data()!;
      expect(u1['riskReason'], 'burst of loads');
      final audit = (await db.collection('audit_events').where('type', isEqualTo: 'user_action').get()).docs;
      expect(audit.length, 3);
      final row = audit.firstWhere((d) => d['targetId'] == 'u2').data();
      expect(row['actorId'], 'admin1');
      expect(row['data'], {'action': 'bulk_hold', 'reason': 'burst of loads', 'from': 'review', 'to': 'restricted', 'bulk': true});
    });

    test('unhold: only restricted users go back to normal, a reason is optional', () async {
      final current = {'u1': 'restricted', 'u2': 'suspended', 'u3': 'normal', 'u4': 'restricted'};
      await seedUsers(current);
      final r = await AdminUserService.bulkSetTier(current, 'normal', action: UserAction.bulkUnhold);
      expect((r.changed, r.skipped), (2, 2));
      expect([await tier('u1'), await tier('u2'), await tier('u3'), await tier('u4')], ['normal', 'suspended', 'normal', 'normal']);
    });

    test('set status: review, restricted, suspended or normal, never banned', () async {
      final current = {'u1': 'normal', 'u2': 'normal'};
      await seedUsers(current);
      await AdminUserService.bulkSetTier(current, 'suspended', action: UserAction.bulkStatus, reason: 'checking papers');
      expect(await tier('u1'), 'suspended');
      expect(() => AdminUserService.bulkSetTier(current, 'banned', action: UserAction.bulkStatus, reason: 'fraud'), throwsArgumentError);
      expect(() => AdminUserService.bulkSetTier(current, 'review', action: 'nope', reason: 'abc'), throwsArgumentError);
      expect(() => AdminUserService.bulkSetTier(current, 'review', action: UserAction.bulkStatus), throwsA(isA<UserActionException>()));
    });

    test('150 users are written in two batches', () async {
      final current = {for (var i = 0; i < 150; i++) 'm$i': 'normal'};
      await seedUsers(current);
      final r = await AdminUserService.bulkSetTier(current, 'review', action: UserAction.bulkStatus, reason: 'sweep');
      expect(r.changed, 150);
      expect((await db.collection('audit_events').get()).docs.length, 150);
      expect(await tier('m149'), 'review');
    });

    test('nothing to change writes nothing', () async {
      final r = await AdminUserService.bulkSetTier({'u1': 'restricted'}, 'restricted', action: UserAction.bulkHold, reason: 'again');
      expect((r.changed, r.skipped), (0, 1));
      expect((await db.collection('audit_events').get()).docs, isEmpty);
    });
  });

  group('ErrorLogService', () {
    test('sanitize removes e-mail, links and long numbers, keeps short numbers', () {
      expect(ErrorLogService.sanitize('Failed for ravi@example.com at https://x.in/a?id=9 phone 9876543210 line 42'), 'Failed for at phone # line 42');
      expect(ErrorLogService.sanitize('a\n  b\t c'), 'a b c');
      expect(ErrorLogService.sanitize('x' * 400).length, 300);
    });

    test('the screen comes from the first app file in the stack', () {
      final stack = StackTrace.fromString('#0 foo (dart:core/x.dart:1)\n#1 build (package:transport_app/driver/driver_trip_screen.dart:120:5)\n#2 other (package:transport_app/core/x.dart:1:1)');
      expect(ErrorLogService.screenFromStack(stack), 'driver/driver_trip_screen.dart');
      expect(ErrorLogService.screenFromStack(null), 'unknown');
      expect(ErrorLogService.screenFromStack(StackTrace.fromString('#0 foo (dart:core/x.dart:1)')), 'unknown');
    });

    Future<List<Map<String, dynamic>>> docs() async => [for (final d in (await db.collection('app_errors').get()).docs) d.data()];

    test('writes a sample: message, screen, kind, version, time; no user id', () async {
      ErrorLogService.enabled = true;
      ErrorLogService.sampleRate = 1;
      final ok = await ErrorLogService.logSampled(StateError('Bad state for 9876543210'), StackTrace.fromString('#0 f (package:transport_app/core/a.dart:1:1)'), fatal: true);
      expect(ok, isTrue);
      final d = (await docs()).single;
      expect(d['message'], 'Bad state: Bad state for #');
      expect(d['screen'], 'core/a.dart');
      expect(d['kind'], 'flutter');
      expect(d['appVersion'], '1.0.0+1');
      expect(d.containsKey('userId'), isFalse);
      expect(d['createdAt'], isNotNull);
      expect(d.keys.toSet(), {'message', 'screen', 'kind', 'appVersion', 'createdAt'});
    });

    test('off in debug, signed out, or sampled out: nothing is written', () async {
      expect(await ErrorLogService.logSampled('boom', null), isFalse, reason: 'disabled by default in tests');
      ErrorLogService.enabled = true;
      ErrorLogService.sampleRate = 1;
      uid = null;
      expect(await ErrorLogService.logSampled('boom', null), isFalse);
      uid = 'admin1';
      ErrorLogService.sampleRate = 0;
      expect(await ErrorLogService.logSampled('boom', null), isFalse);
      expect(await docs(), isEmpty);
    });

    test('the sample rate decides with the given random number', () async {
      ErrorLogService.enabled = true;
      ErrorLogService.sampleRate = 0.25;
      final base = DateTime(2026, 10, 7, 10);
      expect(await ErrorLogService.logSampled('first', null, random: _Fixed(0.5), now: () => base), isFalse);
      expect(await ErrorLogService.logSampled('first', null, random: _Fixed(0.1), now: () => base), isTrue);
    });

    test('the same message once, 30 seconds apart, at most 10 a run', () async {
      ErrorLogService.enabled = true;
      ErrorLogService.sampleRate = 1;
      var now = DateTime(2026, 10, 7, 10);
      expect(await ErrorLogService.logSampled('same', null, now: () => now), isTrue);
      now = now.add(const Duration(minutes: 1));
      expect(await ErrorLogService.logSampled('same', null, now: () => now), isFalse, reason: 'already logged this run');
      expect(await ErrorLogService.logSampled('other', null, now: () => now), isTrue);
      expect(await ErrorLogService.logSampled('third', null, now: () => now.add(const Duration(seconds: 5))), isFalse, reason: 'too soon');
      for (var i = 0; i < 20; i++) {
        now = now.add(const Duration(minutes: 1));
        await ErrorLogService.logSampled('e$i', null, now: () => now);
      }
      expect((await docs()).length, ErrorLogService.maxPerSession);
    });

    test('CrashService.record also samples the error', () async {
      ErrorLogService.enabled = true;
      ErrorLogService.sampleRate = 1;
      CrashService.record(Exception('crash here'), StackTrace.fromString('#0 f (package:transport_app/driver/x.dart:1:1)'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final d = (await docs()).single;
      expect(d['message'], 'Exception: crash here');
      expect(d['kind'], 'async');
      expect(d['screen'], 'driver/x.dart');
    });

    test('the health screen list reads the newest first', () async {
      await db.collection('app_errors').add({'message': 'old', 'screen': 's', 'kind': 'flutter', 'appVersion': '1', 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1))});
      await db.collection('app_errors').add({'message': 'new', 'screen': 's', 'kind': 'flutter', 'appVersion': '1', 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 5))});
      expect((await ErrorLogService.watchRecent().first).map((e) => e.message), ['new', 'old']);
    });
  });

  group('AdminHealthScreen', () {
    testWidgets('counts and recent errors', (t) async {
      tall(t);
      await db.collection('users').doc('u1').set({'name': 'A'});
      await db.collection('tickets').add({'status': 'open'});
      await db.collection('app_errors').add({'message': 'Null check failed', 'screen': 'driver/x.dart', 'kind': 'flutter', 'appVersion': '1.0.0+1', 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 5))});
      await t.pumpWidget(host(const AdminHealthScreen()));
      await settle(t);
      expect(t.widget<Text>(find.byKey(const ValueKey('health_users'))).data, '1');
      expect(t.widget<Text>(find.byKey(const ValueKey('health_tickets'))).data, '1');
      expect(find.text('Null check failed'), findsOneWidget);
      expect(find.textContaining('driver/x.dart'), findsOneWidget);
      expect(find.text('A sample only. No personal data is stored.'), findsOneWidget);
    });

    testWidgets('no errors: an empty state', (t) async {
      tall(t);
      await t.pumpWidget(host(const AdminHealthScreen()));
      await settle(t);
      expect(find.text('No errors logged'), findsOneWidget);
    });
  });

  group('AdminTemplatesScreen', () {
    testWidgets('lists, adds, edits and deletes templates', (t) async {
      tall(t);
      await t.pumpWidget(host(const AdminTemplatesScreen()));
      await settle(t);
      expect(find.text('Looking into it'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('tplAdd')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('tplTitle')), 'Refund info');
      await t.enterText(find.byKey(const ValueKey('tplText')), 'Refunds take 3 days.');
      await t.tap(find.byKey(const ValueKey('tplSave')));
      await settle(t);
      expect(find.text('Refund info'), findsOneWidget);
      final saved = ReplyTemplate.parse((await t.runAsync(() => db.collection('config').doc('reply_templates').get()))!.data());
      expect(saved.length, 5);
      final id = saved.last.id;
      await t.tap(find.byKey(ValueKey('tplEdit_$id')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('tplTitle')), 'Refund time');
      await t.tap(find.byKey(const ValueKey('tplSave')));
      await settle(t);
      expect(find.text('Refund time'), findsOneWidget);
      await t.tap(find.byKey(ValueKey('tplDelete_$id')));
      await settle(t);
      expect(find.text('Refund time'), findsNothing);
    });

    testWidgets('an empty title is refused with a message', (t) async {
      tall(t);
      await t.pumpWidget(host(const AdminTemplatesScreen()));
      await settle(t);
      await t.tap(find.byKey(const ValueKey('tplAdd')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('tplText')), 'text only');
      await t.tap(find.byKey(const ValueKey('tplSave')));
      await settle(t);
      expect(find.textContaining('Title and text are needed'), findsOneWidget);
    });
  });

  group('ticket reply template picker', () {
    Future<void> seedTicket() => db.collection('tickets').doc('t1').set({
          'userId': 'c1', 'category': 'payment', 'priority': 'normal', 'status': 'open', 'subject': 'Payment problem', 'description': 'help', 'escalationLevel': 0,
          'createdAt': Timestamp.now(), 'updatedAt': Timestamp.now(),
        });

    testWidgets('support picks a template into the reply box; a second pick is appended', (t) async {
      tall(t);
      await seedTicket();
      await t.pumpWidget(host(const TicketDetailScreen(ticketId: 't1', asAdmin: true)));
      await settle(t);
      await t.tap(find.byKey(const ValueKey('replyTemplates')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('pickTpl_fixed')));
      await t.pumpAndSettle();
      final field = find.byKey(const ValueKey('replyInput'));
      expect(t.widget<TextField>(field).controller!.text, ReplyTemplate.defaults.firstWhere((x) => x.id == 'fixed').text);
      await t.tap(find.byKey(const ValueKey('replyTemplates')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('pickTpl_closing')));
      await t.pumpAndSettle();
      final text = t.widget<TextField>(field).controller!.text;
      expect(text, contains('\n'));
      expect(text, endsWith(ReplyTemplate.defaults.firstWhere((x) => x.id == 'closing').text));
    });

    testWidgets('a customer does not get the picker', (t) async {
      tall(t);
      await seedTicket();
      uid = 'c1';
      await t.pumpWidget(host(const TicketDetailScreen(ticketId: 't1')));
      await settle(t);
      expect(find.byKey(const ValueKey('replyTemplates')), findsNothing);
      expect(find.byKey(const ValueKey('replyInput')), findsOneWidget);
    });

    testWidgets('saved templates replace the defaults in the picker', (t) async {
      tall(t);
      await seedTicket();
      await db.collection('config').doc('reply_templates').set({'items': [{'id': 'x', 'title': 'Only one', 'text': 'Just this'}]});
      await t.pumpWidget(host(const TicketDetailScreen(ticketId: 't1', asAdmin: true)));
      await settle(t);
      await t.tap(find.byKey(const ValueKey('replyTemplates')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('pickTpl_x')), findsOneWidget);
      expect(find.byKey(const ValueKey('pickTpl_fixed')), findsNothing);
    });
  });

  group('users screen: export and bulk actions', () {
    Future<void> seedUsers() async {
      await db.collection('admins').doc('admin1').set({'createdBy': 'console'});
      await db.collection('users').doc('u1').set({'name': 'Asha', 'phone': '+919111111111', 'riskTier': 'normal', 'role': 'driver'});
      await db.collection('users').doc('u2').set({'name': 'Bala', 'phone': '+919222222222', 'riskTier': 'restricted', 'role': 'customer'});
      await db.collection('users').doc('u3').set({'name': 'Chitra', 'phone': '+919333333333', 'riskTier': 'normal', 'role': 'customer'});
    }

    Future<void> open(WidgetTester t, {Future<bool> Function(String, String)? share}) async {
      tall(t);
      await t.pumpWidget(host(AdminUsersScreen(share: share)));
      await settle(t);
    }

    Future<String> tier(WidgetTester t, String id) async => (await t.runAsync(() => db.collection('users').doc(id).get()))!['riskTier'] as String;

    testWidgets('export shares a masked CSV', (t) async {
      await t.runAsync(seedUsers);
      String? csv, subject;
      await open(t, share: (c, s) async {
        csv = c;
        subject = s;
        return true;
      });
      await t.tap(find.byKey(const ValueKey('exportUsers')));
      await settle(t);
      expect(csv, contains('u1,driver,Asha,**********11'));
      expect(csv!.contains('9111111111'), isFalse);
      expect(subject, 'Users');
    });

    testWidgets('a failed share shows a message', (t) async {
      await t.runAsync(seedUsers);
      await open(t, share: (c, s) async => false);
      await t.tap(find.byKey(const ValueKey('exportUsers')));
      await settle(t);
      expect(find.text('Could not open this'), findsOneWidget);
    });

    testWidgets('long press selects; tapping toggles; the title counts; clear ends it', (t) async {
      await t.runAsync(seedUsers);
      await open(t);
      await t.longPress(find.byKey(const ValueKey('user_u1')));
      await t.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('user_u3')));
      await t.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      expect(find.byKey(const ValueKey('exportUsers')), findsNothing);
      await t.tap(find.byKey(const ValueKey('user_u3')));
      await t.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('bulkClear')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('exportUsers')), findsOneWidget);
    });

    testWidgets('hold needs a reason, then restricts the selected users', (t) async {
      await t.runAsync(seedUsers);
      await open(t);
      await t.longPress(find.byKey(const ValueKey('user_u1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('user_u3')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('bulkHold')));
      await t.pumpAndSettle();
      expect(find.text('Hold 2 users?'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('bulkConfirm')));
      await settle(t);
      expect(find.text('Hold 2 users?'), findsNothing);
      expect(await tier(t, 'u1'), 'normal', reason: 'no reason, nothing changed');
      expect(find.text('Write a reason of at least 3 characters'), findsOneWidget);
      expect(find.text('2 selected'), findsOneWidget, reason: 'the selection stays so the admin can try again');
    });

    testWidgets('hold with a reason: changed, skipped and audited', (t) async {
      await t.runAsync(seedUsers);
      await open(t);
      await t.longPress(find.byKey(const ValueKey('user_u1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('user_u2')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('bulkHold')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('bulkReason')), 'burst of loads');
      await t.tap(find.byKey(const ValueKey('bulkConfirm')));
      await settle(t);
      expect(await tier(t, 'u1'), 'restricted');
      expect(find.text('Changed 1, skipped 1'), findsOneWidget, reason: 'u2 was already restricted');
      expect(find.byKey(const ValueKey('exportUsers')), findsOneWidget, reason: 'selection cleared');
      final audit = (await t.runAsync(() => db.collection('audit_events').get()))!.docs;
      expect(audit.length, 1);
      expect(audit.single['targetId'], 'u1');
    });

    testWidgets('release hold, and set status with the chips', (t) async {
      await t.runAsync(seedUsers);
      await open(t);
      await t.longPress(find.byKey(const ValueKey('user_u2')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('bulkUnhold')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('bulkConfirm')));
      await settle(t);
      expect(await tier(t, 'u2'), 'normal');
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      await t.longPress(find.byKey(const ValueKey('user_u3')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('bulkStatus')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('bulkTier_suspended')));
      await t.pump();
      await t.enterText(find.byKey(const ValueKey('bulkReason')), 'papers expired');
      await t.tap(find.byKey(const ValueKey('bulkConfirm')));
      await settle(t);
      expect(await tier(t, 'u3'), 'suspended');
    });

    testWidgets('a support admin can select but gets no bulk buttons', (t) async {
      await t.runAsync(seedUsers);
      await t.runAsync(() => db.collection('admins').doc('admin1').set({'role': 'support'}));
      await open(t);
      await t.longPress(find.byKey(const ValueKey('user_u1')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('bulkHold')), findsNothing);
      expect(staffCan('support', 'flaggedUsers'), isFalse);
    });
  });

  group('bookings screen export', () {
    testWidgets('exports the chosen status', (t) async {
      tall(t);
      await db.collection('bookings').doc('x1').set({'status': 'delivered', 'pickup': 'A', 'drop': 'B', 'createdAt': Timestamp.now(), 'driverPhone': '+919800000000'});
      await db.collection('bookings').doc('x2').set({'status': 'cancelled', 'pickup': 'C', 'drop': 'D', 'createdAt': Timestamp.now()});
      String? csv;
      await t.pumpWidget(host(AdminBookingsScreen(share: (c, s) async {
        csv = c;
        return true;
      })));
      await settle(t);
      await t.tap(find.byKey(const ValueKey('exportBookings')));
      await settle(t);
      expect(csv!.split('\n').length, 3);
      expect(csv!.contains('9800000000'), isFalse);
    });
  });

  test('staff areas: health for super and ops, templates for super only', () {
    expect(staffCan('super', 'adminHealth'), isTrue);
    expect(staffCan('ops', 'adminHealth'), isTrue);
    expect(staffCan('support', 'adminHealth'), isFalse);
    expect(staffCan('super', 'adminTemplates'), isTrue);
    expect(staffCan('support', 'adminTemplates'), isFalse);
  });

  test('every new string has 12 non-empty languages and the same placeholders', () {
    final ph = RegExp(r'\{(\w+)\}');
    for (final e in adminToolsStrings.entries) {
      expect(e.value.length, 12, reason: e.key);
      expect(e.value.every((s) => s.trim().isNotEmpty), isTrue, reason: e.key);
      final want = ph.allMatches(e.value[0]).map((m) => m[1]).toSet();
      for (var i = 1; i < 12; i++) {
        expect(ph.allMatches(e.value[i]).map((m) => m[1]).toSet(), want, reason: '${e.key}/$i');
      }
    }
  });
}

class _Fixed implements Random {
  final double v;
  _Fixed(this.v);
  @override
  double nextDouble() => v;
  @override
  bool nextBool() => v > 0.5;
  @override
  int nextInt(int max) => (v * max).floor();
}
