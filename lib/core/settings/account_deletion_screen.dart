import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../navigation/app_routes.dart';
import '../services/account_deletion_service.dart';
import '../services/auth_helpers.dart';
import '../services/backend.dart';
import '../services/push_service.dart';
import '../widgets/common.dart';

/// Permanent, in-app account deletion (Play Store requirement): explains what
/// goes and what stays, blocks while trips are active, asks for the word
/// DELETE and a fresh phone OTP, then deletes the data and the Auth user.
class AccountDeletionScreen extends StatefulWidget {
  /// Replaceable in tests. Returns true once the user is freshly signed in.
  final Future<bool> Function(BuildContext context)? reauthenticate;

  /// Replaceable in tests. Defaults to deleting the current Auth user.
  final Future<void> Function()? deleteAuthUser;

  /// Runs after a successful deletion; defaults to the signed-out start screen.
  final void Function(BuildContext context)? onDeleted;

  const AccountDeletionScreen({super.key, this.reauthenticate, this.deleteAuthUser, this.onDeleted});

  static const confirmWord = 'DELETE';

  /// Sign-ins newer than this need no new OTP.
  static const freshSignIn = Duration(minutes: 2);

  @override
  State<AccountDeletionScreen> createState() => _AccountDeletionScreenState();
}

class _AccountDeletionScreenState extends State<AccountDeletionScreen> {
  final _word = TextEditingController();
  bool _loading = true;
  bool _working = false;
  bool _restricted = false;
  bool _failed = false;
  int _active = 0;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _word.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final restricted = await AccountDeletionService.isRestricted();
      final active = await AccountDeletionService.activeTripCount();
      if (!mounted) return;
      setState(() {
        _restricted = restricted;
        _active = active;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  bool get _canDelete => !_loading && !_failed && !_restricted && _active == 0 && _word.text.trim() == AccountDeletionScreen.confirmWord;

  Future<bool> _isFresh() async {
    final last = Backend.currentUser?.metadata.lastSignInTime;
    return last != null && DateTime.now().difference(last) < AccountDeletionScreen.freshSignIn;
  }

  Future<void> _delete() async {
    setState(() => _working = true);
    try {
      if (!await _isFresh()) {
        final reauth = widget.reauthenticate ?? (c) => showDialog<bool>(context: c, barrierDismissible: false, builder: (_) => const _ReauthDialog()).then((v) => v == true);
        if (!mounted) return;
        if (!await reauth(context)) {
          if (mounted) setState(() => _working = false);
          return;
        }
      }
      await PushService.unregister();
      await AccountDeletionService.deleteAccount(deleteAuthUser: widget.deleteAuthUser ?? () async => Backend.currentUser!.delete());
      if (!mounted) return;
      showSnack(context, tr(context, 'delAccDone'));
      (widget.onDeleted ?? _toStart)(context);
    } on ActiveTripsException catch (e) {
      if (!mounted) return;
      setState(() {
        _active = e.count;
        _working = false;
      });
    } on AccountRestrictedException {
      if (!mounted) return;
      setState(() {
        _restricted = true;
        _working = false;
      });
    } catch (_) {
      // Data may be partly gone; deleting again finishes the rest.
      if (!mounted) return;
      setState(() => _working = false);
      showSnack(context, tr(context, 'delAccFailed'));
    }
  }

  static void _toStart(BuildContext context) {
    final build = AppRoutes.roleSelection;
    if (build == null) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: build), (_) => false);
  }

  Widget _note(IconData icon, Color color, String text, {Key? key}) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text(text, key: key, style: const TextStyle(height: 1.35))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'deleteAccount'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(tr(context, 'somethingWrong')),
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: _check, child: Text(tr(context, 'retry'))),
                ]))
              : ListView(padding: const EdgeInsets.all(20), children: [
                  Text(tr(context, 'delAccIntro'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 16),
                  _note(Icons.delete_outline_rounded, Colors.redAccent, tr(context, 'delAccDeleted')),
                  _note(Icons.inventory_2_outlined, Colors.blueGrey, tr(context, 'delAccKept')),
                  if (_active > 0)
                    _note(Icons.local_shipping_outlined, Colors.orange, trf(context, 'delAccActive', {'n': _active}), key: const ValueKey('delActive')),
                  if (_restricted) _note(Icons.shield_outlined, Colors.orange, tr(context, 'delAccRestricted'), key: const ValueKey('delRestricted')),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('delWord'),
                    controller: _word,
                    enabled: !_working,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(labelText: tr(context, 'delAccTypeHint'), border: const OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const ValueKey('delConfirm'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, minimumSize: const Size.fromHeight(50)),
                    onPressed: _canDelete && !_working ? _delete : null,
                    child: _working
                        ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                            const SizedBox(width: 10),
                            Flexible(child: Text(tr(context, 'delAccWorking'))),
                          ])
                        : Text(tr(context, 'delAccButton')),
                  ),
                ]),
    );
  }
}

/// Sends a fresh SMS code to the signed-in number and re-authenticates with it.
class _ReauthDialog extends StatefulWidget {
  const _ReauthDialog();

  @override
  State<_ReauthDialog> createState() => _ReauthDialogState();
}

class _ReauthDialogState extends State<_ReauthDialog> {
  final _code = TextEditingController();
  String? _verificationId;
  String? _error;
  bool _busy = false;

  String get _phone => Backend.currentUser?.phoneNumber ?? '';

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _reauth(AuthCredential credential) async {
    try {
      await Backend.currentUser!.reauthenticateWithCredential(credential);
      if (mounted) Navigator.pop(context, true);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = authErrorKey(e.code);
        });
      }
    }
  }

  Future<void> _send() async {
    final digits = _phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) {
      setState(() => _error = 'otpFailed');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await sendPhoneOtp(
      digits.substring(digits.length - 10),
      OtpCallbacks(
        onCodeSent: (id, _) {
          if (mounted) {
            setState(() {
              _verificationId = id;
              _busy = false;
            });
          }
        },
        onError: (key) {
          if (mounted) {
            setState(() {
              _busy = false;
              _error = key;
            });
          }
        },
        onAutoVerified: _reauth,
      ),
    );
  }

  Future<void> _verify() async {
    final id = _verificationId;
    if (id == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    await _reauth(PhoneAuthProvider.credential(verificationId: id, smsCode: _code.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'delAccOtpTitle')),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(trf(context, 'delAccOtpBody', {'phone': maskPhone(_phone)})),
        if (_verificationId != null) ...[
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('delOtp'),
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(border: OutlineInputBorder(), counterText: ''),
          ),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(tr(context, _error!), style: const TextStyle(color: Colors.redAccent))),
      ]),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: Text(tr(context, 'cancel'))),
        FilledButton(
          onPressed: _busy ? null : (_verificationId == null ? _send : _verify),
          child: Text(tr(context, _verificationId == null ? 'delAccSendCode' : 'verifyOtp')),
        ),
      ],
    );
  }
}
