import 'package:flutter/material.dart';

import '../errors/friendly_error.dart';
import '../services/crash_service.dart';
import 'live_stream.dart';

/// A safety net for one screen (F10). If [builder] throws while turning data
/// into widgets (a field of the wrong type, an old document, a number that is
/// too big), the person sees a calm sentence with a Retry button and never the
/// raw exception. The error itself goes to the (cleaned) error log.
///
/// It catches what [builder] throws. A widget deeper in the tree that fails in
/// its own build is covered by the app's friendly error widget in release.
class ErrorBoundary extends StatefulWidget {
  final WidgetBuilder builder;

  /// Called when the person taps Retry (e.g. to re-subscribe), before rebuilding.
  final VoidCallback? onRetry;
  final bool compact;

  const ErrorBoundary({super.key, required this.builder, this.onRetry, this.compact = false});

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  Object? _error;

  @override
  Widget build(BuildContext context) {
    if (_error == null) {
      try {
        return widget.builder(context);
      } catch (e, st) {
        CrashService.record(e, st);
        _error = e;
      }
    }
    return ErrorRetry(
      key: const ValueKey('errorBoundary'),
      messageKey: FriendlyError.of(_error),
      compact: widget.compact,
      onRetry: () {
        widget.onRetry?.call();
        setState(() => _error = null);
      },
    );
  }
}
