import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/pilot/reuse_survey.dart';
import '../core/services/admin_console_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// Admin > Use-again survey (MASTER-6 Task 7): how many customers and drivers
/// would use the app again after a delivered trip.
class AdminSurveysScreen extends StatefulWidget {
  /// Test hook; defaults to the live read.
  final Future<SurveyStats> Function()? load;
  const AdminSurveysScreen({super.key, this.load});

  @override
  State<AdminSurveysScreen> createState() => _AdminSurveysScreenState();
}

class _AdminSurveysScreenState extends State<AdminSurveysScreen> {
  late Future<SurveyStats> _data = (widget.load ?? AdminConsoleService.surveyStats)();

  void _refresh() {
    final next = (widget.load ?? AdminConsoleService.surveyStats)();
    setState(() {
      _data = next;
    });
  }

  Widget _role(SurveyStats s, String role, String titleKey) {
    final a = s.byRole[role]!;
    return AppCard(
      key: ValueKey('survey_$role'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(context, titleKey), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 4),
        Text(s.total(role) == 0 ? tr(context, 'svNone') : trf(context, 'svLine', {'n': s.total(role), 'p': s.yesPercent(role)!, 'y': a['yes']!, 'm': a['maybe']!, 'x': a['no']!})),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'adminSurveys')), actions: [IconButton(key: const ValueKey('svRefresh'), tooltip: tr(context, 'retry'), onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))]),
      body: FutureBuilder<SurveyStats>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return ErrorState(error: snap.error, onRetry: _refresh);
          final s = snap.data;
          if (s == null) return const Center(child: CircularProgressIndicator());
          return ListView(padding: const EdgeInsets.all(16), children: [
            _role(s, 'customer', 'svRoleCustomer'),
            const SizedBox(height: 8),
            _role(s, 'driver', 'svRoleDriver'),
            const SizedBox(height: 8),
            Text(tr(context, 'svNote'), style: TextStyle(color: AppColors.faint, fontSize: 12)),
          ]);
        },
      ),
    );
  }
}
