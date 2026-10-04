import 'package:flutter/material.dart';

import '../../core/models/load.dart';
import '../../core/models/load_filter.dart';
import '../../core/widgets/common.dart';
import '../../main.dart';
import '../../core/widgets/paged_live_stream.dart';
import 'accept_load.dart';
import 'load_card.dart';
import '../../core/services/vehicle_type_service.dart';
import '../../core/widgets/logistics_labels.dart';

/// Accept button wired to the full accept flow, with its own busy state.
class AcceptLoadButton extends StatefulWidget {
  final Load load;
  final ValueChanged<String>? onAccepted;

  const AcceptLoadButton({super.key, required this.load, this.onAccepted});

  @override
  State<AcceptLoadButton> createState() => _AcceptLoadButtonState();
}

class _AcceptLoadButtonState extends State<AcceptLoadButton> {
  bool _busy = false;

  Future<void> _accept() async {
    final bookingId = await acceptLoadFlow(
      context,
      widget.load,
      onBusy: (busy) {
        if (mounted) setState(() => _busy = busy);
      },
    );
    if (bookingId != null) widget.onAccepted?.call(bookingId);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: FilledButton.icon(
        onPressed: _busy ? null : _accept,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.check_circle_outline_rounded),
        label: Text(tr(context, 'accept'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// Driver "Loads" tab: live list of open loads with pickup search and
/// vehicle type / minimum budget filters.
class AvailableLoadsView extends StatefulWidget {
  final PagedStreamFactory<Load> loads;
  final ValueChanged<String>? onAccepted;

  const AvailableLoadsView({super.key, required this.loads, this.onAccepted});

  @override
  State<AvailableLoadsView> createState() => _AvailableLoadsViewState();
}

class _AvailableLoadsViewState extends State<AvailableLoadsView> {
  final _searchCtrl = TextEditingController();
  LoadFilter _filter = LoadFilter.none;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _clearAll() {
    _searchCtrl.clear();
    setState(() => _filter = LoadFilter.none);
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<LoadFilter>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (_) => _FilterSheet(initial: _filter),
    );
    if (result != null && mounted) setState(() => _filter = result.copyWith(pickupQuery: _searchCtrl.text));
  }

  Widget _activeChips() {
    final chips = <Widget>[
      if (_filter.vehicleType != null)
        InputChip(
          label: Text(_filter.vehicleType!),
          onDeleted: () => setState(() => _filter = _filter.copyWith(vehicleType: () => null)),
        ),
      if (_filter.minBudget != null)
        InputChip(
          label: Text('≥ ${formatRupees(_filter.minBudget!)}'),
          onDeleted: () => setState(() => _filter = _filter.copyWith(minBudget: () => null)),
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Wrap(spacing: 8, runSpacing: 4, children: chips),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _filter.sheetFilterCount;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(tr(context, 'availableLoads'),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.title)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    textInputAction: TextInputAction.search,
                    onChanged: (v) => setState(() => _filter = _filter.copyWith(pickupQuery: v)),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: tr(context, 'searchPickup'),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: tr(context, 'filters'),
                  onPressed: _openFilters,
                  icon: Badge(
                    isLabelVisible: count > 0,
                    label: Text('$count'),
                    child: const Icon(Icons.tune_rounded),
                  ),
                ),
              ],
            ),
          ),
          _activeChips(),
          const SizedBox(height: 8),
          Expanded(
            child: PagedLiveStream<Load>(
              stream: widget.loads,
              builder: (context, all, loadMore) {
                final list = _filter.apply(all);
                if (all.isEmpty) {
                  return EmptyState(icon: Icons.inventory_2_rounded, title: tr(context, 'noAvailableLoads'));
                }
                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.filter_alt_off_rounded,
                    title: tr(context, 'noLoadsMatch'),
                    action: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton(onPressed: _clearAll, child: Text(tr(context, 'clearFilters'))),
                        ?loadMore,
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                  itemCount: list.length + (loadMore == null ? 0 : 1),
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => i == list.length
                      ? loadMore!
                      : LoadCard(
                          key: ValueKey(list[i].id),
                          load: list[i],
                          action: AcceptLoadButton(load: list[i], onAccepted: widget.onAccepted),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet for vehicle type and minimum budget. Pops the new filter.
class _FilterSheet extends StatefulWidget {
  final LoadFilter initial;
  const _FilterSheet({required this.initial});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String? _type = widget.initial.vehicleType;
  late final _budgetCtrl =
      TextEditingController(text: widget.initial.minBudget == null ? '' : formatNum(widget.initial.minBudget!));

  @override
  void dispose() {
    _budgetCtrl.dispose();
    super.dispose();
  }

  void _apply() {
    final budget = num.tryParse(_budgetCtrl.text.trim());
    Navigator.of(context).pop(widget.initial.copyWith(
      vehicleType: () => _type,
      minBudget: () => (budget == null || budget <= 0) ? null : budget,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(context, 'filters'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            FieldLabel(tr(context, 'vehicleType')),
            DropdownButtonFormField<String?>(
              key: const ValueKey('vehicleTypeFilter'),
              initialValue: _type,
              items: [
                DropdownMenuItem(value: null, child: Text(tr(context, 'allTypes'))),
                for (final t in VehicleTypeService.ids) DropdownMenuItem(value: t, child: Text(vehicleTypeLabel(context, t))),
              ],
              onChanged: (v) => setState(() => _type = v),
            ),
            const SizedBox(height: 16),
            FieldLabel(tr(context, 'minBudget')),
            TextField(
              key: const ValueKey('minBudgetFilter'),
              controller: _budgetCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(prefixIcon: const Icon(Icons.currency_rupee_rounded), hintText: tr(context, 'anyBudget')),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(widget.initial.copyWith(vehicleType: () => null, minBudget: () => null)),
                    child: Text(tr(context, 'clearFilters')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: FilledButton(onPressed: _apply, child: Text(tr(context, 'applyFilters')))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
