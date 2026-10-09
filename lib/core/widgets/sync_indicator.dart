import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/connectivity_service.dart';
import '../services/trip_action_queue.dart';
import 'common.dart';

/// "N updates waiting to send" with a Send now button (MASTER-6 Task 23).
/// Hidden when nothing waits. Sends by itself when the phone gets online.
class SyncIndicator extends StatefulWidget {
  /// Called with the result of every flush (the trip screen shows a message).
  final void Function(FlushResult)? onFlushed;
  const SyncIndicator({super.key, this.onFlushed});

  @override
  State<SyncIndicator> createState() => _SyncIndicatorState();
}

class _SyncIndicatorState extends State<SyncIndicator> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    TripActionQueue.refreshCount();
    ConnectivityService.online.addListener(_onlineChanged);
  }

  @override
  void dispose() {
    ConnectivityService.online.removeListener(_onlineChanged);
    super.dispose();
  }

  void _onlineChanged() {
    if (ConnectivityService.online.value) _send();
  }

  Future<void> _send() async {
    if (_busy) return;
    setState(() => _busy = true);
    final r = await TripActionQueue.flush();
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onFlushed?.call(r);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: TripActionQueue.count,
      builder: (context, n, _) {
        if (n == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppCard(
            key: const ValueKey('syncIndicator'),
            child: Row(children: [
              Icon(Icons.cloud_upload_outlined, color: AppColors.warning),
              const SizedBox(width: 10),
              Expanded(child: Text(trf(context, 'syncWaiting', {'n': n}), key: const ValueKey('syncText'), style: const TextStyle(fontWeight: FontWeight.w700))),
              TextButton(key: const ValueKey('syncNow'), onPressed: _busy ? null : _send, child: Text(tr(context, 'syncNow'))),
            ]),
          ),
        );
      },
    );
  }
}

/// The message for the outcome of a flush: what was sent and what was dropped and why.
void showFlushResult(BuildContext context, FlushResult r) {
  if (r.sent > 0) showSnack(context, trf(context, 'syncSent', {'n': r.sent}));
  if (r.dropped.any((d) => d.why == 'otp')) showSnack(context, tr(context, 'syncOtpDropped'));
  if (r.dropped.any((d) => d.why == 'moved' || d.why == 'gone')) showSnack(context, tr(context, 'syncMovedDropped'));
}
