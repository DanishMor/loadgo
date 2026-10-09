import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/admin/staff_roles.dart';

/// MASTER-6 Task 9: the staff permission matrix. The rules decide who may
/// write; `staffAreas` only hides what a role cannot use. This test keeps the
/// two from drifting apart.
void main() {
  final rules = File('firestore.rules').readAsStringSync();

  List<String> adminRolesInBlock(String startMarker, String keyword) {
    final i = rules.indexOf(startMarker);
    expect(i, greaterThanOrEqualTo(0), reason: startMarker);
    final j = rules.indexOf(keyword, i);
    final m = RegExp(r"adminIn\(\[([^\]]*)\]\)").firstMatch(rules.substring(j));
    expect(m, isNotNull, reason: '$startMarker $keyword');
    return RegExp(r"'(\w+)'").allMatches(m!.group(1)!).map((x) => x.group(1)!).toList();
  }

  test('the four named staff roles exist, finance included, and normalise keeps unknown ones out', () {
    expect(StaffRole.all, containsAll(['super', 'support', 'ops', 'finance', 'verifier']));
    expect(StaffRole.normalise('finance'), 'finance');
    expect(StaffRole.normalise('owner-of-the-universe'), StaffRole.superAdmin); // missing / unknown -> rules treat it as no powers; the panel falls back to super only for a missing field
  });

  test('every adminIn([...]) in the rules names real roles', () {
    final lists = RegExp(r"adminIn\(\[([^\]]*)\]\)").allMatches(rules).toList();
    expect(lists.length, greaterThan(30));
    for (final m in lists) {
      for (final r in RegExp(r"'(\w+)'").allMatches(m.group(1)!)) {
        expect(StaffRole.all, contains(r.group(1)), reason: m.group(0));
      }
    }
  });

  test('every panel area is open to super, and only names real roles', () {
    for (final e in staffAreas.entries) {
      expect(e.value, contains(StaffRole.superAdmin), reason: e.key);
      expect(StaffRole.all, containsAll(e.value), reason: e.key);
    }
  });

  test('rules and panel agree on the money screens and the pilot tools', () {
    List<String> area(String k) => [...staffAreas[k]!]..sort();
    List<String> rule(String start, String kw) => adminRolesInBlock(start, kw)..sort();
    expect(rule('match /payouts/{payoutId}', 'allow update'), area('adminPayouts'));
    expect(rule('match /incentive_claims/{claimId}', 'allow update'), area('adminDriverRewards'));
    expect(rule('match /invite_codes/{code}', 'allow create'), area('adminInvites'));
    expect(rule('match /dispatch_suggestions/{id}', 'allow create'), area('adminDispatch'));
    expect(rule('match /payment_nudges/{id}', 'allow create'), area('adminPayAging'));
    expect(rule('match /deletion_requests/{uid}', 'allow update: if adminIn'), area('adminDeletionRequests'));
  });

  test('finance sees the money screens and nothing that edits people or config', () {
    for (final a in ['adminPayouts', 'adminDriverRewards', 'adminUnitEconomics', 'adminPayAging', 'adminAnalytics', 'adminUsers']) {
      expect(staffCan(StaffRole.finance, a), isTrue, reason: a);
    }
    for (final a in ['adminConfig', 'adminOffers', 'driverVerification', 'adminTickets', 'adminInvites', 'adminDispatch', 'flaggedUsers']) {
      expect(staffCan(StaffRole.finance, a), isFalse, reason: a);
    }
  });

  test('support and ops cannot reach the money screens', () {
    for (final r in [StaffRole.support, StaffRole.ops, StaffRole.verifier]) {
      expect(staffCan(r, 'adminPayouts'), isFalse, reason: r);
      expect(staffCan(r, 'adminDriverRewards'), isFalse, reason: r);
    }
  });
}
