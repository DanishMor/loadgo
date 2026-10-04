import 'package:flutter/material.dart';

import '../core/enterprise/validators.dart';
import '../core/l10n/l10n.dart';
import '../core/models/enterprise.dart';
import '../core/services/enterprise_service.dart';
import 'business_screen.dart';
import 'trade_hub_picker.dart';
import '../core/constants/ports.dart';

/// Optional "Import / export" block of the post-load form: container and
/// seal numbers, a port/ICD/CFS picker for pickup or drop, and the branch
/// the load starts from.
class TradeDetailsSection extends StatelessWidget {
  final TextEditingController container;
  final TextEditingController seal;
  final String? branchId;
  final ValueChanged<Branch?> onBranch;
  final void Function(TradeHub hub, {required bool asPickup}) onHub;

  const TradeDetailsSection({
    super.key,
    required this.container,
    required this.seal,
    required this.branchId,
    required this.onBranch,
    required this.onHub,
  });

  Future<void> _pick(BuildContext context, {required bool asPickup}) async {
    final h = await pickTradeHub(context);
    if (h != null) onHub(h, asPickup: asPickup);
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: const ValueKey('tradeDetails'),
      tilePadding: EdgeInsets.zero,
      leading: const Icon(Icons.directions_boat_outlined),
      title: Text(tr(context, 'tradeDetails')),
      children: [
        TextFormField(
          key: const ValueKey('containerNumber'),
          controller: container,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: tr(context, 'containerNumber')),
          validator: (v) => (v ?? '').trim().isEmpty || isValidContainerNumber(normaliseContainer(v!)) ? null : tr(context, 'containerInvalid'),
        ),
        TextFormField(
          key: const ValueKey('sealNumberField'),
          controller: seal,
          decoration: InputDecoration(labelText: tr(context, 'sealNumber')),
          validator: (v) => (v ?? '').trim().isEmpty || isValidSealNumber(v!) ? null : tr(context, 'sealInvalid'),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(
            key: const ValueKey('hubAsPickup'),
            icon: const Icon(Icons.directions_boat_rounded, size: 18),
            label: Text('${tr(context, 'pickPortIcd')} → ${tr(context, 'useAsPickup')}'),
            onPressed: () => _pick(context, asPickup: true),
          ),
          OutlinedButton.icon(
            key: const ValueKey('hubAsDrop'),
            icon: const Icon(Icons.directions_boat_rounded, size: 18),
            label: Text('${tr(context, 'pickPortIcd')} → ${tr(context, 'useAsDrop')}'),
            onPressed: () => _pick(context, asPickup: false),
          ),
        ]),
        StreamBuilder<List<Branch>>(
          stream: EnterpriseService.watchBranches(),
          builder: (context, snap) {
            final branches = snap.data ?? const <Branch>[];
            if (branches.isEmpty) return const SizedBox.shrink();
            return DropdownButtonFormField<String?>(
              key: const ValueKey('fromBranch'),
              initialValue: branches.any((b) => b.id == branchId) ? branchId : null,
              decoration: InputDecoration(labelText: tr(context, 'fromBranch')),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('–')),
                for (final b in branches)
                  DropdownMenuItem<String?>(value: b.id, child: Text('${b.name} (${branchTypeLabel(context, b.type)})')),
              ],
              onChanged: (id) => onBranch(id == null ? null : branches.firstWhere((b) => b.id == id)),
            );
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
