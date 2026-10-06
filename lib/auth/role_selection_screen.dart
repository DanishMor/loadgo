
import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/l10n/language_widgets.dart';
import 'driver_login_screen.dart';
import 'customer_login_screen.dart';
import '../core/widgets/common.dart';


// ROLE SELECTION
// ============================================================

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => showLanguageSelector(context),
                  icon: const Icon(Icons.language_rounded, size: 19),
                  label: Text(trLanguageName(LanguageScope.of(context))),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'LoadGo',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1565C0)),
              ),
              const SizedBox(height: 12),
              Text(
                tr(context, 'welcome'),
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: AppColors.title),
              ),
              const SizedBox(height: 8),
              Text(
                tr(context, 'chooseRole'),
                style: TextStyle(fontSize: 16, color: AppColors.muted),
              ),
              const SizedBox(height: 32),
              _RoleCard(
                icon: Icons.business_center_rounded,
                title: tr(context, 'bookTruck'),
                subtitle: tr(context, 'customerDesc'),
                buttonText: tr(context, 'continueCustomer'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CustomerLoginScreen()),
                  );
                },
              ),
              const SizedBox(height: 18),
              _RoleCard(
                icon: Icons.local_shipping_rounded,
                title: tr(context, 'getLoads'),
                subtitle: tr(context, 'driverDesc'),
                buttonText: tr(context, 'continueDriver'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DriverLoginScreen()),
                  );
                },
              ),
              const SizedBox(height: 18),
              _RoleCard(
                icon: Icons.warehouse_rounded,
                title: tr(context, 'fleetOwner'),
                subtitle: tr(context, 'fleetOwnerDesc'),
                buttonText: tr(context, 'continueFleet'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DriverLoginScreen(role: 'fleet')),
                  );
                },
              ),
              const SizedBox(height: 28),
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => showLanguageSelector(context),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.language_rounded, color: Color(0xFF1565C0), size: 25),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr(context, 'language'),
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              trLanguageName(LanguageScope.of(context)),
                              style: TextStyle(fontSize: 13, color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  tr(context, 'footer'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback onPressed;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: const Color(0xFF1565C0), size: 32),
          ),
          const SizedBox(height: 16),
          Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.title)),
          const SizedBox(height: 7),
          Text(subtitle, style: TextStyle(fontSize: 14, height: 1.45, color: AppColors.muted)),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                buttonText,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
