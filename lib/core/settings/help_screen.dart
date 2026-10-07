import 'package:flutter/material.dart';

import '../features/features.dart';
import '../support/problem_report.dart';
import '../widgets/feature_gate.dart';

import '../l10n/l10n.dart';
import 'feedback_screen.dart';
import 'legal_screens.dart';
import 'onboarding_screen.dart';

/// FAQ plus links to the policies and the app tour.
class HelpScreen extends StatelessWidget {
  static const faqCount = 8;

  /// Expands this question (1..[faqCount]) when the screen opens, e.g. from search.
  final int? openFaq;

  const HelpScreen({super.key, this.openFaq});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'helpCenter'))),
      body: ListView(children: [
        for (var i = 1; i <= faqCount; i++)
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
