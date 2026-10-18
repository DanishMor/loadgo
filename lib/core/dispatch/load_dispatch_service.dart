import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/load.dart';
import '../pricing/cities.dart';
import '../services/backend.dart';
import '../services/server_clock.dart';
import 'dispatch_config_service.dart';
import 'dispatch_models.dart';
import 'instant_progress.dart';

/// The things a customer can do to an open load to get it taken (U12, U13): raise the price, search wider,
/// give the bid window more time, set an auto-accept rule. Each is one small update that the rules
/// already check (the owner of an open load; valid mode, window, rule and ring boost).
class LoadDispatchService {
  LoadDispatchService._();

  static const maxBoost = 3;
  static const maxWindowExtensions = 3;

  static DocumentReference<Map<String, dynamic>> _ref(String id) => Backend.db.collection('loads').doc(id);

  /// +5% or +10% on the price. Returns the new price in rupees, or null when not allowed (see [PriceBump]).
  static Future<int?> raisePrice(Load load, int percent) async {
    if (!load.isOpen || load.shipperId != Backend.uid) return null;
    final next = PriceBump.bumped(load.budget, percent, estimatePaise: load.estimate?.total);
    if (next == null) return null;
    await _ref(load.id).update({'budget': next, 'updatedAt': FieldValue.serverTimestamp()});
    return next;
  }

  /// Search one ring wider, at most [maxBoost] times. Returns the new boost, or null at the limit.
  static Future<int?> widenRange(Load load) async {
    if (!load.isOpen || load.shipperId != Backend.uid || load.ringBoost >= maxBoost) return null;
    final next = load.ringBoost + 1;
    await _ref(load.id).update({'ringBoost': next, 'updatedAt': FieldValue.serverTimestamp()});
    return next;
  }

  /// "More time": the bid window ends [minutes] later than it would now (the later of the old end and now).
  static Future<DateTime?> extendBidWindow(Load load, {int minutes = 10}) async {
    if (!load.isOpen || load.shipperId != Backend.uid || load.mode != LoadMode.bid || minutes < 1 || minutes > 60) return null;
    final now = ServerClock.now();
    final from = load.bidWindowEnds != null && load.bidWindowEnds!.isAfter(now) ? load.bidWindowEnds! : now;
    final end = from.add(Duration(minutes: minutes));
    if (end.isAfter(now.add(const Duration(hours: 23)))) return null; // the rules allow 24 hours at most
    await _ref(load.id).update({'bidWindowEnds': Timestamp.fromDate(end), 'updatedAt': FieldValue.serverTimestamp()});
    return end;
  }

  /// No bid came: the customer turns the load into an instant one (drivers within the widest ring see it at once).
  static Future<bool> switchToInstant(Load load) async {
    if (!load.isOpen || load.shipperId != Backend.uid || load.mode != LoadMode.bid) return false;
    await _ref(load.id).update({'mode': LoadMode.instant.value, 'updatedAt': FieldValue.serverTimestamp()});
    return true;
  }

  /// Save or clear the auto-accept rule (U14).
  static Future<void> setAutoAccept(Load load, AutoAccept? rule) async {
    if (!load.isOpen || load.shipperId != Backend.uid) return;
    await _ref(load.id).update({'autoAccept': rule == null ? FieldValue.delete() : rule.toMap(), 'updatedAt': FieldValue.serverTimestamp()});
  }

  /// The rings and times for this load: the general settings with the override of its pickup city.
  static DispatchConfig configFor(Load load) => DispatchConfigService.current.forCity(findCity(load.pickup)?.name);

  /// The state of an instant load's search right now.
  static InstantProgress? progressOf(Load load, {DateTime? now}) {
    final created = load.createdAt?.toDate();
    if (created == null) return null;
    return InstantProgress.at(configFor(load), createdAt: created, now: now ?? ServerClock.now(), boost: load.ringBoost);
  }

  /// The end of the bid window for a new bid-mode load.
  static DateTime newBidWindowEnd({DateTime? now}) => (now ?? ServerClock.now()).add(Duration(minutes: DispatchConfigService.current.bidWindowMinutes));
}
