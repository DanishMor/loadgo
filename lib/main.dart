import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'admin/admin_entry.dart';
import 'auth/role_selection_screen.dart';
import 'auth/splash_screen.dart';
import 'core/l10n/l10n.dart';
import 'core/navigation/app_routes.dart';
import 'core/services/app_config.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/language_store.dart';
import 'core/services/backend.dart';
import 'core/services/push_service.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/live_stream.dart' show OfflineBanner;
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppRoutes.roleSelection = (_) => const RoleSelectionScreen();
  AppRoutes.adminEntry = (_) => const AdminEntryTile();
  // Log uncaught async errors (e.g. a dropped network call) instead of
  // letting them take the app down; screens show their own retry UI.
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
    return true;
  };
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  Backend.enableOfflinePersistence();
  await ConnectivityService.start();
  applyLanguageName(await LanguageStore.loadLocal());
  await ThemeStore.load();
  // Register for push whenever a user is signed in (also after app restarts).
  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user != null) {
      PushService.register();
      refreshAppConfig();
    }
  });
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
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: ThemeStore.mode,
        builder: (context, mode, _) => MaterialApp(
        title: 'LoadGo',
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
            data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: maxTextScale)),
            child: Column(
              children: [
                Expanded(child: child ?? const SizedBox.shrink()),
                const OfflineBanner(),
              ],
            ),
          );
        },
        theme: AppTheme.build(Brightness.light),
        darkTheme: AppTheme.build(Brightness.dark),
        themeMode: mode,
        home: const SplashScreen(),
        ),
      ),
    );
  }
}
