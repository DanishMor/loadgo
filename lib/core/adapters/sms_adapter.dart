/// Why a message was not sent.
enum SmsFailure { notConfigured, invalidNumber, rateLimited, providerError }

class SmsResult {
  final bool ok;
  final String? messageId;
  final SmsFailure? failure;
  const SmsResult.sent(String this.messageId)
      : ok = true,
        failure = null;
  const SmsResult.failed(SmsFailure this.failure)
      : ok = false,
        messageId = null;
}

class OtpStart {
  final bool ok;
  final String? challengeId;
  final SmsFailure? failure;
  const OtpStart.started(String this.challengeId)
      : ok = true,
        failure = null;
  const OtpStart.failed(SmsFailure this.failure)
      : ok = false,
        challengeId = null;
}

/// LATER(paid): a DLT-registered SMS provider. Used for emergency-contact
/// SMS and as an OTP fallback. Numbers are E.164 (`+919876543210`).
abstract class SmsGateway {
  Future<SmsResult> send(String toE164, String text);

  /// One-time code login through this provider (today Firebase Auth does it).
  Future<OtpStart> startOtp(String toE164);

  /// True when [code] is right for [challengeId]. A challenge allows 5 tries.
  Future<bool> verifyOtp(String challengeId, String code);
}

final RegExp _e164 = RegExp(r'^\+[1-9]\d{9,14}$');
bool isE164(String s) => _e164.hasMatch(s);

/// Default: nothing is sent.
class NoSmsGateway implements SmsGateway {
  const NoSmsGateway();
  @override
  Future<SmsResult> send(String toE164, String text) async => const SmsResult.failed(SmsFailure.notConfigured);
  @override
  Future<OtpStart> startOtp(String toE164) async => const OtpStart.failed(SmsFailure.notConfigured);
  @override
  Future<bool> verifyOtp(String challengeId, String code) async => false;
}

class FakeSmsGateway implements SmsGateway {
  final List<(String, String)> sent = [];
  final Map<String, String> _codes = {};
  final Map<String, int> _tries = {};
  final Map<String, int> _perNumber = {};
  int _n = 0;

  /// Sends allowed per number (the fake of a provider's rate limit).
  int limitPerNumber = 5;

  @override
  Future<SmsResult> send(String toE164, String text) async {
    if (!isE164(toE164)) return const SmsResult.failed(SmsFailure.invalidNumber);
    final c = (_perNumber[toE164] ?? 0) + 1;
    _perNumber[toE164] = c;
    if (c > limitPerNumber) return const SmsResult.failed(SmsFailure.rateLimited);
    sent.add((toE164, text));
    return SmsResult.sent('m${++_n}');
  }

  @override
  Future<OtpStart> startOtp(String toE164) async {
    if (!isE164(toE164)) return const OtpStart.failed(SmsFailure.invalidNumber);
    final id = 'c${++_n}';
    _codes[id] = '123456';
    _tries[id] = 0;
    return OtpStart.started(id);
  }

  /// Test helper: the code the fake "sent".
  String? codeFor(String challengeId) => _codes[challengeId];

  @override
  Future<bool> verifyOtp(String challengeId, String code) async {
    final real = _codes[challengeId];
    if (real == null) return false;
    final t = (_tries[challengeId] ?? 0) + 1;
    _tries[challengeId] = t;
    if (t > 5) return false;
    final ok = code == real;
    if (ok) _codes.remove(challengeId);
    return ok;
  }
}
