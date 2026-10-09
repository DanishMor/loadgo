import '../errors/error_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_info.dart';
import '../features/features.dart';
import '../l10n/l10n.dart';
import '../models/support_ticket.dart';
import '../services/backend.dart';
import '../services/error_log_service.dart';
import '../services/rate_limit_service.dart';
import '../services/support_service.dart';
import '../widgets/common.dart';
import '../widgets/feature_gate.dart';

/// The kinds of problem a person can report in two taps.
enum ProblemKind { appBroke, slow, wrongInfo, payment, otherPerson, safety, other }

/// What a problem report becomes: a normal support ticket (so admins use the
/// tools they already have). Pure.
class ProblemReport {
  final String category;
  final String priority;
  final String subject;
  final String description;
  const ProblemReport({required this.category, required this.priority, required this.subject, required this.description});

  static const maxText = 500;
  static const _subject = {
    ProblemKind.appBroke: 'App problem: something broke',
    ProblemKind.slow: 'App problem: slow or stuck',
    ProblemKind.wrongInfo: 'Problem: wrong information',
    ProblemKind.payment: 'Problem: payment',
    ProblemKind.otherPerson: 'Problem: the other person',
    ProblemKind.safety: 'Problem: safety',
    ProblemKind.other: 'Problem: other',
  };

  static String categoryOf(ProblemKind k) => switch (k) {
        ProblemKind.payment => TicketCategory.payment,
        ProblemKind.safety => TicketCategory.safety,
        ProblemKind.otherPerson => TicketCategory.bookingIssue,
        _ => TicketCategory.other,
      };

  /// [screen] is where the person was, [lastError] the newest cleaned error
  /// text of this app run (no e-mail, links or long numbers; see
  /// [ErrorLogService.sanitize]).
  static ProblemReport build(
    ProblemKind kind,
    String text, {
    String? screen,
    String? bookingId,
    String? role,
    String? lastError,
    String version = appVersion,
  }) {
    final said = text.trim();
    final cut = said.length > maxText ? said.substring(0, maxText) : said;
    final tech = [
      if (screen != null && screen.isNotEmpty) 'Screen: $screen',
      'App: $version',
      if (role != null && role.isNotEmpty) 'Role: $role',
      if (bookingId != null) 'Booking: $bookingId',
      if (lastError != null && lastError.isNotEmpty) 'Last error: ${lastError.length > 150 ? lastError.substring(0, 150) : lastError}',
    ].join('\n');
    final body = cut.isEmpty ? tech : '$cut\n\n$tech';
    return ProblemReport(
      category: categoryOf(kind),
      priority: kind == ProblemKind.safety ? TicketPriority.urgent : TicketPriority.normal,
      subject: _subject[kind]!,
      description: body.length > 1000 ? body.substring(0, 1000) : body,
    );
  }
}

/// Opens the "report a problem" sheet and sends the ticket. Returns true when sent.
Future<bool> showProblemReportSheet(BuildContext context, {String? screen, String? bookingId, String? role}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (c) => _ProblemSheet(screen: screen, bookingId: bookingId, role: role),
  );
  return sent == true;
}

class _ProblemSheet extends StatefulWidget {
  final String? screen, bookingId, role;
  const _ProblemSheet({this.screen, this.bookingId, this.role});

  @override
  State<_ProblemSheet> createState() => _ProblemSheetState();
}

class _ProblemSheetState extends State<_ProblemSheet> {
  ProblemKind? _kind;
  final _text = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final k = _kind;
    if (k == null) return showSnack(context, tr(context, 'prPickKind'));
    final r = ProblemReport.build(k, _text.text, screen: widget.screen, bookingId: widget.bookingId, role: widget.role, lastError: ErrorLogService.lastError);
    setState(() => _busy = true);
    try {
      await SupportService.create(category: r.category, subject: r.subject, description: r.description, priority: r.priority, bookingId: widget.bookingId);
      if (!mounted) return;
      Navigator.pop(context, true);
      showSnack(context, tr(context, 'prSent'));
    } on RateLimitException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, trf(context, 'rateLimited', {'m': e.minutesLeft}));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, errorText(context, error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(context, 'prTitle'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(tr(context, 'prNote'), style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final k in ProblemKind.values)
              ChoiceChip(key: ValueKey('prKind_${k.name}'), label: Text(tr(context, 'prKind_${k.name}')), selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
          ]),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('prText'),
            controller: _text,
            maxLines: 3,
            inputFormatters: [LengthLimitingTextInputFormatter(ProblemReport.maxText)],
            decoration: InputDecoration(labelText: tr(context, 'prText')),
          ),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: FilledButton(key: const ValueKey('prSend'), onPressed: _busy ? null : _send, child: Text(tr(context, 'prSend')))),
        ]),
      ),
    );
  }
}

/// "Report a problem" button; shown while the feature is on. Needs a signed-in user.
class ReportProblemButton extends StatelessWidget {
  final String? screen, bookingId, role;
  const ReportProblemButton({super.key, this.screen, this.bookingId, this.role});

  @override
  Widget build(BuildContext context) => FeatureGate(
        featureKey: FeatureKey.problemReport,
        child: OutlinedButton.icon(
          key: const ValueKey('reportProblem'),
          onPressed: Backend.uid == null ? null : () => showProblemReportSheet(context, screen: screen, bookingId: bookingId, role: role),
          icon: const Icon(Icons.report_gmailerrorred_rounded),
          label: Text(tr(context, 'prButton')),
        ),
      );
}
