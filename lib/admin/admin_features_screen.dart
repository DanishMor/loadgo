import '../core/errors/error_text.dart';
import 'package:flutter/material.dart';

import '../core/features/features.dart';
import '../core/l10n/l10n.dart';
import '../core/services/features_service.dart';
import '../core/widgets/common.dart';

/// Admin > Features (super admin): pilot mode and one switch per feature
/// (Default / On / Off). Saved to `config/features` and audited.
class AdminFeaturesScreen extends StatefulWidget {
  const AdminFeaturesScreen({super.key});

  @override
  State<AdminFeaturesScreen> createState() => _AdminFeaturesScreenState();
}

class _AdminFeaturesScreenState extends State<AdminFeaturesScreen> {
  late Features _f = FeaturesService.current;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    FeaturesService.refresh(force: true).then((_) {
      if (mounted) {
        setState(() {
          _f = FeaturesService.current;
          _loading = false;
        });
      }
    });
  }

  Future<void> _save(Features next) async {
    final before = _f;
    setState(() {
      _f = next;
      _saving = true;
    });
    try {
      await FeaturesService.save(next);
      if (mounted) showSnack(context, tr(context, 'featSaved'));
    } catch (error) {
      if (mounted) {
        setState(() => _f = before);
        showSnack(context, errorText(context, error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'adminFeatures'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              SwitchListTile(
                key: const ValueKey('featPilot'),
                contentPadding: EdgeInsets.zero,
                title: Text(tr(context, 'featPilotMode'), style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(tr(context, 'featPilotNote')),
                value: _f.pilotMode,
                onChanged: _saving ? null : (v) => _save(_f.withPilot(v)),
              ),
              const Divider(),
              for (final spec in Features.registry)
                Padding(
                  key: ValueKey('feat_${spec.key}'),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(tr(context, 'feat_${spec.key}'), style: const TextStyle(fontWeight: FontWeight.w700))),
                      StatusChip(
                        label: _f.isOn(spec.key) ? tr(context, 'featOn') : tr(context, 'featOff'),
                        color: _f.isOn(spec.key) ? AppColors.success : AppColors.muted,
                      ),
                    ]),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(tr(context, 'featHelp_${spec.key}'), key: ValueKey('featHelp_${spec.key}'), style: TextStyle(fontSize: 12, color: AppColors.muted)),
                    ),
                    const SizedBox(height: 6),
                    SegmentedButton<int>(
                      key: ValueKey('featMode_${spec.key}'),
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: 0, label: Text(tr(context, 'featDefault'))),
                        ButtonSegment(value: 1, label: Text(tr(context, 'featOn'))),
                        ButtonSegment(value: 2, label: Text(tr(context, 'featOff'))),
                      ],
                      selected: {_f.explicit(spec.key) == null ? 0 : (_f.explicit(spec.key)! ? 1 : 2)},
                      onSelectionChanged: _saving ? null : (s) => _save(_f.withFlag(spec.key, s.first == 0 ? null : s.first == 1)),
                    ),
                  ]),
                ),
            ]),
    );
  }
}
