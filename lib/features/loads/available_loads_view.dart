import 'package:flutter/material.dart';

import '../../core/models/load.dart';
import '../../core/widgets/common.dart';
import '../../main.dart';
import 'accept_load.dart';
import 'load_card.dart';

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

/// Driver "Loads" tab: live list of all open loads.
class AvailableLoadsView extends StatelessWidget {
  final Stream<List<Load>> loads;
  final ValueChanged<String>? onAccepted;

  const AvailableLoadsView({super.key, required this.loads, this.onAccepted});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(tr(context, 'availableLoads'),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.title)),
          ),
          Expanded(
            child: StreamBuilder<List<Load>>(
              stream: loads,
              builder: (context, snap) {
                if (snap.hasError) return StreamErrorText(snap.error);
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final list = snap.data!;
                if (list.isEmpty) {
                  return EmptyState(icon: Icons.inventory_2_rounded, title: tr(context, 'noAvailableLoads'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => LoadCard(
                    key: ValueKey(list[i].id),
                    load: list[i],
                    action: AcceptLoadButton(load: list[i], onAccepted: onAccepted),
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
