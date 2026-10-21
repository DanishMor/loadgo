import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../services/connectivity_service.dart';
import '../services/features_service.dart';
import '../services/user_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/common.dart';
import '../widgets/ds/app_button.dart';
import '../widgets/ds/status_badge.dart';
import 'diagnose.dart';

/// Z1: runs the main list reads of the role once (6 second limit each), says what each one needs, and copies a masked report.
/// It never writes.
class DiagnoseScreen extends StatefulWidget {
  final String? role;

  /// Test hooks.
  final List<(String, Future<Object?> Function())>? probes;
  final Duration timeout;
  final Future<void> Function(String)? copy;
  const DiagnoseScreen({super.key, this.role, this.probes, this.timeout = const Duration(seconds: 6), this.copy});

  @override
  State<DiagnoseScreen> createState() => _DiagnoseScreenState();
}

class _DiagnoseScreenState extends State<DiagnoseScreen> {
  List<ProbeResult>? _results;
  bool _running = false;
  String? _role;

  Future<void> _run() async {
    setState(() => _running = true);
    String? role = widget.role;
    if (widget.probes == null && role == null) {
      try {
        role = (await UserService.getUser())?['role'] as String?;
      } catch (_) {}
    }
    _role = role;
    final probes = widget.probes ?? Diagnose.probesFor(role);
    final r = await Diagnose.runAll(probes, timeout: widget.timeout, online: ConnectivityService.online.value);
    if (!mounted) return;
    setState(() {
      _results = r;
      _running = false;
    });
  }

  Future<void> _copy() async {
    final text = Diagnose.report(
      results: _results ?? const [],
      features: FeaturesService.current,
      online: ConnectivityService.online.value,
      platform: defaultTargetPlatform.name,
      role: _role ?? widget.role,
    );
    await (widget.copy ?? (t) => Clipboard.setData(ClipboardData(text: t)))(text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'dgCopied')), behavior: SnackBarBehavior.floating));
  }

  StatusTone _tone(ProbeStatus s) => s == ProbeStatus.ok ? StatusTone.success : (s == ProbeStatus.other ? StatusTone.danger : StatusTone.attention);

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background, scrolledUnderElevation: 0, title: Text(tr(context, 'dgTitle'), style: DsStyle.w700)),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 30), children: [
          Text(tr(context, 'dgIntro'), style: DsStyle.inherit.copyWith(color: AppColors.muted)),
          const SizedBox(height: 12),
          AppButton(key: const ValueKey('dgRun'), label: tr(context, _running ? 'dgRunning' : 'dgRun'), loading: _running, expand: true, onPressed: _running ? null : _run),
          const SizedBox(height: 12),
          if (results != null) ...[
            for (final r in results)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  key: ValueKey('dgRow_${r.name}'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(r.name, style: DsStyle.t16w700)),
                      const SizedBox(width: 8),
                      Flexible(child: StatusBadge(label: r.status.code ?? 'OK', tone: _tone(r.status), showIcon: false)),
                    ]),
                    const SizedBox(height: 4),
                    Text(tr(context, r.status.messageKey), style: DsStyle.t12w400.copyWith(color: AppColors.muted)),
                    if (r.detail.isNotEmpty) Text(r.detail, style: DsStyle.t12w400.copyWith(color: AppColors.faint)),
                    if (r.consoleLink != null) SelectableText(r.consoleLink!, key: ValueKey('dgLink_${r.name}'), style: DsStyle.t12w400),
                  ]),
                ),
              ),
            AppButton(key: const ValueKey('dgCopy'), label: tr(context, 'dgCopy'), kind: AppButtonKind.secondary, icon: Icons.copy_rounded, expand: true, onPressed: _copy),
          ],
        ]),
      ),
    );
  }
}
