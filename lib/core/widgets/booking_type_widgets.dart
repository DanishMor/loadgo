import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/logistics.dart';
import '../l10n/l10n.dart';
import '../pricing/fare_calculator.dart';
import 'common.dart';

String bookingTypeLabel(BuildContext context, String type) => tr(context, switch (type) {
      BookingType.rental => 'typeRental',
      BookingType.movers => 'typeMovers',
      _ => 'typeFreight',
    });

/// Freight / hourly rental / packers and movers.
class BookingTypePicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const BookingTypePicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in BookingType.all)
          ChoiceChip(
            key: ValueKey('type_$t'),
            label: Text(bookingTypeLabel(context, t)),
            selected: t == value,
            onSelected: (_) => onChanged(t),
          ),
      ],
    );
  }
}

/// 4 / 8 / 12 hour rental packages.
class RentalHoursPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const RentalHoursPicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final h in rentalHourOptions)
          ChoiceChip(
            key: ValueKey('rentalHours_$h'),
            label: Text(trf(context, 'rentalHoursChip', {'h': h})),
            selected: h == value,
            onSelected: (_) => onChanged(h),
          ),
      ],
    );
  }
}

/// 0..[maxHelpers] helpers (labour) for loading and unloading.
class HelpersStepper extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const HelpersStepper({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.outlined(
          key: const ValueKey('helpersMinus'),
          onPressed: value > 0 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('$value', key: const ValueKey('helpersValue'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ),
        IconButton.outlined(
          key: const ValueKey('helpersPlus'),
          onPressed: value < maxHelpers ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_rounded),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(tr(context, 'helpersHint'), style: const TextStyle(color: AppColors.muted, fontSize: 12))),
      ],
    );
  }
}

/// Items list (one per line), floor, lift and packing for a movers request.
class MoversSection extends StatelessWidget {
  final TextEditingController items;
  final TextEditingController floor;
  final bool hasLift;
  final bool packing;
  final ValueChanged<bool> onLift;
  final ValueChanged<bool> onPacking;

  const MoversSection({
    super.key,
    required this.items,
    required this.floor,
    required this.hasLift,
    required this.packing,
    required this.onLift,
    required this.onPacking,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(tr(context, 'moversItems')),
        TextFormField(
          key: const ValueKey('moversItems'),
          controller: items,
          maxLines: 5,
          decoration: InputDecoration(hintText: tr(context, 'moversItemsHint')),
          validator: (v) {
            final parsed = MoversDetails.parseItems(v ?? '');
            if (parsed == null || parsed.isEmpty) return tr(context, 'moversItemsInvalid');
            return parsed.length > 30 ? tr(context, 'moversItemsInvalid') : null;
          },
        ),
        const SizedBox(height: 14),
        FieldLabel(tr(context, 'moversFloor')),
        TextFormField(
          key: const ValueKey('moversFloor'),
          controller: floor,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(prefixIcon: Icon(Icons.stairs_outlined)),
          validator: (v) {
            final n = int.tryParse(v?.trim() ?? '');
            return (n == null || n < 0 || n > 50) ? tr(context, 'invalidNumber') : null;
          },
        ),
        SwitchListTile(
          key: const ValueKey('moversLift'),
          contentPadding: EdgeInsets.zero,
          title: Text(tr(context, 'moversHasLift')),
          value: hasLift,
          onChanged: onLift,
        ),
        SwitchListTile(
          key: const ValueKey('moversPacking'),
          contentPadding: EdgeInsets.zero,
          title: Text(tr(context, 'moversPacking')),
          value: packing,
          onChanged: onPacking,
        ),
      ],
    );
  }
}
