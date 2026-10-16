import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../features/features.dart';
import '../l10n/l10n.dart';
import '../security/otp_limits.dart';
import '../services/audit_service.dart';
import '../services/auth_helpers.dart';
import '../services/features_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/ds/app_button.dart';
import '../widgets/ds/otp_field.dart';

/// A problem during the check; [key] is a translation key (never raw text).
class StepUpError implements Exception {
  final String key;
  const StepUpError(this.key);
}

/// Where the code goes and how it is checked. The real one uses the signed-in
/// person's own phone number; tests use a fake.
abstract class StepUpBackend {
  /// The number the code goes to, for showing (masked on screen). Null when unknown.
  String? get phone;

  /// Sends a code, returns its verification id. Throws [StepUpError].
  Future<String> send();

  /// Checks the code and refreshes the sign-in so the server sees a fresh login
  /// (the rules look at `auth_time`). Throws [StepUpError].
  Future<void> confirm(String verificationId, String code);
}

class FirebaseStepUpBackend implements StepUpBackend {
  const FirebaseStepUpBackend();

  @override
  String? get phone => FirebaseAuth.instance.currentUser?.phoneNumber;

  String get _local {
    final digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
    return digits.length >= 10 ? digits.substring(digits.length - 10) : '';
  }

  @override
  Future<String> send() async {
    if (_local.isEmpty) throw const StepUpError('otpFailed');
    final done = Completer<String>();
    await sendPhoneOtp(
      _local,
      OtpCallbacks(
        onCodeSent: (id, _) {
          if (!done.isCompleted) done.complete(id);
        },
        onError: (key) {
          if (!done.isCompleted) done.completeError(StepUpError(key));
        },
        // Auto-retrieval: re-authenticate straight away and report an empty id.
        onAutoVerified: (credential) async {
          try {
            await FirebaseAuth.instance.currentUser?.reauthenticateWithCredential(credential);
            await FirebaseAuth.instance.currentUser?.getIdToken(true);
            if (!done.isCompleted) done.complete('');
          } catch (_) {
            if (!done.isCompleted) done.completeError(const StepUpError('otpFailed'));
          }
        },
      ),
    );
    return done.future;
  }

  @override
  Future<void> confirm(String verificationId, String code) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const StepUpError('authErrDisabled');
    try {
      if (verificationId.isNotEmpty) {
        await user.reauthenticateWithCredential(PhoneAuthProvider.credential(verificationId: verificationId, smsCode: code));
      }
      await user.getIdToken(true);
    } on FirebaseAuthException catch (e) {
      throw StepUpError(authErrorKey(e.code));
    }
  }
}

/// F11: before a payout request or a change of payout details the person
/// enters a fresh SMS code. The result is remembered for 5 minutes. The server
/// rules ask for the same thing (`auth_time` within 5 minutes) when the
/// `walletStepUp` flag is on; this is the screen side of it.
class StepUp {
  StepUp._();

  static const window = Duration(minutes: 5);
  static DateTime? _at;

  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  static bool get isFresh => _at != null && now().difference(_at!) < window;

  static void forget() => _at = null;

  /// True when the person may go on: the flag is off, a code was entered in the
  /// last 5 minutes, or a new code was just confirmed.
  static Future<bool> ensure(BuildContext context, {StepUpBackend backend = const FirebaseStepUpBackend()}) async {
    if (!FeaturesService.isOn(FeatureKey.walletStepUp)) return true;
    if (isFresh) return true;
    final ok = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => StepUpDialog(backend: backend));
    if (ok == true) {
      _at = now();
      // Best effort: the log must never block the person.
      try {
        unawaited(AuditService.record(AuditType.walletAction, data: {'action': 'step_up_ok'}).catchError((Object _) {}));
      } catch (_) {}
      return true;
    }
    return false;
  }
}

class StepUpDialog extends StatefulWidget {
  final StepUpBackend backend;
  const StepUpDialog({super.key, required this.backend});

  @override
  State<StepUpDialog> createState() => _StepUpDialogState();
}

class _StepUpDialogState extends State<StepUpDialog> {
  final _code = TextEditingController();
  final _countdown = CountdownController();
  String? _verificationId;
  String? _error; // translation key, or 'locked:<minutes>'
  bool _busy = true;
  bool _wrong = false;

  @override
  void initState() {
    super.initState();
    _send();
  }

  @override
  void dispose() {
    _countdown.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await widget.backend.send();
      if (!mounted) return;
      _verificationId = id;
      _countdown.start(OtpPolicy.resendSeconds);
      if (id.isEmpty) {
        // The phone read the code by itself: nothing more to enter.
        Navigator.of(context).pop(true);
        return;
      }
      setState(() => _busy = false);
    } on StepUpError catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.key;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'otpFailed';
      });
    }
  }

  Future<void> _confirm() async {
    final code = _code.text.trim();
    final phone = widget.backend.phone ?? '';
    if (code.length != 6 || _verificationId == null) {
      setState(() {
        _wrong = true;
        _error = 'invalidOtp';
      });
      return;
    }
    final locked = await OtpLimiter.instance.lockedFor(phone);
    if (locked != null) {
      if (!mounted) return;
      setState(() {
        _wrong = true;
        _error = 'locked:${minutesLeft(locked)}';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.backend.confirm(_verificationId!, code);
      await OtpLimiter.instance.recordSuccess(phone);
      if (mounted) Navigator.of(context).pop(true);
    } on StepUpError catch (e) {
      final wrong = e.key == 'invalidOtp';
      String? err = e.key;
      if (wrong) {
        final f = await OtpLimiter.instance.recordWrong(phone);
        err = f.lockedFor != null ? 'locked:${minutesLeft(f.lockedFor!)}' : 'left:${f.attemptsLeft}';
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _wrong = wrong;
        _error = err;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'otpFailed';
      });
    }
  }

  String _errorText(BuildContext context) {
    final e = _error!;
    if (e.startsWith('locked:')) return trf(context, 'otpLockedMin', {'m': e.substring(7)});
    if (e.startsWith('left:')) return trf(context, 'otpAttemptsLeft', {'n': e.substring(5)});
    return tr(context, e);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final phone = widget.backend.phone;
    return AlertDialog(
      title: Text(tr(context, 'stepUpTitle')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(trf(context, 'stepUpBody', {'number': maskPhone(phone)}), style: DsType.body.copyWith(color: c.text)),
          const SizedBox(height: DsSpace.s4),
          OtpField(
            fieldKey: const ValueKey('stepUpCode'),
            controller: _code,
            error: _wrong,
            autofocus: true,
            enabled: !_busy,
            onChanged: (_) {
              if (_wrong) setState(() => _wrong = false);
            },
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: DsSpace.s2),
              child: Text(_errorText(context), key: const ValueKey('stepUpError'), style: DsType.caption.copyWith(color: c.error)),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OtpResendButton(buttonKey: const ValueKey('stepUpResend'), countdown: _countdown, busy: _busy, onPressed: _send),
          ),
        ]),
      ),
      actions: [
        AppButton(
          key: const ValueKey('stepUpCancel'),
          label: tr(context, 'cancel'),
          kind: AppButtonKind.tertiary,
          expand: false,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(key: const ValueKey('stepUpConfirm'), label: tr(context, 'verifyOtp'), expand: false, loading: _busy, onPressed: _confirm),
      ],
    );
  }
}
