import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../services/safety_service.dart';
import '../services/user_service.dart';
import '../widgets/common.dart';
import 'emergency_contacts_screen.dart';
import 'share_trip.dart';
import 'trip_safety_checks.dart';

/// Night prompt, rest reminder and emergency-contact check for the driver on
/// the road (MASTER-6 Task 26). Hidden when there is nothing to say.
class TripSafetyChecksCard extends StatefulWidget {
  final Booking booking;

  /// Test hooks.
  final DateTime Function() now;
  final Future<List<EmergencyContact>> Function()? loadContacts;
  const TripSafetyChecksCard({super.key, required this.booking, this.now = DateTime.now, this.loadContacts});

  @override
  State<TripSafetyChecksCard> createState() => _TripSafetyChecksCardState();
}

class _TripSafetyChecksCardState extends State<TripSafetyChecksCard> {
  List<EmergencyContact>? _contacts;
  DateTime? _lastBreak;

  String get _key => 'last_rest_${widget.booking.id}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await (widget.loadContacts ?? () async => SafetyService.contactsFrom(await UserService.getUser()))();
      if (mounted) setState(() => _contacts = c);
    } catch (_) {}
    try {
      final ms = (await SharedPreferences.getInstance()).getInt(_key);
      if (mounted && ms != null) setState(() => _lastBreak = DateTime.fromMillisecondsSinceEpoch(ms));
    } catch (_) {}
  }

  Future<void> _tookBreak() async {
    final at = widget.now();
    setState(() => _lastBreak = at);
    try {
      await (await SharedPreferences.getInstance()).setInt(_key, at.millisecondsSinceEpoch);
    } catch (_) {}
  }

  Future<void> _editContacts() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const EmergencyContactsScreen()));
    if (mounted) _load();
  }

  Widget _row(String id, IconData icon, Color color, String text, {Widget? action}) => Padding(
        key: ValueKey(id),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(text), ?action])),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    final now = widget.now();
    final rows = <Widget>[];
    final check = _contacts == null ? null : TripSafetyChecks.contacts(_contacts!);
    if (check != null && !check.ok && b.isActive) {
      rows.add(_row('safetyContacts', Icons.contact_phone_outlined, AppColors.warning, check.none ? tr(context, 'tscNoContacts') : trf(context, 'tscBadContacts', {'n': check.invalid}),
          action: TextButton(key: const ValueKey('tscFixContacts'), onPressed: _editContacts, child: Text(tr(context, 'tscFixContacts')))));
    }
    if (TripSafetyChecks.nightPrompt(b.status, now)) {
      rows.add(_row('safetyNight', Icons.nightlight_round, AppColors.primary, tr(context, 'tscNight'), action: ShareTripButton(booking: b)));
    }
    if (TripSafetyChecks.restDue(b, now, _lastBreak)) {
      final h = TripSafetyChecks.hoursDriving(b, now, _lastBreak)!;
      rows.add(_row('safetyRest', Icons.free_breakfast_outlined, AppColors.warning, trf(context, 'tscRest', {'h': h}),
          action: TextButton(key: const ValueKey('tscTookBreak'), onPressed: _tookBreak, child: Text(tr(context, 'tscTookBreak')))));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return AppCard(key: const ValueKey('tripSafetyChecks'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows));
  }
}
