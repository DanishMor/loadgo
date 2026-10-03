import 'package:flutter/material.dart';

import '../../core/constants/logistics.dart';
import '../../core/models/load.dart';
import '../../core/services/load_service.dart';
import '../../core/widgets/common.dart';
import '../../main.dart';
import '../shared/paged_live_stream.dart';
import 'load_card.dart';

/// Customer "My Loads" tab: live list of the customer's posted loads.
class MyLoadsView extends StatefulWidget {
  final VoidCallback onPostLoad;

  /// Opens the load's current booking.
  final ValueChanged<String> onOpenBooking;

  const MyLoadsView({super.key, required this.onPostLoad, required this.onOpenBooking});

  @override
  State<MyLoadsView> createState() => _MyLoadsViewState();
}

class _MyLoadsViewState extends State<MyLoadsView> {
  Widget? _actionsFor(Load load) {
    final viewBooking = load.bookingId == null
        ? null
        : SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => widget.onOpenBooking(load.bookingId!),
              icon: const Icon(Icons.local_shipping_rounded),
              label: Text(tr(context, 'viewBooking')),
            ),
          );
    if (load.isOpen) return _CancelLoadButton(load: load);
    if (load.status == LoadStatus.matched) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ContactSupportNote(),
          if (viewBooking != null) ...[const SizedBox(height: 10), viewBooking],
        ],
      );
    }
    return viewBooking;
  }

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
            child: PagedLiveStream<Load>(
              stream: LoadService.watchMinePage,
              builder: (context, loads, loadMore) {
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
                  itemCount: loads.length + (loadMore == null ? 0 : 1),
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    if (i == loads.length) return loadMore!;
                    final load = loads[i];
                    return LoadCard(key: ValueKey(load.id), load: load, showStatus: true, action: _actionsFor(load));
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

/// Shown on matched loads, which can no longer be cancelled from the app.
class _ContactSupportNote extends StatelessWidget {
  const _ContactSupportNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFFFF6E5), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(tr(context, 'cannotCancelMatched'), style: const TextStyle(fontSize: 13, color: AppColors.body)),
          ),
          TextButton(
            onPressed: () => showSnack(context, tr(context, 'supportSoon')),
            child: Text(tr(context, 'contactSupport')),
          ),
        ],
      ),
    );
  }
}

class _CancelLoadButton extends StatefulWidget {
  final Load load;
  const _CancelLoadButton({required this.load});

  @override
  State<_CancelLoadButton> createState() => _CancelLoadButtonState();
}

class _CancelLoadButtonState extends State<_CancelLoadButton> {
  bool _busy = false;

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr(dialogContext, 'cancelLoad')),
        content: Text(tr(dialogContext, 'cancelLoadConfirm')),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(tr(dialogContext, 'keepLoad'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(tr(dialogContext, 'cancelLoad')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // The card rebuilds without this button once the load closes, so grab the
    // messenger and messages up front.
    final messenger = ScaffoldMessenger.of(context);
    void snack(String key) =>
        messenger.showSnackBar(SnackBar(content: Text(tr(context, key)), behavior: SnackBarBehavior.floating));
    final cancelled = tr(context, 'loadCancelled');
    setState(() => _busy = true);
    try {
      await LoadService.cancel(widget.load.id);
      messenger.showSnackBar(SnackBar(content: Text(cancelled), behavior: SnackBarBehavior.floating));
    } on LoadNotCancellableException {
      if (mounted) snack('cannotCancelMatched');
    } catch (_) {
      if (mounted) snack('somethingWrong');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _busy ? null : _cancel,
        style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)),
        icon: const Icon(Icons.close_rounded),
        label: Text(tr(context, 'cancelLoad')),
      ),
    );
  }
}
