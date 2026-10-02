import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/common.dart';
import '../../main.dart';

typedef StreamFactory<D> = Stream<D> Function();

/// Translation key for a user-facing explanation of a load failure.
String loadErrorKey(Object? error) {
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' || 'unauthenticated' => 'errorNoAccess',
      'unavailable' || 'deadline-exceeded' || 'network-request-failed' => 'errorNetwork',
      _ => 'errorGeneric',
    };
  }
  if (error is TimeoutException) return 'errorNetwork';
  return 'errorGeneric';
}

/// StreamBuilder with the app's standard states: a spinner while loading, a
/// "taking longer than usual" hint with Retry if nothing arrives within
/// [slowAfter], and a friendly error with Retry instead of raw exceptions.
/// Retry re-subscribes by calling [stream] again.
class LiveStream<D> extends StatefulWidget {
  final StreamFactory<D> stream;
  final Widget Function(BuildContext context, D data) builder;

  /// Inline variant for small sections (e.g. cards on a home screen).
  final bool compact;
  final Duration slowAfter;

  const LiveStream({
    super.key,
    required this.stream,
    required this.builder,
    this.compact = false,
    this.slowAfter = const Duration(seconds: 15),
  });

  @override
  State<LiveStream<D>> createState() => _LiveStreamState<D>();
}

class _LiveStreamState<D> extends State<LiveStream<D>> {
  late Stream<D> _stream;
  Timer? _slowTimer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    _stream = widget.stream();
    _slow = false;
    _slowTimer?.cancel();
    _slowTimer = Timer(widget.slowAfter, () {
      if (mounted) setState(() => _slow = true);
    });
  }

  void _retry() => setState(_subscribe);

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<D>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          debugPrint('LiveStream error: ${snap.error}');
          return ErrorRetry(messageKey: loadErrorKey(snap.error), onRetry: _retry, compact: widget.compact);
        }
        if (snap.hasData) {
          _slowTimer?.cancel();
          return widget.builder(context, snap.data as D);
        }
        if (_slow) return ErrorRetry(messageKey: 'errorSlow', onRetry: _retry, compact: widget.compact);
        return widget.compact
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))),
              )
            : const Center(child: CircularProgressIndicator());
      },
    );
  }
}

/// Friendly failure message with a Retry button.
class ErrorRetry extends StatelessWidget {
  final String messageKey;
  final VoidCallback onRetry;
  final bool compact;

  const ErrorRetry({super.key, required this.messageKey, required this.onRetry, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final retry = OutlinedButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh_rounded),
      label: Text(tr(context, 'retry')),
    );
    if (compact) {
      return AppCard(
        child: Row(
          children: [
            const Icon(Icons.cloud_off_rounded, color: AppColors.faint),
            const SizedBox(width: 12),
            Expanded(child: Text(tr(context, messageKey), style: const TextStyle(color: AppColors.muted))),
            retry,
          ],
        ),
      );
    }
    return EmptyState(icon: Icons.cloud_off_rounded, title: tr(context, messageKey), action: retry);
  }
}
