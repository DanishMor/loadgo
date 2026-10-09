import 'core/app_info.dart';
import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import 'admin/admin_entry.dart';
import 'auth/role_selection_screen.dart';
import 'auth/splash_screen.dart';
import 'core/errors/friendly_error_widget.dart';
import 'core/l10n/l10n.dart';
import 'core/navigation/app_routes.dart';
import 'core/navigation/deep_links.dart';
import 'core/permissions/permission_rationale.dart';
import 'core/services/app_config.dart';
import 'core/services/app_control_service.dart';
import 'core/services/crash_service.dart';
import 'core/services/device_service.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/language_store.dart';
import 'core/services/backend.dart';
import 'core/services/push_service.dart';
import 'core/services/session_watcher.dart';
import 'core/settings/simple_mode.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_control_gate.dart';
import 'core/widgets/live_stream.dart' show OfflineBanner;
import 'firebase_options.dart';
import 'route_hooks.dart';

/// Lets code outside a screen (the session watcher) reach the navigator.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppRoutes.roleSelection = (_) => const RoleSelectionScreen();
  AppRoutes.adminEntry = (_) => const AdminEntryTile();
  registerRouteHooks();
  // In a release build a widget that fails to build shows a calm sentence, not the framework's error box.
  if (!kDebugMode) ErrorWidget.builder = friendlyErrorWidget;
  // Log uncaught async errors (e.g. a dropped network call) instead of
  // letting them take the app down; screens show their own retry UI.
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
    return true;
  };
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await CrashService.init();
  Backend.enableOfflinePersistence();
  AppControlService.refresh();
  // The local settings do not depend on each other: read them together so the
  // first screen is not held up by four reads in a row (MASTER-5 Task 14).
  final results = await Future.wait<Object?>([
    LanguageStore.loadLocal(),
    ConnectivityService.start(),
    ThemeStore.load(),
    SimpleMode.load(),
    LowEndMode.load(),
  ]);
  applyLanguageName(results[0] as String?);
  // Register for push whenever a user is signed in (also after app restarts).
  String? configUid;
  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user != null) {
      // The system prompt only follows the explanation (Settings > Phone alerts).
      PermissionRationale.seen(RationaleKind.notifications).then((seen) {
        if (seen) PushService.register();
      });
      AppControlService.refresh();
      DeviceService.syncClock().ignore();
      // Another account needs its own settings; the same one reuses the cache.
      refreshAppConfig(force: user.uid != configUid);
      configUid = user.uid;
    }
  });
  // An expired or revoked session takes the person back to the first screen.
  SessionWatcher(
    FirebaseAuth.instance.authStateChanges().map((u) => u != null),
    onExpired: () {
      DeepLinks.pendingLoadId.value = null; // a link meant for the old session
      final nav = appNavigatorKey.currentState;
      final build = AppRoutes.roleSelection;
      if (nav == null || build == null) return;
      nav.pushAndRemoveUntil(MaterialPageRoute(builder: build), (route) => false);
      final ctx = appNavigatorKey.currentContext;
      if (ctx != null) ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(content: Text(tr(ctx, 'errorSession'))));
    },
  );
  DeepLinks.start();
  runApp(const LoadGoApp());
}

// ============================================================
// APP
// ============================================================

class LoadGoApp extends StatelessWidget {
  const LoadGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return LanguageScope(
      notifier: languageNotifier,
      child: ValueListenableBuilder<bool>(
        valueListenable: LowEndMode.notifier,
        builder: (context, lowEnd, _) => ValueListenableBuilder<ThemeMode>(
        valueListenable: ThemeStore.mode,
        builder: (context, mode, _) => MaterialApp(
        navigatorKey: appNavigatorKey,
        title: AppInfo.name,
        debugShowCheckedModeBanner: false,
        builder: (context, child) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final palette = isDark ? AppPalette.dark : AppPalette.light;
          if (!identical(AppPalette.current, palette)) {
            AppPalette.current = palette;
            // Screens that read AppColors without watching the theme must repaint.
            WidgetsBinding.instance.addPostFrameCallback((_) => repaintAll());
          }
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: maxTextScale), disableAnimations: lowEnd || mq.disableAnimations),
            // Urdu and Kashmiri read right to left (MASTER-5 Task 24).
            child: Directionality(
              textDirection: LanguageScope.of(context).textDirection,
              child: Column(
                children: [
                  Expanded(child: AppControlGate(child: child ?? const SizedBox.shrink())),
                  const OfflineBanner(),
                ],
              ),
            ),
          );
        },
        theme: AppTheme.build(Brightness.light, lowEnd: lowEnd),
        darkTheme: AppTheme.build(Brightness.dark, lowEnd: lowEnd),
        themeMode: mode,
        // The launch link is read by DeepLinks, not by the navigator.
        initialRoute: '/',
        home: const SplashScreen(),
        ),
        ),
      ),
    );
  }
}
