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
import 'core/services/push_service.dart';
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
  await ConnectivityService.start();
  applyLanguageName(await LanguageStore.loadLocal());
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
      child: MaterialApp(
        title: 'LoadGo',
        debugShowCheckedModeBanner: false,
        builder: (context, child) => Column(
          children: [
            Expanded(child: child ?? const SizedBox.shrink()),
            const OfflineBanner(),
          ],
        ),
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Roboto',
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1565C0),
            brightness: Brightness.light,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE4E7EC)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE4E7EC)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF1565C0), width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}
