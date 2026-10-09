import '../errors/error_text.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/audit_service.dart';
import '../services/auth_helpers.dart';
import 'common.dart';

/// A phone number in an admin screen: masked until an admin taps it; the tap
/// writes a `contact_view` line to `audit_events` first (Task 68). If the log
/// line cannot be written the number stays hidden.
class AdminPhoneText extends StatefulWidget {
  final String uid;
  final String phone;
  final String? bookingId;
  final TextStyle? style;

  const AdminPhoneText({super.key, required this.uid, required this.phone, this.bookingId, this.style});

  @override
  State<AdminPhoneText> createState() => _AdminPhoneTextState();
}

class _AdminPhoneTextState extends State<AdminPhoneText> {
  bool _shown = false;
  bool _busy = false;

  Future<void> _reveal() async {
    if (_busy || _shown || widget.phone.isEmpty) return;
    setState(() => _busy = true);
    try {
      await AuditService.record(AuditType.contactView, targetId: widget.uid, bookingId: widget.bookingId, data: {'fields': ['phone']});
      if (mounted) setState(() => _shown = true);
    } catch (error) {
      if (mounted) showSnack(context, errorText(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.phone.isEmpty) return const SizedBox.shrink();
    return InkWell(
      key: ValueKey('adminPhone_${widget.uid}'),
      onTap: _reveal,
      child: Tooltip(
        message: tr(context, 'pcMaskedHint'),
        child: Text(_shown ? widget.phone : maskPhone(widget.phone), style: widget.style),
      ),
    );
  }
}
