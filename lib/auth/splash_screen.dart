import '../core/app_info.dart';
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/services/device_service.dart';
import '../core/services/user_service.dart';
import '../core/settings/onboarding_screen.dart';
import 'start_resolvers.dart';
import 'role_selection_screen.dart';


// ============================================================
// SPLASH SCREEN
// ============================================================

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    Widget next = const RoleSelectionScreen();
    final user = FirebaseAuth.instance.currentUser;

    if (user == null && !await OnboardingStore.seen()) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => OnboardingScreen(
          onDone: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const RoleSelectionScreen())),
        ),
      ));
      return;
    }

    if (user != null) {
      try {
        // Revoked device or "log out everywhere": start from the login screen.
        if (await DeviceService.sessionRevoked()) {
          await UserService.logout();
          if (!mounted) return;
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const RoleSelectionScreen()));
          return;
        }
        final data = await UserService.getUser();
        final selectedRole = (data?['role'] ?? data?['selectedRole']) as String?;
        next = selectedRole == 'driver'
            ? await resolveDriverStart()
            : selectedRole == 'fleet'
                ? await resolveFleetStart()
                : await resolveCustomerStart();
      } catch (_) {
        next = const RoleSelectionScreen();
      }
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => next));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 25,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: const Icon(Icons.local_shipping_rounded, size: 70, color: Color(0xFF1565C0)),
              ),
              const SizedBox(height: 28),
              Text(
                AppInfo.name,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr(context, 'tagline'),
                style: const TextStyle(color: Colors.white70, fontSize: 17, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 50),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
