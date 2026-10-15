
import '../core/features/features.dart';
import '../core/widgets/feature_gate.dart';
import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/l10n/language_widgets.dart';
import 'driver_login_screen.dart';
import 'customer_login_screen.dart';
import '../core/widgets/common.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/design_tokens.dart';
import '../core/widgets/ds/app_button.dart';
import '../core/widgets/ds/brand_logo.dart';
import '../core/widgets/ds/motion.dart';


// ROLE SELECTION
// ============================================================

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(DsSpace.gutter + 4, DsSpace.s4, DsSpace.gutter + 4, DsSpace.s8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A Wrap, not a Row: at big text sizes the language button drops under the logo.
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: DsSpace.s3,
                spacing: DsSpace.s3,
                children: [
                  const BrandLockup(markSize: 40),
                  OutlinedButton.icon(
                    key: const ValueKey('roleLanguageButton'),
                    onPressed: () => showLanguageSelector(context),
                    icon: const Icon(Icons.language_rounded, size: 19),
                    label: Text(trLanguageName(LanguageScope.of(context))),
                  ),
                ],
              ),
              const SizedBox(height: DsSpace.s6),
              FadeSlideIn(
                child: Semantics(header: true, child: Text(tr(context, 'welcome'), style: DsType.headline.copyWith(fontSize: 28, color: c.text))),
              ),
              const SizedBox(height: DsSpace.s2),
              FadeSlideIn(
                delay: FadeSlideIn.staggerDelay(1),
                child: Text(tr(context, 'chooseRole'), style: DsType.body.copyWith(color: c.textMuted)),
              ),
              const SizedBox(height: DsSpace.s6),
              FadeSlideIn(
                delay: FadeSlideIn.staggerDelay(2),
                child: _RoleCard(
                  role: 'customer',
                  icon: Icons.business_center_rounded,
                  title: tr(context, 'bookTruck'),
                  subtitle: tr(context, 'customerDesc'),
                  buttonText: tr(context, 'continueCustomer'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CustomerLoginScreen())),
                ),
              ),
              const SizedBox(height: DsSpace.s4),
              FadeSlideIn(
                delay: FadeSlideIn.staggerDelay(3),
                child: _RoleCard(
                  role: 'driver',
                  icon: Icons.local_shipping_rounded,
                  title: tr(context, 'getLoads'),
                  subtitle: tr(context, 'driverDesc'),
                  buttonText: tr(context, 'continueDriver'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DriverLoginScreen())),
                ),
              ),
              FeatureGate(
                featureKey: FeatureKey.transporter,
                child: Padding(
                  padding: const EdgeInsets.only(top: DsSpace.s4),
                  child: FadeSlideIn(
                    delay: FadeSlideIn.staggerDelay(4),
                    child: _RoleCard(
                      role: 'transporter',
                      icon: Icons.warehouse_rounded,
                      title: tr(context, 'fleetOwner'),
                      subtitle: tr(context, 'fleetOwnerDesc'),
                      buttonText: tr(context, 'continueFleet'),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DriverLoginScreen(role: 'fleet'))),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: DsSpace.s6),
              AppCard(
                key: const ValueKey('roleLanguageCard'),
                onTap: () => showLanguageSelector(context),
                child: Row(
                  children: [
                    Icon(Icons.language_rounded, color: c.primary, size: 25),
                    const SizedBox(width: DsSpace.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr(context, 'language'), style: DsType.subtitle.copyWith(color: c.text)),
                          const SizedBox(height: 3),
                          Text(trLanguageName(LanguageScope.of(context)), style: DsType.bodySmall.copyWith(color: c.textMuted)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: c.textMuted),
                  ],
                ),
              ),
              const SizedBox(height: DsSpace.s5),
              Center(child: Text(tr(context, 'footer'), textAlign: TextAlign.center, style: DsType.bodySmall.copyWith(color: c.textMuted))),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the three kinds of person: a card with a thin line and an icon tile
/// in the role's own colour (a light touch), the name of the work, one
/// sentence, and one navy button.
class _RoleCard extends StatelessWidget {
  final String role;
  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback onPressed;

  const _RoleCard({
    required this.role,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final accent = RoleAccents.of(context).forRole(role, c.primary);
    return Container(
      key: ValueKey('roleCard_$role'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: DsRadius.all(DsRadius.xl),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(DsSpace.s5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), borderRadius: DsRadius.all(DsRadius.lg)),
                      child: Icon(icon, color: accent, size: 30),
                    ),
                    const SizedBox(height: DsSpace.s4),
                    Semantics(header: true, child: Text(title, style: DsType.headline.copyWith(color: c.text))),
                    const SizedBox(height: DsSpace.s2),
                    Text(subtitle, style: DsType.bodySmall.copyWith(color: c.textMuted, height: 1.45)),
                    const SizedBox(height: DsSpace.s4),
                    AppButton(label: buttonText, kind: AppButtonKind.strong, onPressed: onPressed),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// ============================================================
