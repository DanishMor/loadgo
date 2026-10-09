import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/booking.dart';
import 'backend.dart';
import 'booking_service.dart';

/// A trip step the driver did without a network (MASTER-6 Task 23).
class QueuedAction {
  final String bookingId;

  /// The status the booking had when the driver pressed the button; if it is
  /// different when we get online, someone else moved the trip and the step is dropped.
  final String from;
  final String? otp;
  final Map<String, dynamic>? pickup;
  final Map<String, dynamic>? delivery;
  final DateTime queuedAt;

  const QueuedAction({required this.bookingId, required this.from, this.otp, this.pickup, this.delivery, required this.queuedAt});

  Map<String, Object?> toJson() => {
        'bookingId': bookingId,
        'from': from,
        'otp': otp,
        'pickup': pickup,
        'delivery': delivery,
        'queuedAt': queuedAt.toIso8601String(),
      };

  static QueuedAction? fromJson(Object? m) {
    if (m is! Map || m['bookingId'] is! String || m['from'] is! String) return null;
    final at = DateTime.tryParse('${m['queuedAt']}');
    if (at == null) return null;
    return QueuedAction(
      bookingId: m['bookingId'] as String,
      from: m['from'] as String,
      otp: m['otp'] as String?,
      pickup: m['pickup'] is Map ? Map<String, dynamic>.from(m['pickup'] as Map) : null,
      delivery: m['delivery'] is Map ? Map<String, dynamic>.from(m['delivery'] as Map) : null,
      queuedAt: at,
    );
  }
}

/// What happened to the queue on a flush.
class FlushResult {
  final int sent;

  /// Steps that could not be done and were dropped, with why: `otp` (the code
  /// was wrong), `moved` (the trip is no longer at the step), `gone`.
  final List<({String bookingId, String why})> dropped;

  /// Steps still waiting (no network again, or a temporary error).
  final int left;
  const FlushResult({this.sent = 0, this.dropped = const [], this.left = 0});
}

/// Trip steps done without a network wait here and go out in order when the
/// phone is online again. Free: shared_preferences, no server. A step is only
/// queued by the trip screen when the phone is offline or the call failed
/// because the network was down; the OTP is checked by the rules when it is sent.
class TripActionQueue {
  TripActionQueue._();

  static const maxQueued = 20;

  /// How many steps wait (for the sync indicator).
  static final ValueNotifier<int> count = ValueNotifier(0);

  static String get _key => 'trip_queue_${Backend.uid ?? 'anon'}';

  static Future<List<QueuedAction>> pending() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return const [];
      final list = jsonDecode(raw);
      return list is List ? [for (final x in list) ?QueuedAction.fromJson(x)] : const [];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _save(List<QueuedAction> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (list.isEmpty) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, jsonEncode([for (final a in list) a.toJson()]));
      }
    } catch (_) {}
    count.value = list.length;
  }

  static Future<void> refreshCount() async => count.value = (await pending()).length;

  /// Adds a step; the same booking and step is kept once (the newest wins).
  static Future<void> enqueue(QueuedAction a) async {
    final list = [for (final x in await pending()) if (!(x.bookingId == a.bookingId && x.from == a.from)) x, a];
    await _save(list.length > maxQueued ? list.sublist(list.length - maxQueued) : list);
  }

  /// True when a failed call looks like "no network" and the step can wait.
  static bool isNetworkError(Object e) {
    if (e is FirebaseException) return const ['unavailable', 'deadline-exceeded', 'network-request-failed'].contains(e.code);
    final s = e.toString().toLowerCase();
    return s.contains('socketexception') || s.contains('network') || s.contains('unavailable');
  }

  static bool _flushing = false;

  /// Sends the waiting steps in order. [send] defaults to
  /// [BookingService.advance]; [statusOf] reads the booking's status now.
  static Future<FlushResult> flush({
    Future<String> Function(String bookingId, {String? otp, PickupProof? pickup, DeliveryProof? delivery})? send,
    Future<String?> Function(String bookingId)? statusOf,
  }) async {
    if (_flushing) return FlushResult(left: count.value);
    _flushing = true;
    try {
      final todo = await pending();
      if (todo.isEmpty) {
        count.value = 0;
        return const FlushResult();
      }
      final push = send ?? (id, {otp, pickup, delivery}) => BookingService.advance(id, otp: otp, pickup: pickup, delivery: delivery);
      final current = statusOf ?? (id) async => (await Backend.db.collection('bookings').doc(id).get()).data()?['status'] as String?;
      var sent = 0;
      final dropped = <({String bookingId, String why})>[];
      final keep = <QueuedAction>[];
      var offline = false;
      for (final a in todo) {
        if (offline) {
          keep.add(a);
          continue;
        }
        try {
          final now = await current(a.bookingId);
          if (now == null) {
            dropped.add((bookingId: a.bookingId, why: 'gone'));
            continue;
          }
          if (now != a.from) {
            dropped.add((bookingId: a.bookingId, why: 'moved'));
            continue;
          }
          await push(
            a.bookingId,
            otp: a.otp,
            pickup: a.pickup == null ? null : PickupProof.fromMap(a.pickup!),
            delivery: a.delivery == null ? null : DeliveryProof.fromMap(a.delivery!),
          );
          sent++;
        } on WrongOtpException {
          dropped.add((bookingId: a.bookingId, why: 'otp'));
        } catch (e) {
          if (isNetworkError(e)) {
            offline = true;
          }
          keep.add(a);
        }
      }
      await _save(keep);
      return FlushResult(sent: sent, dropped: dropped, left: keep.length);
    } finally {
      _flushing = false;
    }
  }
}
