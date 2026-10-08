import 'package:flutter/material.dart';

import '../features/features.dart';
import '../support/problem_report.dart';
import '../widgets/feature_gate.dart';

import '../l10n/l10n.dart';
import 'feedback_screen.dart';
import 'legal_screens.dart';
import 'onboarding_screen.dart';

/// Which questions each role sees (MASTER-5 Task 42). A role not listed for a
/// question does not see it; `null` (role unknown) sees them all.
class HelpFaq {
  HelpFaq._();

  static const customer = 'customer';
  static const driver = 'driver';
  static const fleet = 'fleet';
  static const _all = {customer, driver, fleet};

  static const roles = <int, Set<String>>{
    1: {customer, fleet},
    2: _all,
    3: _all,
    4: _all,
    5: _all,
    6: {driver},
    7: _all,
    8: _all,
    9: _all,
    10: _all,
    11: _all,
    12: {customer, fleet}, // issue and share a bilty
    13: {customer, fleet}, // inspection mode, owner side
    14: {driver}, // show the LR at a checkpoint
    15: {driver}, // earnings and the statement
    16: {fleet}, // assign a vehicle and driver
    17: {fleet}, // party statements
    18: {customer}, // promo and credits
  };

  /// The question numbers [role] sees, in order.
  static List<int> forRole(String? role) => [for (final e in roles.entries) if (role == null || e.value.contains(role)) e.key];
}

/// FAQ plus links to the policies and the app tour.
class HelpScreen extends StatelessWidget {
  static const faqCount = 18;

  /// Expands this question (1..[faqCount]) when the screen opens, e.g. from search.
  final int? openFaq;

  /// `customer`, `driver` or `fleet`: only that role's questions show (and the
  /// one asked for by [openFaq]). Null shows all.
  final String? role;

  const HelpScreen({super.key, this.openFaq, this.role});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'helpCenter'))),
      body: ListView(children: [
        for (final i in {...HelpFaq.forRole(role), ?openFaq}.toList()..sort())
          ExpansionTile(
            key: ValueKey('faq$i'),
            initiallyExpanded: openFaq == i,
            title: Text(tr(context, 'faqQ$i'), style: const TextStyle(fontWeight: FontWeight.w700)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            expandedAlignment: Alignment.centerLeft,
            children: [Text(tr(context, 'faqA$i'), style: const TextStyle(height: 1.4))],
          ),
        const Divider(),
        ListTile(
          key: const ValueKey('helpFeedback'),
          leading: const Icon(Icons.rate_review_outlined),
          title: Text(tr(context, 'fbTitle')),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FeedbackScreen())),
        ),
        FeatureGate(
          featureKey: FeatureKey.problemReport,
          child: ListTile(
            key: const ValueKey('helpProblem'),
            leading: const Icon(Icons.report_gmailerrorred_rounded),
            title: Text(tr(context, 'prButton')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showProblemReportSheet(context, screen: 'help'),
          ),
        ),
        ListTile(
          key: const ValueKey('helpTour'),
          leading: const Icon(Icons.slideshow_rounded),
          title: Text(tr(context, 'showIntroAgain')),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnboardingScreen())),
        ),
        for (final (key, icon, screen) in [
          ('helpTerms', Icons.description_outlined, PolicyScreen.terms),
          ('helpPrivacy', Icons.privacy_tip_outlined, PolicyScreen.privacy),
          ('helpRefund', Icons.currency_rupee_rounded, PolicyScreen.refund),
        ])
          ListTile(
            key: ValueKey(key),
            leading: Icon(icon),
            title: Text(tr(context, switch (key) { 'helpTerms' => 'termsOfService', 'helpPrivacy' => 'privacyPolicy', _ => 'refundPolicy' })),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)),
          ),
      ]),
    );
  }
}
