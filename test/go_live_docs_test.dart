import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/features/features.dart';

/// G43 to G45: the go-live runbook, the check script and the phone sheet exist and agree with the code.
void main() {
  final runbook = File('docs/GO_LIVE_RUNBOOK.md').readAsStringSync();
  final script = File('tool/golive_check.ps1').readAsStringSync();
  final sheet = File('docs/PHONE_TEST_SHEET.md').readAsStringSync();

  test('the runbook has the eight steps in the planned order', () {
    final heads = RegExp(r'^## (\d)\.', multiLine: true).allMatches(runbook).map((m) => m.group(1)).toList();
    expect(heads, ['1', '2', '3', '4', '5', '6', '7', '8']);
    for (final w in ['Blaze', 'budget', 'Console', '409', 'Publish', 'secrets:set', 'Check server', '24 ghante', 'Test numbers', 'asli admin']) {
      expect(runbook.toLowerCase(), contains(w.toLowerCase()), reason: w);
    }
  });

  test('the first six switches are turned on in the planned order: push, photos, maps, live location, payments, SMS', () {
    final names = ['pushNotifications', 'photoUploads', 'maps', 'liveLocation', 'paymentGateway', 'smsGateway'];
    final at = [for (final s in names) runbook.indexOf('`$s`')];
    expect(at.every((x) => x > 0), isTrue);
    for (var k = 1; k < at.length; k++) {
      expect(at[k], greaterThan(at[k - 1]), reason: '${names[k]} comes after ${names[k - 1]}');
    }
  });

  test('every switch the runbook and the sheet name for turning on exists in the code', () {
    final known = Features.registry.map((s) => s.key).toSet();
    const named = [
      'pushNotifications', 'photoUploads', 'maps', 'liveLocation', 'paymentGateway', 'smsGateway', 'payHold', 'kycVerify', 'safetyCheckin',
      'khata', 'bizCard', 'appCheckEnforce', 'tripTrustCard', 'rateRange', 'appLock', 'serverLimits', 'serverChatScan', 'serverTrust',
      'serverCredits', 'serverJobs', 'serverAdminActions', 'serverDeletion', 'serverWallet', 'adminBroadcast',
    ];
    for (final s in named) {
      expect(known, contains(s), reason: s);
      expect(runbook + sheet, contains(s), reason: '$s is not in the runbook or the sheet');
    }
  });

  test('the check script only reads: no deploy, no secret value, no write to the project', () {
    expect(script, isNot(contains('firebase deploy')));
    expect(script, isNot(contains('secrets:access')));
    expect(RegExp(r'Set-Content|Out-File|Add-Content|Remove-Item').hasMatch(script), isFalse);
    expect(script.toLowerCase(), contains('read-only'));
  });

  test('the phone sheet has a Pass / Fail column and one row for every Part 3 switch', () {
    expect(sheet, contains('Pass / Fail'));
    for (final s in ['maps', 'liveLocation', 'paymentGateway', 'payHold', 'smsGateway', 'safetyCheckin', 'tripTrustCard', 'rateRange', 'khata', 'bizCard', 'appLock', 'kycVerify', 'pushNotifications', 'photoUploads']) {
      expect(sheet, contains('`$s`'), reason: s);
    }
  });

  test('no real key or token is written in the new go-live documents', () {
    for (final t in [runbook, sheet, script]) {
      expect(RegExp(r'AIza[0-9A-Za-z_-]{30,}|rzp_(live|test)_[A-Za-z0-9]{8,}|-----BEGIN [A-Z ]*PRIVATE KEY').hasMatch(t), isFalse);
    }
  });
}
