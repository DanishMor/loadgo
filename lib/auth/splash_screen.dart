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
import '../core/theme/design_tokens.dart';
import '../core/widgets/ds/brand_logo.dart';
import '../core/widgets/ds/motion.dart';


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
      // Take the navigator now: this splash is gone after the replace, so its own context cannot be used later.
      final nav = Navigator.of(context);
      nav.pushReplacement(MaterialPageRoute(
        builder: (_) => OnboardingScreen(
          onDone: () => nav.pushReplacement(MaterialPageRoute(builder: (_) => const RoleSelectionScreen())),
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
  Widget build(BuildContext context) => const SplashView();
}

/// What the splash screen shows (separate from the start-up logic so it can be tested).
class SplashView extends StatelessWidget {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) {
    // The brand on its deep-navy gradient: the mark pops in, then the name and
    // the tagline arrive one after the other, with a thin progress bar below.
    // With "remove animations" or Low-end mode all of it is simply there.
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: DsHero.colors),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(DsSpace.s6),
              child: Semantics(
                container: true,
                label: '${AppInfo.name}. ${tr(context, 'tagline')}',
                child: ExcludeSemantics(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const PopIn(child: LogoMark(size: 112, variant: LogoVariant.reversed)),
                      const SizedBox(height: DsSpace.s6),
                      const FadeSlideIn(delay: Duration(milliseconds: 150), child: Wordmark(height: 40, onDark: true)),
                      const SizedBox(height: DsSpace.s2),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 300),
                        child: Text(tr(context, 'tagline'), textAlign: TextAlign.center, style: DsStyle.t18w400.copyWith(color: DsBrand.white)),
                      ),
                      const SizedBox(height: DsSpace.s12),
                      SizedBox(
                        width: 140,
                        child: ClipRRect(
                          borderRadius: DsRadius.all(DsRadius.pill),
                          child: LinearProgressIndicator(minHeight: 4, color: DsBrand.saffron, backgroundColor: DsBrand.white.withValues(alpha: 0.25)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
// ============================================================
