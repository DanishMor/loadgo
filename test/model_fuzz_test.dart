import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/analytics/unit_economics.dart';
import 'package:transport_app/core/assistant/assistant_log_service.dart';
import 'package:transport_app/core/bilty/inspection_service.dart';
import 'package:transport_app/core/bilty/lr_model.dart';
import 'package:transport_app/core/bilty/lr_service.dart';
import 'package:transport_app/core/call/call_models.dart';
import 'package:transport_app/core/models/app_notification.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/business.dart';
import 'package:transport_app/core/models/business_ops.dart';
import 'package:transport_app/core/models/chat_message.dart';
import 'package:transport_app/core/models/claim.dart';
import 'package:transport_app/core/models/driver_extras.dart';
import 'package:transport_app/core/models/driver_network.dart';
import 'package:transport_app/core/models/enterprise.dart';
import 'package:transport_app/core/models/fleet.dart';
import 'package:transport_app/core/models/fraud_case.dart';
import 'package:transport_app/core/models/handover.dart';
import 'package:transport_app/core/models/invoice.dart';
import 'package:transport_app/core/models/ledger_entry.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/offer.dart';
import 'package:transport_app/core/models/payout.dart';
import 'package:transport_app/core/models/rating.dart';
import 'package:transport_app/core/models/recurring.dart';
import 'package:transport_app/core/models/repeat.dart';
import 'package:transport_app/core/models/saved_place.dart';
import 'package:transport_app/core/models/saved_search.dart';
import 'package:transport_app/core/models/support_ticket.dart';
import 'package:transport_app/core/models/trip_evidence.dart';
import 'package:transport_app/core/models/truck_board.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/models/vehicle_expense.dart';
import 'package:transport_app/core/offers/promo.dart';
import 'package:transport_app/core/services/error_log_service.dart';
import 'package:transport_app/core/services/feedback_service.dart';
import 'package:transport_app/core/transporter/transporter_logic.dart';

/// MASTER-5 Phase B, Round 1: a document from before a field existed (missing
/// keys) or with fields set to null must never crash a screen. Every model
/// reader below is given an empty document and one with every key it reads
/// set to null.
void main() {
  // The keys a model file reads: d['x'], m['x'], u['x'].
  Set<String> keysIn(String file) =>
      {for (final m in RegExp(r"\b(?:d|m|u|data|raw)\['(\w+)'\]").allMatches(File(file).readAsStringSync())) m.group(1)!};

  final fromDoc = <String, (String, Object? Function(dynamic doc))>{
    'Booking': ('lib/core/models/booking.dart', (d) => Booking.fromDoc(d)),
    'Load': ('lib/core/models/load.dart', (d) => Load.fromDoc(d)),
    'Vehicle': ('lib/core/models/vehicle.dart', (d) => Vehicle.fromDoc(d)),
    'Offer': ('lib/core/models/offer.dart', (d) => Offer.fromDoc(d)),
    'AppNotification': ('lib/core/models/app_notification.dart', (d) => AppNotification.fromDoc(d)),
    'Rating': ('lib/core/models/rating.dart', (d) => Rating.fromDoc(d)),
    'LedgerEntry': ('lib/core/models/ledger_entry.dart', (d) => LedgerEntry.fromDoc(d)),
    'SupportTicket': ('lib/core/models/support_ticket.dart', (d) => SupportTicket.fromDoc(d)),
    'TicketReply': ('lib/core/models/support_ticket.dart', (d) => TicketReply.fromDoc(d)),
    'ChatMessage': ('lib/core/models/chat_message.dart', (d) => ChatMessage.fromDoc(d)),
    'Handover': ('lib/core/models/handover.dart', (d) => Handover.fromDoc(d)),
    'DriverLink': ('lib/core/models/driver_network.dart', (d) => DriverLink.fromDoc(d)),
    'DriverGroup': ('lib/core/models/driver_network.dart', (d) => DriverGroup.fromDoc(d)),
    'NetworkMessage': ('lib/core/models/driver_network.dart', (d) => NetworkMessage.fromDoc(d)),
    'Branch': ('lib/core/models/enterprise.dart', (d) => Branch.fromDoc(d)),
    'Shipment': ('lib/core/models/enterprise.dart', (d) => Shipment.fromDoc(d)),
    'SavedPlace': ('lib/core/models/saved_place.dart', (d) => SavedPlace.fromDoc(d)),
  };

  final fromIdMap = <String, (String, Object? Function(String id, Map<String, dynamic> d))>{
    'UnknownQuestion': ('lib/core/assistant/assistant_log_service.dart', (i, d) => UnknownQuestion.fromDoc(i, d)),
    'LrPublic': ('lib/core/bilty/lr_model.dart', (i, d) => LrPublic.fromDoc(i, d)),
    'LrDetails': ('lib/core/bilty/lr_model.dart', (i, d) => LrDetails.fromMap(d)),
    'LrCompliance': ('lib/core/bilty/lr_model.dart', (i, d) => LrCompliance.fromMap(d)),
    'LrShare': ('lib/core/bilty/lr_service.dart', (i, d) => LrShare.fromDoc(i, d)),
    'InspectionGrant': ('lib/core/bilty/inspection_service.dart', (i, d) => InspectionGrant.fromDoc(i, d)),
    'InspectionRequest': ('lib/core/bilty/inspection_service.dart', (i, d) => InspectionRequest.fromDoc(i, d)),
    'VehicleExpense': ('lib/core/models/vehicle_expense.dart', (i, d) => VehicleExpense.fromDoc(i, d)),
    'Payout': ('lib/core/models/payout.dart', (i, d) => Payout.fromDoc(i, d)),
    'LoadTemplate': ('lib/core/models/repeat.dart', (i, d) => LoadTemplate.fromDoc(i, d)),
    'FavouriteDriver': ('lib/core/models/repeat.dart', (i, d) => FavouriteDriver.fromDoc(i, d)),
    'TruckPost': ('lib/core/models/truck_board.dart', (i, d) => TruckPost.fromDoc(i, d)),
    'TruckRequest': ('lib/core/models/truck_board.dart', (i, d) => TruckRequest.fromDoc(i, d)),
    'BizExpense': ('lib/core/models/business_ops.dart', (i, d) => BizExpense.fromDoc(i, d)),
    'ContractVehicle': ('lib/core/models/business_ops.dart', (i, d) => ContractVehicle.fromDoc(i, d)),
    'PoolDriver': ('lib/core/models/business_ops.dart', (i, d) => PoolDriver.fromDoc(d)),
    'Booking.fromMap': ('lib/core/models/booking.dart', (i, d) => Booking.fromMap(i, d)),
    'CargoDoc': ('lib/core/models/trip_evidence.dart', (i, d) => CargoDoc.fromDoc(i, d)),
    'FraudCase': ('lib/core/models/fraud_case.dart', (i, d) => FraudCase.fromDoc(i, d)),
    'CaseNote': ('lib/core/models/fraud_case.dart', (i, d) => CaseNote.fromDoc(i, d)),
    'FeedbackEntry': ('lib/core/services/feedback_service.dart', (i, d) => FeedbackEntry.fromDoc(i, d)),
    'AppError': ('lib/core/services/error_log_service.dart', (i, d) => AppError.fromDoc(i, d)),
    'Claim': ('lib/core/models/claim.dart', (i, d) => Claim.fromDoc(i, d)),
    'ClaimEvent': ('lib/core/models/claim.dart', (i, d) => ClaimEvent.fromDoc(i, d)),
    'TripInvoice': ('lib/core/models/invoice.dart', (i, d) => TripInvoice.fromDoc(i, d)),
    'Promo': ('lib/core/offers/promo.dart', (i, d) => Promo.fromMap(i, d)),
    'CreditLine': ('lib/core/offers/promo.dart', (i, d) => CreditLine.fromDoc(i, d)),
    'BusinessInvite': ('lib/core/models/business.dart', (i, d) => BusinessInvite.fromDoc(i, d)),
    'BusinessMember': ('lib/core/models/business.dart', (i, d) => BusinessMember.fromDoc(i, d)),
    'Tip': ('lib/core/models/driver_extras.dart', (i, d) => Tip.fromDoc(i, d)),
    'Incentive': ('lib/core/models/driver_extras.dart', (i, d) => Incentive.fromDoc(i, d)),
    'IncentiveClaim': ('lib/core/models/driver_extras.dart', (i, d) => IncentiveClaim.fromDoc(i, d)),
    'RatingFlag': ('lib/core/models/rating.dart', (i, d) => RatingFlag.fromDoc(i, d)),
    'FleetInvite': ('lib/core/models/fleet.dart', (i, d) => FleetInvite.fromDoc(i, d)),
    'FleetMember': ('lib/core/models/fleet.dart', (i, d) => FleetMember.fromDoc(i, d)),
    'RecurringLoad': ('lib/core/models/recurring.dart', (i, d) => RecurringLoad.fromDoc(i, d)),
    'SavedSearch': ('lib/core/models/saved_search.dart', (i, d) => SavedSearch.fromDoc(i, d)),
    'TripAccount': ('lib/core/transporter/transporter_logic.dart', (i, d) => TripAccount.fromMap(i, d)),
    'CallDoc': ('lib/core/call/call_models.dart', (i, d) => CallDoc.fromMap(i, d)),
    'TransporterProfile': ('lib/core/transporter/transporter_logic.dart', (i, d) => TransporterProfile.fromUser(d)),
    'EconomicsCosts': ('lib/core/analytics/unit_economics.dart', (i, d) => EconomicsCosts.fromMap(d)),
  };

  group('documents read by id and map', () {
    for (final e in fromIdMap.entries) {
      final (file, build) = e.value;
      test('${e.key}: an empty document and one with every key null', () {
        expect(() => build('x1', <String, dynamic>{}), returnsNormally, reason: 'empty');
        final nulls = <String, dynamic>{for (final k in keysIn(file)) k: null};
        expect(() => build('x1', nulls), returnsNormally, reason: 'all null: ${nulls.keys}');
      });
    }
  });

  group('documents read from a snapshot', () {
    for (final e in fromDoc.entries) {
      final (file, build) = e.value;
      test('${e.key}: an empty document and one with every key null', () async {
        final db = FakeFirebaseFirestore();
        await db.collection('t').doc('empty').set({'_': 1});
        await db.collection('t').doc('nulls').set({for (final k in keysIn(file)) k: null});
        final empty = await db.collection('t').doc('empty').get();
        final nulls = await db.collection('t').doc('nulls').get();
        expect(() => build(empty), returnsNormally, reason: 'empty');
        expect(() => build(nulls), returnsNormally, reason: 'all null');
      });
    }
  });
}
