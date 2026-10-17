import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app_info.dart';
import '../constants/logistics.dart';
import '../features/features.dart';
import '../models/booking.dart';
import '../services/backend.dart';
import '../services/booking_service.dart';
import '../services/features_service.dart';
import '../services/location_service.dart';
import '../services/settings_service.dart';
import 'live_location_policy.dart';

enum SharingState { off, starting, on, noConsent, noPermission }

/// G11: the driver's live position for ONE trip, behind the `liveLocation` switch
/// (OFF). It:
///  * needs the driver's location consent and the phone permission (else it says why and does nothing),
///  * runs as an Android foreground service (a visible notification) so it keeps working with the screen
///    off, and only while the trip is on the way or in transit,
///  * writes with [LiveLocationPolicy] (30 s gap, 100 m move, 5 min heartbeat),
///  * stops by itself when the trip is delivered or cancelled, on sign-out, and when the driver stops it.
/// A server job deletes the last position a day after the trip ends (docs/LIVE_LOCATION.md).
class LiveLocationSharer {
  LiveLocationSharer._();

  static final ValueNotifier<SharingState> state = ValueNotifier(SharingState.off);
  static String? _bookingId;
  static StreamSubscription<Coordinates>? _pos;
  static StreamSubscription<Booking?>? _watch;
  static LiveLocationPolicy _policy = LiveLocationPolicy();

  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  @visibleForTesting
  static Future<bool> Function() consentGiven = () async => (await SettingsService.loadConsents()).location;

  @visibleForTesting
  static Stream<Booking?> Function(String id) watchBooking = BookingService.watch;

  @visibleForTesting
  static Future<void> Function(String id, double lat, double lng) write = BookingService.updateLocation;

  static bool get enabled => FeaturesService.isOn(FeatureKey.liveLocation);
  static String? get activeBooking => _bookingId;

  /// Starts (or keeps) sharing for [bookingId]. [notice] is the notification text shown by the phone.
  static Future<SharingState> start(String bookingId, {String noticeTitle = AppInfo.name, String noticeText = ''}) async {
    if (!enabled) return state.value = SharingState.off;
    if (_bookingId == bookingId && state.value == SharingState.on) return state.value;
    await stop();
    _bookingId = bookingId;
    state.value = SharingState.starting;
    bool consent;
    try {
      consent = await consentGiven();
    } catch (_) {
      consent = false;
    }
    if (_bookingId != bookingId) return state.value; // stopped meanwhile
    if (!consent) {
      _bookingId = null;
      return state.value = SharingState.noConsent;
    }
    if (!await LocationService.ensurePermission()) {
      _bookingId = null;
      return state.value = SharingState.noPermission;
    }
    _policy = LiveLocationPolicy(LiveLocationConfig.fromMap(await _config()));
    _pos = LocationService.positions(foregroundTitle: noticeTitle, foregroundText: noticeText).listen(_onPosition, onError: (_) => stop());
    _watch = watchBooking(bookingId).listen((b) {
      if (b == null || !(b.status == BookingStatus.driverArriving || b.isInTransit)) stop();
    }, onError: (_) {});
    return state.value = SharingState.on;
  }

  static Future<Map<String, dynamic>?> _config() async {
    try {
      return (await Backend.db.collection('config').doc('liveLocation').get()).data();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _onPosition(Coordinates c) async {
    final id = _bookingId;
    if (id == null) return;
    final t = now();
    if (!_policy.shouldWrite(c, t)) return;
    _policy.wrote(c, t); // before the await, so two quick fixes cannot both pass
    try {
      await write(id, c.lat, c.lng);
    } catch (_) {
      // Best effort: the next fix after the gap tries again.
    }
  }

  static Future<void> stop() async {
    final p = _pos, w = _watch;
    _pos = null;
    _watch = null;
    _bookingId = null;
    _policy.reset();
    state.value = SharingState.off;
    await p?.cancel();
    await w?.cancel();
  }
}
