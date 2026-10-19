
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/breadcrumbs.dart';
import '../theme/app_theme.dart';

/// Part 5 (H16): what the person sees when the app cannot start at all (Firebase did not initialise: no network on
/// first launch, a broken install). One calm sentence, one button. It needs nothing from Firebase, a service or a
/// saved setting, so it cannot fail for the same reason.
class StartupFailedApp extends StatelessWidget {
  final VoidCallback onRetry;

  const StartupFailedApp({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(Brightness.light),
        darkTheme: AppTheme.build(Brightness.dark),
        home: _Body(onRetry: onRetry),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final VoidCallback onRetry;

  const _Body({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final rtl = LanguageScope.of(context).textDirection;
    return Directionality(
      textDirection: rtl,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_rounded, size: 48, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  Text(tr(context, 'startFailedTitle'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(tr(context, 'startFailedBody'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 24),
                  FilledButton(key: const ValueKey('startRetry'), onPressed: onRetry, child: Text(tr(context, 'startRetry'))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Part 5 (H16): a start-up step that may fail without taking the app down. Returns the result, or null when the
/// step threw or took longer than [timeout]. The name of the step is logged (cleaned), never its data.
class StartupGuard {
  StartupGuard._();

  /// Names of the steps that failed in this run, for the health screen and tests.
  static final List<String> failed = [];

  static Future<R?> step<R>(String name, Future<R> Function() run, {Duration timeout = const Duration(seconds: 15)}) async {
    try {
      return await Future<R>.sync(run).timeout(timeout);
    } catch (e) {
      failed.add(name);
      debugPrint('Start-up step "$name" failed: ${Redactor.safe(e)}');
      return null;
    }
  }

  @visibleForTesting
  static void reset() => failed.clear();
}
