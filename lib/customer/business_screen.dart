import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/enterprise/validators.dart';
import '../core/l10n/l10n.dart';
import '../core/models/enterprise.dart';
import '../core/services/enterprise_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

String branchTypeLabel(BuildContext context, String type) => tr(context, switch (type) {
      BranchType.factory => 'placeFactory',
      BranchType.port => 'placePort',
      BranchType.cfs => 'placeCfs',
      _ => 'placeWarehouse',
    });

IconData branchTypeIcon(String type) => switch (type) {
      BranchType.factory => Icons.factory_rounded,
      BranchType.port => Icons.directions_boat_rounded,
      BranchType.cfs => Icons.inventory_rounded,
      _ => Icons.warehouse_rounded,
    };

/// Business profile (GSTIN format check, always "Not verified") and branches.
class BusinessScreen extends StatefulWidget {
  const BusinessScreen({super.key});

  @override
  State<BusinessScreen> createState() => _BusinessScreenState();
}

class _BusinessScreenState extends State<BusinessScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _gstin = TextEditingController();
  final _address = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    EnterpriseService.loadBusiness().then((b) {
      if (!mounted) return;
      setState(() {
        _name.text = b.legalName;
        _gstin.text = b.gstin;
        _address.text = b.address;
        _loaded = true;
      });
    }).catchError((_) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _gstin.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    try {
      await EnterpriseService.saveBusiness(BusinessProfile(legalName: _name.text, gstin: _gstin.text, address: _address.text));
      if (mounted) showSnack(context, tr(context, 'businessSaved'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  Future<void> _addBranch() async {
    final result = await showDialog<_BranchInput>(context: context, builder: (_) => const _BranchDialog());
    if (result == null || !mounted) return;
    try {
      final ok = await EnterpriseService.addBranch(type: result.type, name: result.name, address: result.address, city: result.city);
      if (mounted && !ok) showSnack(context, tr(context, 'branchesFull'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'businessProfile'))),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextFormField(
                    key: const ValueKey('bizName'),
                    controller: _name,
                    maxLength: 100,
                    decoration: InputDecoration(labelText: tr(context, 'legalName')),
                  ),
                  TextFormField(
                    key: const ValueKey('bizGstin'),
                    controller: _gstin,
                    maxLength: 15,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: tr(context, 'gstin'),
                      suffixIcon: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Center(
                          widthFactor: 1,
                          child: StatusChip(label: tr(context, 'notVerified'), color: AppColors.warning),
                        ),
                      ),
                    ),
                    validator: (v) => (v ?? '').trim().isEmpty || isValidGstinFormat(v!) ? null : tr(context, 'gstinInvalid'),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(tr(context, 'gstinNote'), style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  ),
                  TextFormField(
                    key: const ValueKey('bizAddress'),
                    controller: _address,
                    maxLength: 200,
                    decoration: InputDecoration(labelText: tr(context, 'branchAddress')),
                  ),
                  FilledButton(key: const ValueKey('bizSave'), onPressed: _save, child: Text(tr(context, 'save'))),
                ]),
              ),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(child: Text(tr(context, 'branches'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
                TextButton.icon(
                  key: const ValueKey('addBranch'),
                  onPressed: _addBranch,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(tr(context, 'addBranch')),
                ),
              ]),
              LiveStream<List<Branch>>(
                stream: EnterpriseService.watchBranches,
                compact: true,
                builder: (context, branches) {
                  if (branches.isEmpty) return Padding(padding: const EdgeInsets.all(12), child: Text(tr(context, 'noBranches')));
                  return Column(children: [
                    for (final b in branches)
                      ListTile(
                        key: ValueKey('branch_${b.id}'),
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(branchTypeIcon(b.type)),
                        title: Text(b.name),
                        subtitle: Text([branchTypeLabel(context, b.type), b.address, b.city].where((e) => e.isNotEmpty).join(' · ')),
                        trailing: IconButton(tooltip: tr(context, 'a11yDelete'), 
                          key: ValueKey('branchDelete_${b.id}'),
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => EnterpriseService.removeBranch(b.id),
                        ),
                      ),
                  ]);
                },
              ),
            ]),
    );
  }
}

class _BranchInput {
  final String type, name, address, city;
  const _BranchInput(this.type, this.name, this.address, this.city);
}

class _BranchDialog extends StatefulWidget {
  const _BranchDialog();

  @override
  State<_BranchDialog> createState() => _BranchDialogState();
}

class _BranchDialogState extends State<_BranchDialog> {
  String _type = BranchType.warehouse;
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _city.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'addBranch')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            isExpanded: true,
            key: const ValueKey('branchType'),
            initialValue: _type,
            items: [for (final t in BranchType.all) DropdownMenuItem(value: t, child: Text(branchTypeLabel(context, t)))],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          TextField(key: const ValueKey('branchName'), controller: _name, decoration: InputDecoration(labelText: tr(context, 'branchName')), inputFormatters: [LengthLimitingTextInputFormatter(100)]),
          TextField(controller: _address, decoration: InputDecoration(labelText: tr(context, 'branchAddress')), inputFormatters: [LengthLimitingTextInputFormatter(100)]),
          TextField(controller: _city, decoration: InputDecoration(labelText: tr(context, 'branchCity')), inputFormatters: [LengthLimitingTextInputFormatter(100)]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr(context, 'cancel'))),
        FilledButton(
          key: const ValueKey('branchSave'),
          onPressed: () {
            if (_name.text.trim().isEmpty) return;
            Navigator.pop(context, _BranchInput(_type, _name.text, _address.text, _city.text));
          },
          child: Text(tr(context, 'save')),
        ),
      ],
    );
  }
}
