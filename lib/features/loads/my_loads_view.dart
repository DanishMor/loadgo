import 'package:flutter/material.dart';

import '../../core/models/load.dart';
import '../../core/services/load_service.dart';
import '../../core/widgets/common.dart';
import '../../main.dart';
import 'load_card.dart';

/// Customer "My Loads" tab: live list of the customer's posted loads.
class MyLoadsView extends StatefulWidget {
  final VoidCallback onPostLoad;

  /// Opens the booking for a matched/closed load (booking id == load id).
  final ValueChanged<String> onOpenBooking;

  const MyLoadsView({super.key, required this.onPostLoad, required this.onOpenBooking});

  @override
  State<MyLoadsView> createState() => _MyLoadsViewState();
}

class _MyLoadsViewState extends State<MyLoadsView> {
  final Stream<List<Load>> _loads = LoadService.watchMine();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(tr(context, 'myLoads'),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.title)),
                ),
                TextButton.icon(
                  onPressed: widget.onPostLoad,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(tr(context, 'postLoad')),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Load>>(
              stream: _loads,
              builder: (context, snap) {
                if (snap.hasError) return StreamErrorText(snap.error);
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final loads = snap.data!;
                if (loads.isEmpty) {
                  return EmptyState(
                    icon: Icons.inventory_2_rounded,
                    title: tr(context, 'noLoadsTitle'),
                    subtitle: tr(context, 'noLoadsSub'),
                    action: SizedBox(
                      width: 220,
                      child: PrimaryButton(label: tr(context, 'postLoad'), icon: Icons.add_rounded, onPressed: widget.onPostLoad),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                  itemCount: loads.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final load = loads[i];
                    return LoadCard(
                      load: load,
                      showStatus: true,
                      action: load.isOpen
                          ? null
                          : SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => widget.onOpenBooking(load.bookingId ?? load.id),
                                icon: const Icon(Icons.local_shipping_rounded),
                                label: Text(tr(context, 'viewBooking')),
                              ),
                            ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
