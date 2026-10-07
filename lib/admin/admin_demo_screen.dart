import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/services/demo_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// Admin > Demo data (super admin): create or remove sample users, vehicles,
/// loads and bookings, all flagged `demo: true`.
class AdminDemoScreen extends StatefulWidget {
  const AdminDemoScreen({super.key});

  @override
  State<AdminDemoScreen> createState() => _AdminDemoScreenState();
}

class _AdminDemoScreenState extends State<AdminDemoScreen> {
  late Future<int> _count = DemoService.count();
  bool _busy = false;

  void _refresh() => setState(() {
        _count = DemoService.count();
      });

  void _snack(String key, [int? n]) {
    final text = n == null ? tr(context, key) : trf(context, key, {'n': n});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _confirm(String key) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(tr(c, key)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr(c, 'cancel'))),
            FilledButton(key: const ValueKey('demoConfirm'), onPressed: () => Navigator.pop(c, true), child: Text(tr(c, 'save'))),
          ],
        ),
      ) ??
      false;

  Future<void> _run(String confirmKey, Future<int> Function() job, String doneKey) async {
    if (_busy || !await _confirm(confirmKey)) return;
    setState(() => _busy = true);
    try {
      final n = await job();
      if (mounted) _snack(doneKey, n);
    } on DemoBlockedException {
      if (mounted) _snack('demoBlocked');
    } catch (_) {
      if (mounted) _snack('somethingWrong');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'adminDemo'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(tr(context, 'demoIntro'), style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 16),
        FutureBuilder<int>(
          future: _count,
          builder: (context, snap) {
            if (snap.hasError) return ErrorRetry(messageKey: 'somethingWrong', onRetry: _refresh, compact: true);
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            return AppCard(child: Text(trf(context, 'demoCount', {'n': snap.data!}), key: const ValueKey('demoCount'), style: const TextStyle(fontWeight: FontWeight.w700)));
          },
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey('demoCreate'),
          onPressed: _busy ? null : () => _run('demoConfirmCreate', DemoService.create, 'demoCreated'),
          icon: const Icon(Icons.add_circle_outline),
          label: Text(tr(context, 'demoCreate')),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const ValueKey('demoRemove'),
          onPressed: _busy ? null : () => _run('demoConfirmRemove', DemoService.removeAll, 'demoRemoved'),
          icon: const Icon(Icons.delete_outline),
          label: Text(tr(context, 'demoRemove')),
        ),
      ]),
    );
  }
}
