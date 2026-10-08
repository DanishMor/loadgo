import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/l10n/language_widgets.dart';
import '../core/services/settings_service.dart';
import '../core/services/user_service.dart';
import 'role_selection_screen.dart';
import 'start_resolvers.dart';
import '../core/widgets/common.dart';

/// One clear question during driver onboarding: may LoadGo keep the last
/// location to show the nearest loads first? Either answer continues.
class DriverConsentScreen extends StatefulWidget {
  const DriverConsentScreen({super.key});

  @override
  State<DriverConsentScreen> createState() => _DriverConsentScreenState();
}

class _DriverConsentScreenState extends State<DriverConsentScreen> {
  bool _saving = false;

  Future<void> _answer(bool allow) async {
    setState(() => _saving = true);
    try {
      await SettingsService.answerLocationConsent(allow);
      if (!mounted) return;
      final next = await resolveDriverStart();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => next), (route) => false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'somethingWrong')), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _logout() async {
    await UserService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const RoleSelectionScreen()), (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          actions: [
            const LanguageButton(),
            TextButton(onPressed: _saving ? null : _logout, child: Text(tr(context, 'logout'))),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(28)),
                          child: const Icon(Icons.my_location_rounded, size: 50, color: Color(0xFF1565C0)),
                        ),
                        const SizedBox(height: 24),
                        Text(tr(context, 'locConsentTitle'), textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.title)),
                        const SizedBox(height: 12),
                        Text(tr(context, 'locConsentBody'), textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.5, color: AppColors.muted)),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    key: const ValueKey('consentAllow'),
                    onPressed: _saving ? null : () => _answer(true),
                    child: Text(tr(context, 'locConsentAllow'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  key: const ValueKey('consentSkip'),
                  onPressed: _saving ? null : () => _answer(false),
                  child: Text(tr(context, 'locConsentSkip')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
