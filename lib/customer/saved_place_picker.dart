import '../core/errors/error_text.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../core/enterprise/validators.dart';
import '../core/l10n/l10n.dart';
import '../core/models/saved_place.dart';
import '../core/services/saved_place_service.dart';
import '../core/widgets/common.dart';

String placeLabelText(BuildContext context, String label) => tr(context, switch (label) {
      PlaceLabel.office => 'placeOffice',
      PlaceLabel.warehouse => 'placeWarehouse',
      PlaceLabel.factory => 'placeFactory',
      PlaceLabel.port => 'placePort',
      PlaceLabel.cfs => 'placeCfs',
      _ => 'placeHome',
    });

IconData placeLabelIcon(String label) => switch (label) {
      PlaceLabel.office => Icons.business_rounded,
      PlaceLabel.warehouse => Icons.warehouse_rounded,
      PlaceLabel.factory => Icons.factory_rounded,
      PlaceLabel.port => Icons.directions_boat_rounded,
      PlaceLabel.cfs => Icons.inventory_rounded,
      _ => Icons.home_rounded,
    };

/// Text to put in a location field for [p].
String savedPlaceText(SavedPlace p) => p.address.isEmpty ? p.name : '${p.name}, ${p.address}';

/// Sheet listing the customer's saved places; returns the chosen one. Places
/// can be added and deleted from here.
Future<SavedPlace?> pickSavedPlace(BuildContext context) => showModalBottomSheet<SavedPlace>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      builder: (_) => const _SavedPlacesSheet(),
    );

class _SavedPlacesSheet extends StatefulWidget {
  const _SavedPlacesSheet();

  @override
  State<_SavedPlacesSheet> createState() => _SavedPlacesSheetState();
}

class _SavedPlacesSheetState extends State<_SavedPlacesSheet> {
  final Stream<List<SavedPlace>> _places = SavedPlaceService.watchMine();

  Future<void> _add() async {
    final saved = await showDialog<bool>(context: context, builder: (_) => const _AddPlaceDialog());
    if (saved == true && mounted) showSnack(context, tr(context, 'placeSaved'));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr(context, 'savedPlaces'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Flexible(
              child: StreamBuilder<List<SavedPlace>>(
                stream: _places,
                builder: (context, snap) {
                  final places = snap.data ?? const [];
                  if (snap.hasData && places.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(tr(context, 'noSavedPlaces'), style: TextStyle(color: AppColors.muted)),
                    );
                  }
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      for (final p in places)
                        ListTile(
                          key: ValueKey('place_${p.id}'),
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(placeLabelIcon(p.label), color: AppColors.primary),
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('${placeLabelText(context, p.label)} • ${p.address}${p.hasBilling ? '\nGSTIN ${p.gstin}' : ''}'),
                          isThreeLine: p.hasBilling,
                          onTap: () => Navigator.of(context).pop(p),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (p.hasBilling)
                              IconButton(
                                key: ValueKey('copyBilling_${p.id}'),
                                tooltip: tr(context, 'placeCopyBilling'),
                                icon: const Icon(Icons.receipt_long_outlined),
                                onPressed: () async {
                                  await Clipboard.setData(ClipboardData(text: p.billingText()));
                                  if (context.mounted) showSnack(context, tr(context, 'copied'));
                                },
                              ),
                            IconButton(tooltip: tr(context, 'a11yDelete'), icon: const Icon(Icons.delete_outline_rounded), onPressed: () => SavedPlaceService.delete(p.id)),
                          ]),
                        ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('addSavedPlace'),
              onPressed: _add,
              icon: const Icon(Icons.add_location_alt_rounded),
              label: Text(tr(context, 'addSavedPlace')),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddPlaceDialog extends StatefulWidget {
  const _AddPlaceDialog();

  @override
  State<_AddPlaceDialog> createState() => _AddPlaceDialogState();
}

class _AddPlaceDialogState extends State<_AddPlaceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _legalName = TextEditingController();
  final _gstin = TextEditingController();
  String _label = PlaceLabel.warehouse;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _legalName.dispose();
    _gstin.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await SavedPlaceService.add(label: _label, name: _name.text, address: _address.text, legalName: _legalName.text, gstin: _gstin.text);
      if (mounted) Navigator.of(context).pop(true);
    } on TooManyPlacesException {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, tr(context, 'tooManyPlaces'));
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, errorText(context, error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'addSavedPlace')),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _label,
                isExpanded: true,
                items: [
                  for (final l in PlaceLabel.all)
                    DropdownMenuItem(value: l, child: Text(placeLabelText(context, l), overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _label = v ?? _label),
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: const ValueKey('placeName'),
                controller: _name,
                maxLength: 40,
                decoration: InputDecoration(labelText: tr(context, 'placeName'), counterText: ''),
                validator: (v) => (v == null || v.trim().isEmpty) ? tr(context, 'fieldRequired') : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: const ValueKey('placeAddress'),
                controller: _address,
                maxLength: 200,
                maxLines: 2,
                decoration: InputDecoration(labelText: tr(context, 'placeAddress'), counterText: ''),
                validator: (v) => (v == null || v.trim().length < 2) ? tr(context, 'fieldRequired') : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: const ValueKey('placeLegalName'),
                controller: _legalName,
                maxLength: 80,
                decoration: InputDecoration(labelText: tr(context, 'placeLegalName'), counterText: ''),
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: const ValueKey('placeGstin'),
                controller: _gstin,
                maxLength: 15,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: tr(context, 'placeGstin'), counterText: ''),
                validator: (v) => (v == null || v.trim().isEmpty || isValidGstinFormat(v)) ? null : tr(context, 'gstinInvalid'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(tr(context, 'cancel'))),
        FilledButton(onPressed: _saving ? null : _save, child: Text(tr(context, 'save'))),
      ],
    );
  }
}
