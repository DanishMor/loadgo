import 'dart:async';

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
import 'core/errors/startup_failed_app.dart';
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
import 'core/services/breadcrumbs.dart';
import 'core/services/push_service.dart';
import 'core/services/session_watcher.dart';
import 'core/services/settings_service.dart';
import 'core/services/analytics_events.dart';
import 'core/settings/simple_mode.dart';
import 'core/features/features.dart';
import 'core/services/features_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/design_tokens.dart';
import 'core/widgets/app_control_gate.dart';
import 'core/notifications/push_router.dart';
import 'core/location/live_location_sharer.dart';
import 'core/security/app_lock.dart';
import 'core/services/app_check_setup.dart';
import 'core/security/local_auth_authenticator.dart';
import 'core/widgets/ds/haptics.dart';
import 'core/widgets/live_stream.dart' show OfflineBanner;
import 'firebase_options.dart';
import 'route_hooks.dart';
import 'admin/admin_web_shell.dart';
import 'core/app_mode.dart';
import 'core/photos/photo_widgets.dart' show PhotoImage, PhotoSync;
import 'core/photos/vehicle_photo_badge.dart' show PhotoBadgeCache;

/// Lets code outside a screen (the session watcher) reach the navigator.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Part 5 (H20): pictures in memory are capped (the default is 100 MB, too much for a 2 GB phone); the framework also
  // empties this cache by itself when the system says memory is low.
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = 48 << 20
    ..maximumSize = 150;
  AppRoutes.roleSelection = (_) => const RoleSelectionScreen();
  AppRoutes.adminEntry = (_) => const AdminEntryTile();
  registerRouteHooks();
  // In a release build a widget that fails to build shows a calm sentence, not the framework's error box.
  if (!kDebugMode) ErrorWidget.builder = friendlyErrorWidget;
  // Log uncaught async errors (e.g. a dropped network call) instead of
  // letting them take the app down; screens show their own retry UI.
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught error: ${Redactor.safe(error)}');
    return true;
  };
  // Part 5 (H16): if Firebase cannot start (no network on the very first launch, a broken install) the person sees one calm
  // screen with a Try again button, not a frozen splash. A second try after a half start finds the app already there.
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform).timeout(const Duration(seconds: 30));
    }
  } catch (e) {
    debugPrint('Firebase did not start: ${Redactor.safe(e)}');
    runApp(StartupFailedApp(onRetry: main));
    return;
  }
  // Everything below may fail without stopping the app (StartupGuard): a late push router or a failed settings read is
  // better than no app. The failures are listed in StartupGuard.failed.
  await StartupGuard.step<Object?>('crash', CrashService.init);
  // G15: App Check proof, only when the build asks for it (--dart-define=APP_CHECK=on); monitor mode first.
  await StartupGuard.step<Object?>('appCheck', AppCheckSetup.start);
  // A tapped push opens the right screen. It must start AFTER Firebase: before that the messaging
  // service does not exist and the router would silently stay off.
  await StartupGuard.step<Object?>('localAuth', () async => LocalAuthAppLockAuthenticator.install());
  await StartupGuard.step<Object?>('offline', () async => Backend.enableOfflinePersistence());
  unawaited(AppControlService.refresh());
  // The local settings do not depend on each other: read them together so the
  // first screen is not held up by four reads in a row (MASTER-5 Task 14).
  final results = await Future.wait<Object?>([
    StartupGuard.step<Object?>('language', LanguageStore.loadLocal),
    StartupGuard.step<Object?>('connectivity', ConnectivityService.start),
    StartupGuard.step<Object?>('theme', ThemeStore.load),
    StartupGuard.step<Object?>('simpleMode', SimpleMode.load),
    StartupGuard.step<Object?>('lowEnd', LowEndMode.load),
    StartupGuard.step<Object?>('haptics', Haptics.load),
    StartupGuard.step<Object?>('appLock', AppLock.load),
  ]);
  applyLanguageName(results[0] as String?);
  // Photos that waited for the network go out when the phone is back online.
  PhotoSync.start();
  // Register for push whenever a user is signed in (also after app restarts).
  String? configUid;
  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user != null) {
      // The system prompt only follows the explanation (Settings > Phone alerts).
      PermissionRationale.seen(RationaleKind.notifications).then((seen) {
        if (seen) PushService.register();
      });
      // With the pushNotifications switch on: the explanation, then the system prompt (once a day at most).
      PushService.askAfterSignIn(appNavigatorKey);
      AppControlService.refresh();
      DeviceService.syncClock().ignore();
      PhotoSync.flush().ignore();
      // Another account needs its own settings; the same one reuses the cache.
      refreshAppConfig(force: user.uid != configUid);
      configUid = user.uid;
      // The saved analytics choice applies from the first screen (off until the person said yes).
      SettingsService.loadConsents().then((_) {}, onError: (_) {});
    } else {
      AnalyticsEvents.setConsent(false).ignore();
      // The live trip location stops with the sign-in (G11).
      LiveLocationSharer.stop().ignore();
      // Pictures of papers kept in memory must not outlive the sign-in.
      PhotoImage.clearCache();
      PhotoBadgeCache.clear();
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
  // Part 5 (H24): the push router waits for the first frame instead of holding it: it asks the platform for the message that
  // opened the app, which can take a moment. It still starts after Firebase (above) and keeps a tap that arrives early.
  unawaited(StartupGuard.step<Object?>('push', () => PushRouter.start(appNavigatorKey)));
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
        builder: (context, lowEnd, _) => ListenableBuilder(
        // E7: the look follows the designV3 switch; Classic while it is OFF.
        listenable: Listenable.merge([ThemeStore.mode, ThemeStore.style, FeaturesService.notifier]),
        builder: (context, _) {
        final style = ThemeStore.effective(designV3: FeaturesService.current.isOn(FeatureKey.designV3));
        return MaterialApp(
        navigatorKey: appNavigatorKey,
        navigatorObservers: [BreadcrumbObserver()],
        title: AppInfo.name,
        debugShowCheckedModeBanner: false,
        builder: (context, child) {
          final colors = context.ds;
          final palette = AppPalette.forColors(colors);
          if (!identical(AppPalette.current, palette)) {
            AppPalette.current = palette;
            AppPalette.currentColors = colors;
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
                  Expanded(child: AppControlGate(child: AppMode.isAdminOnly ? AdminWebShell(child: child ?? const SizedBox.shrink()) : (child ?? const SizedBox.shrink()))),
                  const OfflineBanner(),
                ],
              ),
            ),
          );
        },
        theme: AppTheme.build(Brightness.light, lowEnd: lowEnd, style: style),
        darkTheme: AppTheme.build(Brightness.dark, lowEnd: lowEnd, style: style),
        themeMode: ThemeStore.mode.value,
        // The launch link is read by DeepLinks, not by the navigator.
        initialRoute: '/',
        home: const SplashScreen(),
        );
        },
        ),
      ),
    );
  }
}
