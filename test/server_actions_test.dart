import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_broadcast_screen.dart';
import 'package:transport_app/core/admin/staff_roles.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/payout.dart';
import 'package:transport_app/core/services/admin_service.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/services/finance_service.dart';
import 'package:transport_app/core/services/risk_service.dart';
import 'package:transport_app/core/services/server_actions.dart';
import 'package:transport_app/core/theme/app_theme.dart';

class FakeGateway implements ServerGateway {
  final calls = <(String, Map<String, Object?>)>[];
  Object? error;
  Map<String, dynamic> answer = {'ok': true};

  @override
  Future<Map<String, dynamic>> call(String name, Map<String, Object?> data) async {
    calls.add((name, data));
    if (error != null) throw error!;
    return answer;
  }
}

/// F21, F23, F27: the app side of the server actions. With the switch off or
/// the function missing the old direct write happens; a real refusal is shown.
void main() {
  late FakeFirebaseFirestore db;
  late FakeGateway gw;

  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'admin1');
    gw = FakeGateway();
    ServerActions.gateway = gw;
    FeaturesService.reset();
  });

  tearDown(() => ServerActions.gateway = const CloudServerGateway());

  void on(String key) => FeaturesService.notifier.value = Features(flags: {key: true});

  group('risk tier', () {
    test('switch off: written directly, with the audit line, and the server is not asked', () async {
      await db.collection('users').doc('d1').set({'name': 'x'});
      await RiskService.setTier('d1', 'review', reason: ' fraud ');
      expect(gw.calls, isEmpty);
      expect((await db.collection('users').doc('d1').get()).data()!['riskTier'], 'review');
      expect((await db.collection('audit_events').get()).docs.single.data()['type'], 'risk_change');
    });

    test('switch on and the server answers: only the server call, no direct write', () async {
      on(FeatureKey.serverAdminActions);
      await db.collection('users').doc('d1').set({'name': 'x'});
      await RiskService.setTier('d1', 'suspended', reason: 'no show');
      expect(gw.calls.single.$1, 'adminSetRiskTier');
      expect(gw.calls.single.$2, {'uid': 'd1', 'tier': 'suspended', 'reason': 'no show'});
      expect((await db.collection('users').doc('d1').get()).data()!['riskTier'], isNull);
      expect((await db.collection('audit_events').get()).docs, isEmpty);
    });

    test('switch on but the function is not deployed: the old direct write happens', () async {
      on(FeatureKey.serverAdminActions);
      gw.error = FirebaseFunctionsException(code: 'not-found', message: 'no such function');
      await db.collection('users').doc('d1').set({'name': 'x'});
      await RiskService.setTier('d1', 'review');
      expect((await db.collection('users').doc('d1').get()).data()!['riskTier'], 'review');
    });

    test('a function that is switched off on the server (failed-precondition) also falls back; offline too', () async {
      on(FeatureKey.serverAdminActions);
      await db.collection('users').doc('d1').set({'name': 'x'});
      gw.error = FirebaseFunctionsException(code: 'failed-precondition', message: 'disabled');
      await RiskService.setTier('d1', 'review');
      gw.error = StateError('offline');
      await RiskService.setTier('d1', 'restricted');
      expect((await db.collection('users').doc('d1').get()).data()!['riskTier'], 'restricted');
    });

    test('a real refusal is shown and nothing is written behind it', () async {
      on(FeatureKey.serverAdminActions);
      gw.error = FirebaseFunctionsException(code: 'permission-denied', message: 'role support may not do this');
      await db.collection('users').doc('d1').set({'name': 'x'});
      await expectLater(RiskService.setTier('d1', 'banned'), throwsA(isA<ServerRefused>().having((e) => e.code, 'code', 'permission-denied')));
      expect((await db.collection('users').doc('d1').get()).data()!['riskTier'], isNull);
    });
  });

  group('driver approval', () {
    test('switch on: the server is asked with the reason and the note; switch off: direct write', () async {
      await db.collection('users').doc('d1').set({'name': 'x'});
      await AdminService.setStatus('d1', 'rejected', reason: 'docs_unclear', note: ' blurry ');
      expect((await db.collection('users').doc('d1').get()).data()!['verificationStatus'], 'rejected');
      expect(gw.calls, isEmpty);
      on(FeatureKey.serverAdminActions);
      await AdminService.setStatus('d1', 'approved');
      expect(gw.calls.single.$1, 'adminDecideDriver');
      expect(gw.calls.single.$2, {'uid': 'd1', 'status': 'approved'});
      await AdminService.setStatus('d1', 'rejected', reason: 'other', note: 'x ');
      expect(gw.calls.last.$2, {'uid': 'd1', 'status': 'rejected', 'reason': 'other', 'note': 'x'});
    });
  });

  group('payout decisions', () {
    Payout p({String status = 'requested', String? approvedBy}) => Payout(id: 'p1', driverId: 'd1', amountPaise: 5000, status: status, approvedBy: approvedBy);

    test('switch off: the same direct batches as before', () async {
      await db.collection('payouts').doc('p1').set({'driverId': 'd1', 'amountPaise': 5000, 'status': 'requested'});
      await FinanceService.approve(p());
      expect((await db.collection('payouts').doc('p1').get()).data()!['status'], 'approved');
      expect(gw.calls, isEmpty);
    });

    test('switch on: each action goes to the server with its words; checks that need no server still happen first', () async {
      on(FeatureKey.serverWallet);
      await FinanceService.approve(p());
      await FinanceService.pay(p(status: 'approved', approvedBy: 'other'), ' UTR1234 ');
      await FinanceService.reject(p(), ' no match ');
      await FinanceService.reverse(p(status: 'paid'), 'bounced back');
      expect(gw.calls.map((c) => c.$1).toSet(), {'adminPayoutDecision'});
      expect(gw.calls.map((c) => c.$2), [
        {'payoutId': 'p1', 'action': 'approve'},
        {'payoutId': 'p1', 'action': 'pay', 'reference': 'UTR1234'},
        {'payoutId': 'p1', 'action': 'reject', 'reason': 'no match'},
        {'payoutId': 'p1', 'action': 'reverse', 'reason': 'bounced back'},
      ]);
      await expectLater(FinanceService.pay(p(status: 'approved', approvedBy: 'admin1'), 'UTR1234'), throwsA(isA<FinanceException>()), reason: 'the approver cannot pay, with or without the server');
      await expectLater(FinanceService.reject(p(), 'no'), throwsA(isA<FinanceException>()));
      expect(gw.calls.length, 4, reason: 'refused before any call');
      expect((await db.collection('audit_events').get()).docs, isEmpty);
    });
  });

  group('announcement push', () {
    test('the gateway answer is the number of people; the server missing is null', () async {
      expect(await ServerActions.broadcast(title: 'Hi', body: 'There'), isNull, reason: 'switch off');
      on(FeatureKey.adminBroadcast);
      gw.answer = {'people': 42, 'sent': 30};
      expect(await ServerActions.broadcast(title: 'Diwali', body: 'Free pickup', role: 'driver'), 42);
      expect(gw.calls.single.$2, {'title': 'Diwali', 'body': 'Free pickup', 'role': 'driver'});
      gw.error = FirebaseFunctionsException(code: 'unavailable', message: 'x');
      expect(await ServerActions.broadcast(title: 'Diwali', body: 'Free pickup'), isNull);
    });

    Widget host(Widget w, {double scale = 1.0, Brightness b = Brightness.light}) => LanguageScope(
          notifier: ValueNotifier(AppLanguage.english),
          child: MaterialApp(
            theme: AppTheme.build(b),
            builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true), child: child!),
            home: w,
          ),
        );

    testWidgets('the screen sends the title, the message and the audience, and tells how many', (t) async {
      final sent = <Map<String, Object?>>[];
      await t.pumpWidget(host(AdminBroadcastScreen(send: ({required title, required body, role}) async {
        sent.add({'title': title, 'body': body, 'role': role});
        return 12;
      })));
      await t.tap(find.byKey(const ValueKey('bcSend')));
      await t.pump();
      expect(find.text(T.get('bcTooShort', AppLanguage.english)), findsOneWidget);
      expect(sent, isEmpty);
      await t.pump(const Duration(seconds: 5));
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('bcTitle')), ' Diwali offer ');
      await t.enterText(find.byKey(const ValueKey('bcBody')), 'Free pickup this week');
      await t.tap(find.byKey(const ValueKey('bcRole_driver')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('bcSend')));
      await t.pump();
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(sent, [{'title': 'Diwali offer', 'body': 'Free pickup this week', 'role': 'driver'}]);
      expect(find.textContaining('12'), findsWidgets);
    });

    testWidgets('no server: a calm message; the screen fits 360x640 at 2.0x text in dark mode', (t) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(host(AdminBroadcastScreen(send: ({required title, required body, role}) async => null), scale: 2.0, b: Brightness.dark));
      await t.enterText(find.byKey(const ValueKey('bcTitle')), 'Hello');
      await t.enterText(find.byKey(const ValueKey('bcBody')), 'World wide');
      await t.scrollUntilVisible(find.byKey(const ValueKey('bcSend')), 200, scrollable: find.byType(Scrollable).first);
      await t.tap(find.byKey(const ValueKey('bcSend')));
      await t.pump();
      await t.pump();
      expect(find.text(T.get('bcNoServer', AppLanguage.english)), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  test('the broadcast area is for super, support and ops only', () {
    for (final r in ['super', 'support', 'ops']) {
      expect(staffCan(r, 'adminBroadcast'), isTrue, reason: r);
    }
    for (final r in ['finance', 'verifier']) {
      expect(staffCan(r, 'adminBroadcast'), isFalse, reason: r);
    }
  });
}
