import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/features/features.dart';

void main() {
  String doc(String f) => File('docs/$f').readAsStringSync();

  test('the three pilot documents exist and are not stubs', () {
    for (final f in ['ADDON_PILOT.md', 'LAUNCH_RISKS.md', 'COST_WATCH.md']) {
      expect(doc(f).length, greaterThan(2000), reason: f);
    }
  });

  test('the pilot table matches the code defaults: OFF features are listed as OFF, ON as ON', () {
    final pilot = doc('ADDON_PILOT.md');
    final labels = {
      FeatureKey.driverNetwork: 'Driver network and groups',
      FeatureKey.emptyTrucks: 'Empty trucks board',
      FeatureKey.businessTools: 'Business tools',
      FeatureKey.rentalMovers: 'Hourly rental and packers and movers',
      FeatureKey.driverRewards: 'Driver tips, bonuses and plans',
      FeatureKey.tripShare: 'Trip share link',
      FeatureKey.problemReport: 'Report a problem',
      FeatureKey.transporter: 'Transporter accounts',
      FeatureKey.bilty: 'Bilty (LR)',
      FeatureKey.secureScreens: 'Block screenshots on private screens',
      FeatureKey.walletHub: 'Earnings and accounts hub',
      FeatureKey.walletMakerChecker: 'Two admins for payouts',
      FeatureKey.walletStepUp: 'Fresh code before payouts',
      FeatureKey.walletLimits: 'Payout limits and waiting time',
      FeatureKey.appLock: 'Fingerprint lock for earnings',
      FeatureKey.serverLimits: 'Server hourly limits',
      FeatureKey.serverChatScan: 'Server chat check',
      FeatureKey.serverCredits: 'Server credits and referral',
      FeatureKey.serverTrust: 'Server trip counts',
      FeatureKey.serverJobs: 'Server timed jobs',
      FeatureKey.serverAdminActions: 'Server admin actions',
      FeatureKey.serverDeletion: 'Server account deletion',
      FeatureKey.serverWallet: 'Server earnings checks',
      FeatureKey.paymentGateway: 'Online payment (test mode)',
      FeatureKey.pushNotifications: 'Push notifications',
      FeatureKey.adminBroadcast: 'Admin announcements by push',
      FeatureKey.photoUploads: 'Photo uploads',
      FeatureKey.dispatchV2: 'Nearby-first dispatch and bidding',
      FeatureKey.uiV2: 'New look and booking steps',
      FeatureKey.designV3: 'Signature look',
      FeatureKey.vehicleCatalog: 'Vehicle catalog',
      FeatureKey.vehiclePhotos: 'Vehicle photos and badge',
      FeatureKey.cargoPhotos: 'Goods and seal photos',
      FeatureKey.homeV3: 'Arrangeable home',
      FeatureKey.driverHomeV3: 'Arrangeable driver home',
      FeatureKey.fleetCommand: 'Transporter command center',
      FeatureKey.adminOpsHome: 'Admin ops home',
      FeatureKey.navV3: 'Search in bilty',
      FeatureKey.onboardingV3: 'First-run tour v3',
      FeatureKey.priceCard: 'Full price card',
      FeatureKey.roundTrip: 'Book the way back',
      FeatureKey.bulkUpload: 'Bulk loads from Excel',
      FeatureKey.laneRfq: 'Lane tenders',
      FeatureKey.quoteShare: 'Share a quote',
      FeatureKey.legalGateInsurance: 'Insurance quote requests (legal gate)',
      FeatureKey.tollEstimate: 'Expected tolls',
      FeatureKey.cityNotes: 'City notes',
      FeatureKey.bizCard: 'Business card to share',
      FeatureKey.khata: 'Party khata',
      FeatureKey.safetyCheckin: 'Safety check-in on a long stop',
      FeatureKey.payHold: 'Hold online payment until delivery',
      FeatureKey.rateRange: 'Usual price on a route',
      FeatureKey.tripTrustCard: 'Driver trust on offers and trips',
      FeatureKey.appCheckEnforce: 'Refuse calls from unknown apps',
      FeatureKey.kycVerify: 'ID checks (licence, RC, PAN, GST)',
      FeatureKey.smsGateway: 'SMS messages',
      FeatureKey.liveLocation: 'Live trip location',
      FeatureKey.maps: 'Maps and road distance',
    };
    expect(labels.keys.toSet(), Features.registry.map((s) => s.key).toSet(), reason: 'a new feature needs a row in ADDON_PILOT.md');
    for (final s in Features.registry) {
      final row = pilot.split('\n').firstWhere((l) => l.startsWith('| ${labels[s.key]}'), orElse: () => '');
      expect(row, isNotEmpty, reason: s.key);
      expect(row.contains('| ${s.pilotOn ? 'ON' : 'OFF'}'), isTrue, reason: '${s.key}: $row');
    }
  });

  test('cost watch names the real code that limits reads', () {
    final c = doc('COST_WATCH.md');
    for (final name in ['refreshAppConfig', 'supplyDemand', 'unitEconomics', 'PagedLiveStream', 'ErrorLogService']) {
      expect(c, contains(name));
    }
    for (final f in ['lib/core/services/admin_console_service.dart', 'lib/core/services/app_config.dart']) {
      expect(File(f).existsSync(), isTrue);
    }
    expect(File('lib/core/services/admin_console_service.dart').readAsStringSync(), contains('static Future<SupplyDemand> supplyDemand'));
  });

  test('every risk row has likelihood, impact, a fix and an owner', () {
    final rows = doc('LAUNCH_RISKS.md').split('\n').where((l) => RegExp(r'^\| \d+ \|').hasMatch(l)).toList();
    expect(rows.length, greaterThanOrEqualTo(12));
    for (final r in rows) {
      final cells = r.split('|').map((c) => c.trim()).toList();
      expect(cells.length, 8, reason: r);
      expect(['L', 'M', 'H'], contains(cells[3]), reason: r);
      expect(['L', 'M', 'H'], contains(cells[4]), reason: r);
      expect(cells[5].length, greaterThan(15), reason: r);
      expect(['Owner', 'Admin'], contains(cells[6]), reason: r);
    }
  });
}
