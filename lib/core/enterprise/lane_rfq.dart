import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/backend.dart';

/// E30 (flag laneRfq): a lane tender. A business asks for a rate per trip on one lane for a few months;
/// transporters and drivers send one rate each; the business awards one or closes it. Records only: no booking,
/// no money and no contract is made by the app (firestore.rules `lane_rfqs`).
class LaneRfq {
  final String id;
  final String ownerId;
  final String ownerName;
  final String fromCity;
  final String toCity;
  final String vehicleType;
  final int tripsPerMonth;
  final int months;
  final String note;
  final DateTime? closesAt;
  final String status;
  final String? awardedTo;
  final int? awardedRatePaise;

  const LaneRfq({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.fromCity,
    required this.toCity,
    required this.vehicleType,
    required this.tripsPerMonth,
    required this.months,
    this.note = '',
    this.closesAt,
    this.status = 'open',
    this.awardedTo,
    this.awardedRatePaise,
  });

  static const statuses = ['open', 'awarded', 'closed'];

  /// Defensive: unknown status reads as closed, numbers out of range as 0.
  factory LaneRfq.fromMap(String id, Map<String, dynamic> d) {
    int n(String k) => d[k] is int ? d[k] as int : 0;
    String s(String k) => d[k] is String ? d[k] as String : '';
    final status = statuses.contains(d['status']) ? d['status'] as String : 'closed';
    return LaneRfq(
      id: id,
      ownerId: s('ownerId'),
      ownerName: s('ownerName'),
      fromCity: s('fromCity'),
      toCity: s('toCity'),
      vehicleType: s('vehicleType'),
      tripsPerMonth: n('tripsPerMonth'),
      months: n('months'),
      note: s('note'),
      closesAt: d['closesAt'] is Timestamp ? (d['closesAt'] as Timestamp).toDate() : null,
      status: status,
      awardedTo: d['awardedTo'] is String ? d['awardedTo'] as String : null,
      awardedRatePaise: d['awardedRatePaise'] is int ? d['awardedRatePaise'] as int : null,
    );
  }

  bool openAt(DateTime now) => status == 'open' && (closesAt?.isAfter(now) ?? false);

  int get totalTrips => tripsPerMonth * months;
}

class LaneBid {
  final String bidderId;
  final String bidderName;
  final int ratePaise;
  final String note;
  final DateTime? at;
  const LaneBid({required this.bidderId, required this.bidderName, required this.ratePaise, this.note = '', this.at});

  static LaneBid? fromMap(String id, Map<String, dynamic> d) {
    final rate = d['ratePaise'];
    if (rate is! int || rate <= 0) return null;
    return LaneBid(
      bidderId: id,
      bidderName: d['bidderName'] is String ? d['bidderName'] as String : '',
      ratePaise: rate,
      note: d['note'] is String ? d['note'] as String : '',
      at: d['at'] is Timestamp ? (d['at'] as Timestamp).toDate() : null,
    );
  }
}

/// Lowest rate first; ties by the earlier bid.
List<LaneBid> rankBids(Iterable<LaneBid> bids) => [...bids]..sort((a, b) {
    final c = a.ratePaise.compareTo(b.ratePaise);
    if (c != 0) return c;
    return (a.at ?? DateTime(9999)).compareTo(b.at ?? DateTime(9999));
  });

class LaneRfqService {
  LaneRfqService._();

  static const listLimit = 30;
  static const bidLimit = 50;

  static CollectionReference<Map<String, dynamic>> get _col => Backend.db.collection('lane_rfqs');

  static Future<String> create({
    required String ownerName,
    required String fromCity,
    required String toCity,
    required String vehicleType,
    required int tripsPerMonth,
    required int months,
    required DateTime closesAt,
    String note = '',
  }) async {
    final uid = Backend.requireUid();
    final ref = _col.doc();
    await ref.set({
      'ownerId': uid,
      'ownerName': ownerName.trim(),
      'fromCity': fromCity.trim(),
      'toCity': toCity.trim(),
      'vehicleType': vehicleType,
      'tripsPerMonth': tripsPerMonth,
      'months': months,
      'note': note.trim(),
      'closesAt': Timestamp.fromDate(closesAt),
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Open tenders (at most [listLimit]), soonest closing first.
  static Stream<List<LaneRfq>> watchOpen() => _col.where('status', isEqualTo: 'open').limit(listLimit).snapshots().map((s) =>
      [for (final d in s.docs) LaneRfq.fromMap(d.id, d.data())]..sort((a, b) => (a.closesAt ?? DateTime(9999)).compareTo(b.closesAt ?? DateTime(9999))));

  /// The signed-in owner's tenders (at most [listLimit]).
  static Stream<List<LaneRfq>> watchMine() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _col.where('ownerId', isEqualTo: uid).limit(listLimit).snapshots().map((s) => [for (final d in s.docs) LaneRfq.fromMap(d.id, d.data())]);
  }

  /// For the owner: every bid on a tender, lowest first.
  static Stream<List<LaneBid>> watchBids(String rfqId) =>
      _col.doc(rfqId).collection('bids').limit(bidLimit).snapshots().map((s) => rankBids([for (final d in s.docs) ?LaneBid.fromMap(d.id, d.data())]));

  /// For a bidder: their own bid, or null.
  static Future<LaneBid?> myBid(String rfqId) async {
    final uid = Backend.uid;
    if (uid == null) return null;
    final d = await _col.doc(rfqId).collection('bids').doc(uid).get();
    return d.exists ? LaneBid.fromMap(d.id, d.data()!) : null;
  }

  static Future<void> placeBid(String rfqId, {required String bidderName, required int ratePaise, String note = ''}) {
    final uid = Backend.requireUid();
    return _col.doc(rfqId).collection('bids').doc(uid).set({
      'bidderId': uid,
      'bidderName': bidderName.trim(),
      'ratePaise': ratePaise,
      'note': note.trim(),
      'at': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> award(String rfqId, LaneBid bid) => _col.doc(rfqId).update({
        'status': 'awarded',
        'awardedTo': bid.bidderId,
        'awardedRatePaise': bid.ratePaise,
        'decidedAt': FieldValue.serverTimestamp(),
      });

  static Future<void> close(String rfqId) => _col.doc(rfqId).update({'status': 'closed', 'decidedAt': FieldValue.serverTimestamp()});
}
