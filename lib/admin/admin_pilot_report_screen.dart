import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/admin/pilot_report.dart';
import '../core/l10n/l10n.dart';
import '../core/services/admin_console_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// Admin > Pilot report (MASTER-6 Task 5): today's or the last seven days'
/// numbers as plain text to paste into WhatsApp.
class AdminPilotReportScreen extends StatefulWidget {
  /// Test hook; defaults to the live counts.
  final Future<PilotReport> Function(bool weekly)? load;
  const AdminPilotReportScreen({super.key, this.load});

  @override
  State<AdminPilotReportScreen> createState() => _AdminPilotReportScreenState();
}

class _AdminPilotReportScreenState extends State<AdminPilotReportScreen> {
  bool _weekly = false;
  late Future<PilotReport> _data = _fetch();

  Future<PilotReport> _fetch() => (widget.load ?? ((w) => AdminConsoleService.pilotReport(weekly: w)))(_weekly);

  void _set(bool weekly) {
    _weekly = weekly;
    final next = _fetch();
    setState(() {
      _data = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    String label(String k) => tr(context, 'pr${k[0].toUpperCase()}${k.substring(1)}');
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'adminPilotReport')),
        actions: [IconButton(key: const ValueKey('prRefresh'), tooltip: tr(context, 'retry'), onPressed: () => _set(_weekly), icon: const Icon(Icons.refresh_rounded))],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 8, children: [
          ChoiceChip(key: const ValueKey('prDay'), label: Text(tr(context, 'prDay')), selected: !_weekly, onSelected: (_) => _set(false)),
          ChoiceChip(key: const ValueKey('prWeek'), label: Text(tr(context, 'prWeek')), selected: _weekly, onSelected: (_) => _set(true)),
        ]),
        const SizedBox(height: 12),
        FutureBuilder<PilotReport>(
          future: _data,
          builder: (context, snap) {
            if (snap.hasError) return ErrorState(error: snap.error, onRetry: () => _set(_weekly));
            final r = snap.data;
            if (r == null) return const Center(child: CircularProgressIndicator());
            final text = r.text(label);
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AppCard(child: SelectableText(text, key: const ValueKey('prText'))),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const ValueKey('prCopy'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'copied'))));
                },
                icon: const Icon(Icons.copy_rounded),
                label: Text(tr(context, 'prCopy')),
              ),
              const SizedBox(height: 8),
              Text(tr(context, 'prFootnote'), style: TextStyle(color: AppColors.faint, fontSize: 12)),
            ]);
          },
        ),
      ]),
    );
  }
}
