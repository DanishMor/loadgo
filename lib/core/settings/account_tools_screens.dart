import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../models/business.dart';
import '../models/fleet.dart';
import '../services/auth_helpers.dart';
import '../services/business_service.dart';
import '../services/data_export_service.dart';
import '../services/fleet_service.dart';
import '../services/phone_change_service.dart';
import '../services/user_service.dart';
import '../widgets/common.dart';
import '../widgets/live_stream.dart';

/// Settings > Linked accounts: the company teams and fleets this login belongs
/// to, and the account's own company profile (A9).
class LinkedAccountsScreen extends StatefulWidget {
  final Stream<List<BusinessMember>>? memberships;
  final Stream<List<FleetMember>>? fleets;
  final Stream<Map<String, dynamic>>? profile;

  const LinkedAccountsScreen({super.key, this.memberships, this.fleets, this.profile});

  @override
  State<LinkedAccountsScreen> createState() => _LinkedAccountsScreenState();
}

class _LinkedAccountsScreenState extends State<LinkedAccountsScreen> {
  late final _memberships = (widget.memberships ?? BusinessService.watchMyMemberships()).asBroadcastStream();
  late final _fleets = (widget.fleets ?? FleetService.watchMyFleets()).asBroadcastStream();
  late final _profile = (widget.profile ?? UserService.watchUser()).asBroadcastStream();

  Widget _row(IconData icon, String text, {Key? key}) => ListTile(key: key, leading: Icon(icon, color: AppColors.primary), title: Text(text));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'linkedAccounts'))),
      body: LiveStream<Map<String, dynamic>>(
        stream: () => _profile,
        builder: (context, profile) => LiveStream<List<BusinessMember>>(
          stream: () => _memberships,
          builder: (context, memberships) => LiveStream<List<FleetMember>>(
            stream: () => _fleets,
            builder: (context, fleets) {
              final own = ((profile['business'] as Map?)?['legalName'] as String?)?.trim() ?? '';
              final rows = <Widget>[
                if (own.isNotEmpty) _row(Icons.business_rounded, trf(context, 'linkedOwnBusiness', {'name': own}), key: const ValueKey('linkedOwn')),
                for (final m in memberships)
                  _row(Icons.groups_rounded, trf(context, 'linkedBooker', {'name': m.ownerName.isEmpty ? m.ownerId : m.ownerName}), key: ValueKey('linkedBiz_${m.id}')),
                for (final f in fleets)
                  _row(Icons.local_shipping_rounded, trf(context, 'linkedFleet', {'name': f.ownerName.isEmpty ? f.ownerId : f.ownerName}), key: ValueKey('linkedFleet_${f.id}')),
              ];
              if (rows.isEmpty) return EmptyState(icon: Icons.link_off_rounded, title: tr(context, 'linkedNone'));
              return ListView(children: rows);
            },
          ),
        ),
      ),
    );
  }
}

/// Settings > Download my data: builds the JSON and lets the person copy it.
class DataExportScreen extends StatefulWidget {
  const DataExportScreen({super.key});

  @override
  State<DataExportScreen> createState() => _DataExportScreenState();
}

class _DataExportScreenState extends State<DataExportScreen> {
  String? _json;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    DataExportService.buildJson().then((j) {
      if (mounted) setState(() => _json = j);
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'dataExport'))),
      body: _failed
          ? EmptyState(icon: Icons.error_outline, title: tr(context, 'somethingWrong'))
          : _json == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Text(tr(context, 'dataExportInfo'), style: TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const ValueKey('exportCopy'),
                    icon: const Icon(Icons.copy_rounded),
                    label: Text(tr(context, 'dataExportCopy')),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _json!));
                      if (context.mounted) showSnack(context, tr(context, 'copied'));
                    },
                  ),
                  const SizedBox(height: 12),
                  SelectableText(_json!, key: const ValueKey('exportJson'), style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                ]),
    );
  }
}

/// Settings > Change mobile number (R3): SMS code to the new number, then the
/// profile phone is updated and admins get a risk signal.
class PhoneChangeScreen extends StatefulWidget {
  const PhoneChangeScreen({super.key});

  @override
  State<PhoneChangeScreen> createState() => _PhoneChangeScreenState();
}

class _PhoneChangeScreenState extends State<PhoneChangeScreen> {
  final _number = TextEditingController();
  final _code = TextEditingController();
  String? _verificationId;
  String? _newPhone;
  bool _busy = false;

  @override
  void dispose() {
    _number.dispose();
    _code.dispose();
    super.dispose();
  }

  void _fail(String key) {
    if (!mounted) return;
    setState(() => _busy = false);
    showSnack(context, tr(context, key));
  }

  Future<void> _done(PhoneAuthCredential c) async {
    try {
      await PhoneChangeService.complete(c, newPhone: _newPhone!);
      if (!mounted) return;
      showSnack(context, tr(context, 'phoneChanged'));
      Navigator.of(context).pop(true);
    } catch (_) {
      _fail('somethingWrong');
    }
  }

  Future<void> _send() async {
    final phone = PhoneChangeService.normalise(_number.text);
    if (phone == null) return _fail('invalidMobile');
    setState(() => _busy = true);
    _newPhone = phone;
    await sendPhoneOtp(
      phone.substring(3),
      OtpCallbacks(
        onCodeSent: (id, _) {
          if (!mounted) return;
          setState(() {
            _verificationId = id;
            _busy = false;
          });
        },
        onError: _fail,
        onAutoVerified: _done,
      ),
    );
  }

  Future<void> _confirm() async {
    final id = _verificationId;
    if (id == null || _code.text.trim().length != 6) return _fail('otpFailed');
    setState(() => _busy = true);
    await _done(PhoneAuthProvider.credential(verificationId: id, smsCode: _code.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'phoneChange'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(tr(context, 'phoneChangeInfo'), style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('newMobile'),
          controller: _number,
          keyboardType: TextInputType.phone,
          enabled: _verificationId == null,
          decoration: InputDecoration(labelText: tr(context, 'newMobile'), prefixText: '+91 '),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
        ),
        const SizedBox(height: 12),
        if (_verificationId == null)
          FilledButton(key: const ValueKey('sendCode'), onPressed: _busy ? null : _send, child: Text(tr(context, 'sendCodeBtn')))
        else ...[
          TextField(
            key: const ValueKey('smsCode'),
            controller: _code,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: tr(context, 'codeLabel')),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          ),
          const SizedBox(height: 12),
          FilledButton(key: const ValueKey('confirmCode'), onPressed: _busy ? null : _confirm, child: Text(tr(context, 'confirmBtn'))),
        ],
      ]),
    );
  }
}
