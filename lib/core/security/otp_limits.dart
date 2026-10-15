import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The limits on login codes (F1). One place, so a screen redesign cannot
/// quietly drop them (see test/otp_limits_guard_test.dart).
///
/// These run on the phone, so a determined person can get around them (clear
/// app data, another phone). The real protection is Firebase's own limits,
/// the SMS region and a budget alert; see docs/OTP_SECURITY.md.
class OtpPolicy {
  OtpPolicy._();

  /// Seconds before "Resend" turns on.
  static const resendSeconds = 60;

  /// Codes that may be sent to one number in any rolling hour.
  static const sendsPerHour = 5;

  /// Wrong codes allowed before the number is locked.
  static const maxWrongAttempts = 5;

  /// How long the lock lasts.
  static const lockMinutes = 15;
}

/// Where the counters live. Tests pass a map.
abstract class OtpLimitStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class PrefsOtpLimitStore implements OtpLimitStore {
  const PrefsOtpLimitStore();

  @override
  Future<String?> read(String key) async {
    try {
      return (await SharedPreferences.getInstance()).getString(key);
    } catch (_) {
      return null; // storage broken: do not block the user on our own bookkeeping
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await (await SharedPreferences.getInstance()).setString(key, value);
    } catch (_) {}
  }
}

/// What happened after a wrong code.
class OtpFailure {
  final int attemptsLeft;

  /// Set when this wrong code locked the number.
  final Duration? lockedFor;
  const OtpFailure(this.attemptsLeft, this.lockedFor);
}

/// Per-phone counters: sends in the last hour, wrong codes, lock time.
/// The phone number is never stored, only a short hash of it.
class OtpLimiter {
  final OtpLimitStore store;
  final DateTime Function() now;

  OtpLimiter({this.store = const PrefsOtpLimitStore(), DateTime Function()? now}) : now = now ?? DateTime.now;

  static final OtpLimiter instance = OtpLimiter();

  static String keyFor(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    var h = 0x811c9dc5; // FNV-1a, 32 bit
    for (final u in digits.codeUnits) {
      h = ((h ^ u) * 0x01000193) & 0xffffffff;
    }
    return 'otp_lim_${h.toRadixString(16)}';
  }

  Future<_State> _load(String phone) async {
    try {
      final raw = await store.read(keyFor(phone));
      if (raw == null) return _State();
      final m = jsonDecode(raw);
      if (m is! Map) return _State();
      final sends = <int>[];
      final s = m['s'];
      if (s is List) {
        for (final v in s) {
          if (v is int) sends.add(v);
        }
      }
      final w = m['w'];
      final l = m['l'];
      return _State(sends: sends, wrong: w is int ? w : 0, lockUntil: l is int ? l : 0);
    } catch (_) {
      return _State();
    }
  }

  Future<void> _save(String phone, _State st) =>
      store.write(keyFor(phone), jsonEncode({'s': st.sends, 'w': st.wrong, 'l': st.lockUntil}));

  /// Time left until another code may be asked for this number, or null.
  Future<Duration?> sendBlockedFor(String phone) async {
    final st = await _load(phone);
    final t = now().millisecondsSinceEpoch;
    final locked = _remaining(st.lockUntil, t);
    final hourAgo = t - const Duration(hours: 1).inMilliseconds;
    final recent = st.sends.where((x) => x > hourAgo).toList()..sort();
    Duration? capped;
    if (recent.length >= OtpPolicy.sendsPerHour) {
      capped = Duration(milliseconds: recent.first + const Duration(hours: 1).inMilliseconds - t);
    }
    if (locked == null) return capped;
    if (capped == null) return locked;
    return locked > capped ? locked : capped;
  }

  Future<void> recordSend(String phone) async {
    final st = await _load(phone);
    final t = now().millisecondsSinceEpoch;
    final hourAgo = t - const Duration(hours: 1).inMilliseconds;
    st.sends
      ..removeWhere((x) => x <= hourAgo)
      ..add(t);
    await _save(phone, st);
  }

  /// Time left on a wrong-code lock, or null.
  Future<Duration?> lockedFor(String phone) async {
    final st = await _load(phone);
    return _remaining(st.lockUntil, now().millisecondsSinceEpoch);
  }

  /// Counts a wrong code. The 5th one locks for [OtpPolicy.lockMinutes].
  Future<OtpFailure> recordWrong(String phone) async {
    final st = await _load(phone);
    final t = now().millisecondsSinceEpoch;
    if (_remaining(st.lockUntil, t) == null && st.lockUntil != 0) {
      st.wrong = 0; // an old lock has run out: start counting again
      st.lockUntil = 0;
    }
    st.wrong += 1;
    Duration? lock;
    if (st.wrong >= OtpPolicy.maxWrongAttempts) {
      lock = const Duration(minutes: OtpPolicy.lockMinutes);
      st.lockUntil = t + lock.inMilliseconds;
      st.wrong = 0;
    }
    await _save(phone, st);
    final left = OtpPolicy.maxWrongAttempts - st.wrong;
    return OtpFailure(lock == null ? left : 0, lock);
  }

  /// A correct code clears the wrong-code counter (sends stay counted).
  Future<void> recordSuccess(String phone) async {
    final st = await _load(phone);
    st.wrong = 0;
    st.lockUntil = 0;
    await _save(phone, st);
  }

  static Duration? _remaining(int until, int t) => until > t ? Duration(milliseconds: until - t) : null;
}

class _State {
  final List<int> sends;
  int wrong;
  int lockUntil;
  _State({List<int>? sends, this.wrong = 0, this.lockUntil = 0}) : sends = sends ?? [];
}

/// Whole minutes to show (never 0 while a wait remains).
int minutesLeft(Duration d) {
  final m = (d.inSeconds + 59) ~/ 60;
  return m < 1 ? 1 : m;
}
