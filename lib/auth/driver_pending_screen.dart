import 'package:flutter/material.dart';

import '../core/services/user_service.dart';
import '../core/l10n/l10n.dart';
import '../driver/driver_home_screen.dart';
import 'start_resolvers.dart';
import 'driver_onboarding_card.dart';
import 'role_selection_screen.dart';
import '../core/widgets/common.dart';
import '../core/theme/design_tokens.dart';
import '../core/widgets/ds/status_badge.dart';

class DriverPendingScreen extends StatefulWidget {
  const DriverPendingScreen({super.key});

  @override
  State<DriverPendingScreen> createState() => _DriverPendingScreenState();
}

class _DriverPendingScreenState extends State<DriverPendingScreen> {
  bool _checking = false;

  Future<void> _checkStatus() async {
    setState(() => _checking = true);
    final next = await resolveDriverStart();
    if (!mounted) return;
    setState(() => _checking = false);

    if (next is DriverHomeScreen) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => next),
        (route) => false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'pendingStillWaiting')), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _logout() async {
    await UserService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: TextButton(onPressed: _logout, child: Text(tr(context, 'logout'))),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                        Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(color: AppColors.warnBg, borderRadius: BorderRadius.circular(32)),
                          child: Icon(Icons.hourglass_top_rounded, size: 56, color: context.ds.warning),
                        ),
                        const SizedBox(height: 20),
                        StatusBadge(
                          key: const ValueKey('pendingChip'),
                          label: tr(context, 'pendingVerification'),
                          tone: StatusTone.attention,
                          icon: Icons.pending_actions_rounded,
                        ),
                        const SizedBox(height: 16),
                        Text(tr(context, 'pendingTitle'), textAlign: TextAlign.center, style: DsStyle.t24w700.copyWith(color: AppColors.title)),
                        const SizedBox(height: 10),
                        Text(tr(context, 'pendingSub'), textAlign: TextAlign.center, style: DsStyle.t16w400.copyWith(height: 1.5, color: AppColors.muted)),
                        const SizedBox(height: 20),
                        DriverOnboardingCard(onResubmitted: _checkStatus),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _checking ? null : _checkStatus,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _checking
                        ? const SizedBox(
                            width: 23,
                            height: 23,
                            child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                          )
                        : Text(tr(context, 'refreshStatus'), style: DsStyle.t16w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}