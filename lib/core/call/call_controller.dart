import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/booking.dart';
import '../services/backend.dart';
import '../services/comm_guard.dart';
import '../services/rate_limit_service.dart';
import 'call_models.dart';
import 'call_provider.dart';
import 'call_signaling.dart';

enum CallPhase { idle, preparing, ringing, incoming, connecting, connected, ended, failed }

/// Why a call ended, for the message on the call screen.
enum CallEnd { hungUp, noAnswer, declined, cancelled, remoteEnded, failed, micDenied, blocked, unsupported, tooMany }

/// One call, from either side. Drives the [CallProvider] (media) and
/// [CallSignaling] (Firestore) and tells the screen what to show.
class CallController extends ChangeNotifier {
  final CallProvider provider;
  final Duration ringTimeout;

  CallController(this.provider, {this.ringTimeout = callRingTimeout});

  CallPhase phase = CallPhase.idle;
  CallEnd? endReason;
  bool muted = false;
  bool speaker = false;
  String? callId;
  String peerName = '';

  final _subs = <StreamSubscription<Object?>>[];
  Timer? _ring;
  bool _remoteSet = false;
  final _pending = <CallCandidate>[];
  bool _disposed = false;
  bool _finishing = false;
  bool _endingHere = false;

  bool get isActive => const [CallPhase.preparing, CallPhase.ringing, CallPhase.incoming, CallPhase.connecting, CallPhase.connected].contains(phase);

  void _set(CallPhase p, {CallEnd? end}) {
    if (_disposed) return;
    phase = p;
    if (end != null) endReason = end;
    notifyListeners();
  }

  /// Rings [calleeId] about [booking]. Never throws: problems become [endReason].
  Future<void> start({required Booking booking, required String calleeId, required String callerName, String peer = ''}) async {
    if (isActive) return;
    peerName = peer;
    _set(CallPhase.preparing);
    try {
      if (!provider.supported) {
        await _finish(CallEnd.unsupported);
        return;
      }
      await CommGuard.ensureAllowed();
      await provider.init();
      final offer = await provider.createOffer();
      final id = await CallSignaling.create(
        bookingId: booking.id,
        calleeId: calleeId,
        callerName: callerName,
        vehicleNumber: booking.assignedVehicleNumber.isNotEmpty ? booking.assignedVehicleNumber : booking.vehicleNumber,
        offerSdp: offer,
      );
      callId = id;
      _wire(id, caller: true);
      _set(CallPhase.ringing);
      _ring = Timer(ringTimeout, () async {
        if (phase != CallPhase.ringing) return;
        _endingHere = true;
        await _safe(() => CallSignaling.cancel(id));
        await _finish(CallEnd.noAnswer);
      });
    } on ChatBlockedException {
      await _finish(CallEnd.blocked);
    } on MicDeniedException {
      await _finish(CallEnd.micDenied);
    } on RateLimitException {
      await _finish(CallEnd.tooMany);
    } catch (_) {
      await _finish(CallEnd.failed);
    }
  }

  /// Takes a call that is ringing for this person.
  Future<void> answer(CallDoc call) async {
    if (isActive) return;
    callId = call.id;
    peerName = call.callerName;
    _set(CallPhase.preparing);
    try {
      if (!provider.supported) {
        await _safe(() => CallSignaling.decline(call.id));
        await _finish(CallEnd.unsupported);
        return;
      }
      await CommGuard.ensureAllowed();
      await provider.init();
      final answerSdp = await provider.acceptOffer(call.offerSdp ?? '');
      _remoteSet = true;
      await CallSignaling.accept(call.id, answerSdp);
      _wire(call.id, caller: false);
      _set(CallPhase.connecting);
    } on ChatBlockedException {
      await _safe(() => CallSignaling.decline(call.id));
      await _finish(CallEnd.blocked);
    } on MicDeniedException {
      await _safe(() => CallSignaling.decline(call.id));
      await _finish(CallEnd.micDenied);
    } catch (_) {
      await _safe(() => CallSignaling.decline(call.id));
      await _finish(CallEnd.failed);
    }
  }

  Future<void> decline(CallDoc call) async {
    await _safe(() => CallSignaling.decline(call.id));
    await _finish(CallEnd.declined);
  }

  /// Ends the call from this side (cancel while ringing, end once connected).
  Future<void> hangUp() async {
    final id = callId;
    final ringing = phase == CallPhase.ringing;
    _endingHere = true; // the document change we cause ourselves is not "the other side hung up"
    if (id != null) {
      await _safe(() => ringing ? CallSignaling.cancel(id) : CallSignaling.end(id));
    }
    await _finish(ringing ? CallEnd.cancelled : CallEnd.hungUp);
  }

  Future<void> toggleMute() async {
    muted = !muted;
    await provider.setMuted(muted);
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    speaker = !speaker;
    await provider.setSpeaker(speaker);
    notifyListeners();
  }

  void _wire(String id, {required bool caller}) {
    _subs.add(provider.localCandidates.listen((c) => _safe(() => CallSignaling.addCandidate(id, c))));
    _subs.add(provider.connected.listen((ok) {
      if (ok && isActive) {
        _ring?.cancel();
        _set(CallPhase.connected);
      } else if (!ok && isActive) {
        _finish(CallEnd.failed);
      }
    }));
    _subs.add(CallSignaling.watchRemoteCandidates(id).listen((c) async {
      if (!_remoteSet) {
        _pending.add(c);
      } else {
        await _safe(() => provider.addRemoteCandidate(c));
      }
    }));
    _subs.add(CallSignaling.watch(id).listen((doc) async {
      if (doc == null || !isActive || _endingHere) return;
      if (caller && doc.status == CallStatus.accepted && !_remoteSet && doc.answerSdp != null) {
        _ring?.cancel();
        try {
          await provider.setAnswer(doc.answerSdp!);
          _remoteSet = true;
          for (final c in _pending) {
            await _safe(() => provider.addRemoteCandidate(c));
          }
          _pending.clear();
          _set(CallPhase.connecting);
        } catch (_) {
          await _finish(CallEnd.failed);
        }
      } else if (doc.status == CallStatus.declined) {
        await _finish(CallEnd.declined);
      } else if (doc.status == CallStatus.cancelled || doc.status == CallStatus.ended) {
        await _finish(CallEnd.remoteEnded);
      }
    }));
  }

  Future<void> _finish(CallEnd why) async {
    if (_finishing || phase == CallPhase.ended || phase == CallPhase.failed) return;
    _finishing = true;
    _ring?.cancel();
    final subs = List.of(_subs);
    _subs.clear();
    for (final s in subs) {
      await s.cancel();
    }
    await _safe(provider.close);
    _set(why == CallEnd.failed || why == CallEnd.micDenied || why == CallEnd.unsupported ? CallPhase.failed : CallPhase.ended, end: why);
  }

  static Future<void> _safe(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _ring?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    if (isActive) _safe(provider.close);
    super.dispose();
  }

  /// The signed-in person's display name for the call document (never a phone number).
  static Future<String> myDisplayName() async {
    try {
      final uid = Backend.uid;
      if (uid == null) return '';
      final u = (await Backend.db.collection('users').doc(uid).get()).data() ?? const {};
      final name = '${u['companyName'] ?? u['driverName'] ?? u['name'] ?? ''}';
      return name.length > 60 ? name.substring(0, 60) : name;
    } catch (_) {
      return ''; // offline: the call still rings, the other side just sees no name
    }
  }
}
