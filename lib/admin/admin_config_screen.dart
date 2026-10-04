import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/vehicle_type.dart';
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
  final _text = TextEditingController();
  bool _loaded = false;

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
    // No document yet: start from what the app currently uses.
    data ??= widget.docId == 'pricing'
        ? PricingService.config.toMap()
        : {'types': [for (final VehicleTypeInfo t in VehicleTypeService.notifier.value) t.toMap()]};
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
    try {
      await AdminConsoleService.writeConfig(widget.docId, parsed);
      if (widget.docId == 'pricing') await PricingService.refresh();
      if (widget.docId == 'vehicle_types') await VehicleTypeService.refresh();
      if (mounted) showSnack(context, tr(context, 'adminConfigSaved'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, widget.titleKey))),
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
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('saveConfig'),
                    onPressed: _save,
                    child: Text(tr(context, 'adminSaveConfig')),
                  ),
                ),
              ]),
            ),
    );
  }
}
