import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';
import 'common.dart';
import '../l10n/l10n.dart';

typedef StreamFactory<D> = Stream<D> Function();

/// Translation key for a user-facing explanation of a load failure.
String loadErrorKey(Object? error) {
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' || 'unauthenticated' => 'errorNoAccess',
      'unavailable' ||
      'deadline-exceeded' ||
      'network-request-failed' => 'errorNetwork',
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

  /// When this changes the stream is re-created (e.g. a larger page limit).
  /// The previous data stays on screen until the new stream delivers.
  final Object? resubscribeKey;

  const LiveStream({
    super.key,
    required this.stream,
    required this.builder,
    this.compact = false,
    this.slowAfter = const Duration(seconds: 15),
    this.resubscribeKey,
  });

  @override
  State<LiveStream<D>> createState() => _LiveStreamState<D>();
}

class _LiveStreamState<D> extends State<LiveStream<D>> {
  late Stream<D> _stream;
  Timer? _slowTimer;
  bool _slow = false;
  D? _last;
  bool _keepLast = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(LiveStream<D> old) {
    super.didUpdateWidget(old);
    if (old.resubscribeKey != widget.resubscribeKey) {
      _keepLast = _last != null;
      _subscribe();
    }
  }

  void _subscribe() {
    _stream = widget.stream();
    _slow = false;
    _slowTimer?.cancel();
    _slowTimer = Timer(widget.slowAfter, () {
      if (mounted) setState(() => _slow = true);
    });
  }

  /// Bumped on Retry so the StreamBuilder starts clean (it would keep showing
  /// the old error until the new stream speaks).
  int _attempt = 0;

  void _retry() => setState(() {
        _attempt++;
        _subscribe();
      });

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<D>(
      key: ValueKey(_attempt),
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          debugPrint('LiveStream error: ${snap.error}');
          final offline = !ConnectivityService.online.value;
          return ErrorRetry(
            messageKey: offline ? 'errorOffline' : loadErrorKey(snap.error),
            onRetry: _retry,
            compact: widget.compact,
          );
        }
        if (snap.hasData) {
          _slowTimer?.cancel();
          _last = snap.data as D;
          _keepLast = false;
          return widget.builder(context, _last as D);
        }
        if (_keepLast && _last != null) {
          return widget.builder(context, _last as D);
        }
        // Nothing to show yet: say so plainly if the device is offline.
        return ValueListenableBuilder<bool>(
          valueListenable: ConnectivityService.online,
          builder: (context, online, _) {
            if (!online || _slow) {
              return ErrorRetry(
                messageKey: online ? 'errorSlow' : 'errorOffline',
                onRetry: _retry,
                compact: widget.compact,
              );
            }
            return _spinner();
          },
        );
      },
    );
  }

  Widget _spinner() {
    return widget.compact
        ? const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          )
        : const Center(child: CircularProgressIndicator());
  }
}

/// [LiveStream] for one document that may not exist: the builder gets null
/// when it is missing (a null event counts as data, not as "still loading").
class LiveDoc<V> extends StatelessWidget {
  final Stream<V?> Function() stream;
  final Widget Function(BuildContext context, V? value) builder;
  final bool compact;

  const LiveDoc({super.key, required this.stream, required this.builder, this.compact = false});

  @override
  Widget build(BuildContext context) => LiveStream<(V?,)>(
        stream: () => stream().map((v) => (v,)),
        compact: compact,
        builder: (context, data) => builder(context, data.$1),
      );
}

/// Friendly failure message with a Retry button.
class ErrorRetry extends StatelessWidget {
  final String messageKey;
  final VoidCallback onRetry;
  final bool compact;

  const ErrorRetry({
    super.key,
    required this.messageKey,
    required this.onRetry,
    this.compact = false,
  });

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
            Expanded(
              child: Text(
                tr(context, messageKey),
                style: const TextStyle(color: AppColors.muted),
              ),
            ),
            retry,
          ],
        ),
      );
    }
    return EmptyState(
      icon: Icons.cloud_off_rounded,
      title: tr(context, messageKey),
      action: retry,
    );
  }
}

/// Thin strip shown under the app while the device has no connection; lists
/// keep showing whatever Firestore has cached.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService.online,
      builder: (context, online, _) {
        if (online) return const SizedBox.shrink();
        return Material(
          color: Colors.black87,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.wifi_off_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr(context, 'offlineBanner'),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
