import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/truck_board.dart';
import '../models/vehicle.dart';
import 'backend.dart';
import 'risk_service.dart';

class TruckBoardException implements Exception {
  /// `driver_not_verified`, `route`, `date`, `vehicle`, `own_post`, `closed`, `details`.
  final String reason;
  const TruckBoardException(this.reason);

  @override
  String toString() => 'TruckBoardException($reason)';
}

/// The empty-truck board: drivers post "free from A to B", customers browse
/// and request. Records only: nothing is booked until the customer posts the
/// load (reserved for the driver) and a driver accepts it as usual.
class TruckBoardService {
  TruckBoardService._();

  static FirebaseFirestore get _db => Backend.db;
  static CollectionReference<Map<String, dynamic>> get _posts => _db.collection('truck_posts');
  static CollectionReference<Map<String, dynamic>> get _requests => _db.collection('truck_requests');

  // ---- driver ----

  static Future<String> post({
    required Vehicle vehicle,
    required String fromCity,
    required String toCity,
    required DateTime date,
    String note = '',
    DateTime? now,
  }) async {
    final uid = Backend.requireUid();
    await RiskService.ensureCanTransact();
    final today = now ?? DateTime.now();
    final day = DateTime(date.year, date.month, date.day);
    final from = fromCity.trim(), to = toCity.trim(), n = note.trim();
    if (from.length < 2 || to.length < 2 || from.length > 60 || to.length > 60) throw const TruckBoardException('route');
    if (n.length > 200) throw const TruckBoardException('details');
    if (day.isBefore(DateTime(today.year, today.month, today.day)) || day.isAfter(today.add(const Duration(days: TruckPost.maxDaysAhead)))) {
      throw const TruckBoardException('date');
    }
    if (vehicle.ownerId != uid || !vehicle.isActive) throw const TruckBoardException('vehicle');
    final profile = (await _db.collection('users').doc(uid).get()).data() ?? const {};
    if (profile['verified'] != true) throw const TruckBoardException('driver_not_verified');
    final ref = await _posts.add({
      'driverId': uid,
      'driverName': profile['driverName'] ?? '',
      'vehicleId': vehicle.id,
      'vehicleNumber': vehicle.number,
      'vehicleType': vehicle.type,
      'capacity': vehicle.capacity,
      'fromCity': from,
      'toCity': to,
      'availableDate': Timestamp.fromDate(day),
      if (n.isNotEmpty) 'note': n,
      'status': TruckPost.open,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static Future<void> closePost(String id) => _posts.doc(id).update({'status': TruckPost.closed, 'closedAt': FieldValue.serverTimestamp()});

  static Stream<List<TruckPost>> watchMyPosts() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _posts.where('driverId', isEqualTo: uid).snapshots().map(_sortedPosts);
  }

  /// Requests addressed to the signed-in driver, newest first.
  static Stream<List<TruckRequest>> watchRequestsForDriver() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _requests.where('driverId', isEqualTo: uid).snapshots().map(_sortedRequests);
  }

  /// Accept or decline. The customer sees the answer in My requests.
  static Future<void> answer(TruckRequest r, {required bool accept}) async {
    if (r.driverId != Backend.requireUid() || r.status != TruckRequest.pending) throw const TruckBoardException('closed');
    await _requests.doc(r.id).update({
      'status': accept ? TruckRequest.accepted : TruckRequest.declined,
      'answeredAt': FieldValue.serverTimestamp(),
    });
  }

  // ---- customer ----

  /// Open posts that are still dated today or later, soonest first.
  static Stream<List<TruckPost>> watchOpenBoard({DateTime? now}) {
    final today = now ?? DateTime.now();
    return _posts.where('status', isEqualTo: TruckPost.open).snapshots().map((s) {
      final list = _sortedPosts(s).where((p) => p.isOpenOn(today)).toList()
        ..sort((a, b) => a.availableDate.compareTo(b.availableDate));
      return list;
    });
  }

  static Future<String> sendRequest(
    TruckPost post, {
    required String pickup,
    required String drop,
    required num weight,
    String cargoType = '',
    String note = '',
  }) async {
    final uid = Backend.requireUid();
    await RiskService.ensureCanTransact();
    if (post.driverId == uid) throw const TruckBoardException('own_post');
    if (!post.isOpenOn(DateTime.now())) throw const TruckBoardException('closed');
    final p = pickup.trim(), d = drop.trim(), n = note.trim();
    if (p.length < 2 || d.length < 2 || weight <= 0 || weight > 100 || n.length > 200 || cargoType.trim().length > 40) {
      throw const TruckBoardException('details');
    }
    final profile = (await _db.collection('users').doc(uid).get()).data() ?? const {};
    final id = TruckRequest.idFor(post.id, uid);
    await _requests.doc(id).set({
      'postId': post.id,
      'driverId': post.driverId,
      'customerId': uid,
      'customerName': profile['name'] ?? '',
      'pickup': p,
      'drop': d,
      'weight': weight,
      if (cargoType.trim().isNotEmpty) 'cargoType': cargoType.trim(),
      'vehicleType': post.vehicleType,
      if (n.isNotEmpty) 'note': n,
      'status': TruckRequest.pending,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return id;
  }

  static Future<void> withdrawRequest(String id) => _requests.doc(id).update({'status': TruckRequest.withdrawn});

  static Stream<List<TruckRequest>> watchMyRequests() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _requests.where('customerId', isEqualTo: uid).snapshots().map(_sortedRequests);
  }

  static List<TruckPost> _sortedPosts(QuerySnapshot<Map<String, dynamic>> s) {
    final list = [for (final d in s.docs) TruckPost.fromDoc(d.id, d.data())];
    list.sort((a, b) => (b.createdAt ?? DateTime(3000)).compareTo(a.createdAt ?? DateTime(3000)));
    return list;
  }

  static List<TruckRequest> _sortedRequests(QuerySnapshot<Map<String, dynamic>> s) {
    final list = [for (final d in s.docs) TruckRequest.fromDoc(d.id, d.data())];
    list.sort((a, b) => (b.createdAt ?? DateTime(3000)).compareTo(a.createdAt ?? DateTime(3000)));
    return list;
  }
}
