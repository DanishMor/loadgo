import 'package:firebase_auth/firebase_auth.dart';

/// Translation key for a Firebase Auth error code (phone sign-in).
String authErrorKey(String code) {
  switch (code) {
    case 'invalid-phone-number':
    case 'missing-phone-number':
      return 'authErrInvalidPhone';
    case 'invalid-verification-code':
    case 'missing-verification-code':
      return 'invalidOtp';
    case 'session-expired':
    case 'code-expired':
    case 'invalid-verification-id':
      return 'otpExpired';
    case 'too-many-requests':
      return 'authErrTooMany';
    case 'quota-exceeded':
      return 'authErrQuota';
    case 'network-request-failed':
      return 'authErrNetwork';
    case 'captcha-check-failed':
    case 'missing-client-identifier':
    case 'app-not-authorized':
      return 'authErrCaptcha';
    case 'user-disabled':
      return 'authErrDisabled';
    default:
      return 'otpFailed';
  }
}

/// `+919876543210` / `9876543210` -> `+91 98•••••210`. Short or odd input is
/// returned unchanged.
String maskPhone(String? phone) {
  final raw = (phone ?? '').replaceAll(RegExp(r'\s'), '');
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 10) return phone ?? '';
  final local = digits.substring(digits.length - 10);
  final cc = digits.length > 10 ? '+${digits.substring(0, digits.length - 10)} ' : '';
  return '$cc${local.substring(0, 2)}•••••${local.substring(7)}';
}

/// Outcome callbacks of [sendPhoneOtp].
class OtpCallbacks {
  final void Function(String verificationId, int? resendToken) onCodeSent;
  final void Function(String errorKey) onError;
  final Future<void> Function(PhoneAuthCredential credential) onAutoVerified;

  const OtpCallbacks({required this.onCodeSent, required this.onError, required this.onAutoVerified});
}

/// Starts (or, with [resendToken], resends) the SMS code for an Indian
/// 10-digit [localNumber].
Future<void> sendPhoneOtp(String localNumber, OtpCallbacks cb, {int? resendToken}) async {
  try {
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: '+91$localNumber',
      forceResendingToken: resendToken,
      timeout: const Duration(seconds: 60),
      verificationCompleted: cb.onAutoVerified,
      verificationFailed: (e) => cb.onError(authErrorKey(e.code)),
      codeSent: cb.onCodeSent,
      codeAutoRetrievalTimeout: (_) {},
    );
  } on FirebaseAuthException catch (e) {
    cb.onError(authErrorKey(e.code));
  } catch (_) {
    cb.onError('otpFailed');
  }
}
