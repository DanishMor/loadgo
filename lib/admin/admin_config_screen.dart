import '../core/admin/config_schema.dart';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/announcement/announcement.dart';
import '../core/widgets/once.dart';
import '../core/l10n/l10n.dart';
import '../core/models/vehicle_type.dart';
import '../core/risk/risk_config.dart';
import '../core/services/admin_console_service.dart';
import '../core/services/pricing_service.dart';
import '../core/services/vehicle_type_service.dart';
import '../core/widgets/common.dart';

/// Edit `config/pricing` and `config/vehicle_types` as JSON. Rules let only
/// admins write; invalid JSON is refused here before anything is sent.
class AdminConfigScreen extends StatelessWidget {
  const AdminConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void open(String docId, String titleKey) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConfigEditorScreen(docId: docId, titleKey: titleKey)));
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'adminConfig'))),
      body: ListView(children: [
        ListTile(
          key: const ValueKey('editPricing'),
          title: Text(tr(context, 'adminPricing')),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => open('pricing', 'adminPricing'),
        ),
        ListTile(
          key: const ValueKey('editVehicleTypes'),
          title: Text(tr(context, 'adminVehicleTypes')),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => open('vehicle_types', 'adminVehicleTypes'),
        ),
        ListTile(
          key: const ValueKey('editRisk'),
          title: Text(tr(context, 'adminRiskConfig')),
          subtitle: Text(tr(context, 'adminRiskConfigSub')),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => open('risk', 'adminRiskConfig'),
        ),
        ListTile(
          key: const ValueKey('editSupport'),
          title: Text(tr(context, 'adminSupportConfig')),
          subtitle: Text(tr(context, 'adminSupportConfigSub')),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => open('support', 'adminSupportConfig'),
        ),
        ListTile(
          key: const ValueKey('editAnnouncement'),
          title: Text(tr(context, 'adminAnnouncement')),
          subtitle: Text(tr(context, 'adminAnnouncementSub')),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => open('announcement', 'adminAnnouncement'),
        ),
        ListTile(
          key: const ValueKey('backfillGeohash'),
          title: Text(tr(context, 'adminBackfillGeohash')),
          subtitle: Text(tr(context, 'adminBackfillGeohashSub')),
          trailing: const Icon(Icons.sync_rounded),
          onTap: () async {
            final n = await AdminConsoleService.backfillPickupGeohash();
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(trf(context, 'adminBackfilled', {'n': n}))));
          },
        ),
      ]),
    );
  }
}

class ConfigEditorScreen extends StatefulWidget {
  final String docId;
  final String titleKey;
  const ConfigEditorScreen({super.key, required this.docId, required this.titleKey});

  @override
  State<ConfigEditorScreen> createState() => _ConfigEditorScreenState();
}

class _ConfigEditorScreenState extends State<ConfigEditorScreen> {
  final _once = Once();
  final _text = TextEditingController();
  bool _loaded = false;

  /// The version on screen when it was loaded (null: no saved document yet); the diff and the kind check use it.
  Map<String, dynamic>? _saved;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Object? _plain(Object? v) => switch (v) {
        Timestamp t => t.toDate().toIso8601String(),
        Map m => {for (final e in m.entries) e.key.toString(): _plain(e.value)},
        List l => [for (final e in l) _plain(e)],
        _ => v,
      };

  Future<void> _load() async {
    var data = await AdminConsoleService.readConfig(widget.docId);
    if (data != null) _saved = (_plain(Map<String, dynamic>.of(data)..remove('updatedAt')) as Map).cast<String, dynamic>();
    // No document yet: start from what the app currently uses.
    data ??= switch (widget.docId) {
      'pricing' => PricingService.config.toMap(),
      'risk' => RiskConfigStore.current.toMap(),
      'support' => {'phone': '', 'hours': ''},
      'announcement' => {'id': 'notice-1', 'text': '', 'level': 'info', 'until': '', 'roles': <String>[]},
      _ => {'types': [for (final VehicleTypeInfo t in VehicleTypeService.notifier.value) t.toMap()]},
    };
    data = Map<String, dynamic>.of(data)..remove('updatedAt');
    if (!mounted) return;
    setState(() {
      _text.text = const JsonEncoder.withIndent('  ').convert(_plain(data));
      _loaded = true;
    });
  }

  Future<void> _save() async {
    final Object? parsed;
    try {
      parsed = jsonDecode(_text.text);
    } catch (_) {
      showSnack(context, tr(context, 'adminConfigInvalid'));
      return;
    }
    if (parsed is! Map<String, dynamic>) {
      showSnack(context, tr(context, 'adminConfigInvalid'));
      return;
    }
    final issues = ConfigSchema.validate(widget.docId, parsed, before: _saved);
    if (issues.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(tr(c, 'cfgProblems')),
          content: SingleChildScrollView(
            key: const ValueKey('cfgIssues'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final i in issues.take(12)) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('${i.path.isEmpty ? '' : '${i.path}: '}${tr(c, i.messageKey)}')),
              if (issues.length > 12) Text(trf(c, 'cfgMore', {'n': issues.length - 12})),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(tr(c, 'wlGotIt')))],
        ),
      );
      return;
    }
    final changes = ConfigSchema.diff(_saved, parsed);
    if (changes.isEmpty) {
      showSnack(context, tr(context, 'cfgNoChange'));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(trf(c, 'cfgReview', {'n': changes.length})),
        content: SingleChildScrollView(
          key: const ValueKey('cfgDiff'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final ch in changes.take(20))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(ch.path, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${ch.before ?? tr(c, 'cfgAdded')}  →  ${ch.after ?? tr(c, 'cfgRemoved')}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                ]),
              ),
            if (changes.length > 20) Text(trf(c, 'cfgMore', {'n': changes.length - 20})),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr(c, 'cancel'))),
          FilledButton(key: const ValueKey('cfgConfirm'), onPressed: () => Navigator.pop(c, true), child: Text(tr(c, 'cfgConfirm'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await AdminConsoleService.writeConfig(widget.docId, parsed);
      _saved = (_plain(parsed) as Map).cast<String, dynamic>();
      if (widget.docId == 'pricing') await PricingService.refresh();
      if (widget.docId == 'vehicle_types') await VehicleTypeService.refresh();
      if (widget.docId == 'risk') await RiskConfigStore.refresh();
      if (widget.docId == 'announcement') await AnnouncementService.refresh(force: true);
      if (mounted) showSnack(context, tr(context, 'adminConfigSaved'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  Future<void> _history() async {
    final List<ConfigVersion> versions;
    try {
      versions = await AdminConsoleService.configHistory(widget.docId);
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
      return;
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<ConfigVersion>(
      context: context,
      builder: (c) => SafeArea(
        child: versions.isEmpty
            ? Padding(padding: const EdgeInsets.all(24), child: Text(tr(c, 'cfgHistoryEmpty'), key: const ValueKey('cfgHistoryEmpty')))
            : ListView(shrinkWrap: true, children: [
                Padding(padding: const EdgeInsets.all(16), child: Text(tr(c, 'cfgHistory'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                for (final v in versions)
                  ListTile(
                    key: ValueKey('cfgVersion_${v.id}'),
                    title: Text(v.at == null ? v.id : formatDateTime(v.at!)),
                    subtitle: Text('${v.by} · ${ConfigSchema.diff(_saved, v.data).length}'),
                    onTap: () => Navigator.pop(c, v),
                  ),
              ]),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _text.text = const JsonEncoder.withIndent('  ').convert(picked.data));
    showSnack(context, tr(context, 'cfgLoaded'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, widget.titleKey)), actions: [IconButton(key: const ValueKey('cfgHistoryButton'), tooltip: tr(context, 'cfgHistory'), icon: const Icon(Icons.history_rounded), onPressed: _loaded ? _history : null)]),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('configJson'),
                    controller: _text,
                    maxLines: null,
                    expands: true,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    decoration: const InputDecoration(border: OutlineInputBorder()), inputFormatters: [LengthLimitingTextInputFormatter(20000)]),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('saveConfig'),
                    onPressed: () => _once.run(_save),
                    child: Text(tr(context, 'adminSaveConfig')),
                  ),
                ),
              ]),
            ),
    );
  }
}
