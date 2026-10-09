import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/admin/staff_roles.dart';
import 'package:transport_app/core/features/features.dart';

void main() {
  final doc = File('docs/WHERE_IS_WHAT.md').readAsStringSync();

  test('every feature flag is listed with the default the code has', () {
    for (final s in Features.registry) {
      final row = doc.split('\n').firstWhere((l) => l.startsWith('| `${s.key}`'), orElse: () => '');
      expect(row, isNotEmpty, reason: '${s.key} is missing in docs/WHERE_IS_WHAT.md');
      final cells = row.split('|').map((c) => c.trim()).toList(); // ['', flag, meaning, pilot, normal, where, '']
      expect(cells[3], s.pilotOn ? 'ON' : 'OFF', reason: '${s.key} pilot default');
      expect(cells[4], s.normalOn ? 'ON' : 'OFF', reason: '${s.key} normal default');
    }
  });

  test('every role has its section', () {
    for (final h in ['## Customer', '## Driver', '## Transporter', '## Admin', '## Feature flags']) {
      expect(doc, contains(h));
    }
  });

  test('every Admin Panel area is named in the admin table', () {
    const names = {
      'adminAnalytics': 'Analytics',
      'adminUsers': 'Users',
      'driverVerification': 'Driver verification',
      'adminVehicles': 'Vehicles',
      'adminLoads': 'Loads',
      'adminBookings': 'Bookings',
      'adminTickets': 'Tickets',
      'adminSos': 'SOS',
      'adminReports': 'Reports',
      'pcAdminViolations': 'Chat violations',
      'adminSignals': 'Signals',
      'adminFraudCases': 'Fraud cases',
      'adminDisputes': 'Disputes',
      'adminRatingFlags': 'Rating flags',
      'adminRatingBurst': 'Rating bursts',
      'adminAssistant': 'Sahayak',
      'adminFeedback': 'Feedback',
      'adminHealth': 'Health',
      'adminTemplates': 'Templates',
      'adminDemo': 'Demo data',
      'adminFeatures': 'Features',
      'adminUnitEconomics': 'Unit economics',
      'adminSupplyDemand': 'Supply and demand',
      'adminPilotFunnel': 'Pilot funnel',
      'adminInvites': 'Invite codes',
      'adminWaitlist': 'Waitlist',
      'adminPilotControl': 'Pilot control room',
      'flaggedUsers': 'Flagged users',
      'adminDeletionRequests': 'Deletion requests',
      'adminAudit': 'Audit log',
      'adminDriverRewards': 'Driver rewards',
      'adminPayouts': 'Payouts',
      'adminOffers': 'Offers',
      'adminConfig': 'Config',
    };
    expect(names.keys.toSet(), staffAreas.keys.toSet(), reason: 'a new admin area needs a row in docs/WHERE_IS_WHAT.md and here');
    final admin = doc.substring(doc.indexOf('## Admin'));
    for (final e in names.entries) {
      expect(admin, contains(e.value), reason: e.key);
    }
  });
}
