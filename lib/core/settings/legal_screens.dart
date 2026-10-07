import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import '../widgets/common.dart';
import 'policy_links.dart';

/// A policy made of clauses. Each clause string is "Heading\nBody".
class PolicyScreen extends StatelessWidget {
  final String titleKey;
  final String clausePrefix;
  final int clauses;

  /// Public page of this policy (`/privacy`, `/terms`), shown as a link.
  final String? Function()? webUrl;

  const PolicyScreen({super.key, required this.titleKey, required this.clausePrefix, required this.clauses, this.webUrl});

  static const terms = PolicyScreen(titleKey: 'termsOfService', clausePrefix: 'tosC', clauses: 5, webUrl: PolicyLinks.terms);
  static const privacy = PolicyScreen(titleKey: 'privacyPolicy', clausePrefix: 'privC', clauses: 5, webUrl: PolicyLinks.privacy);
  static const refund = PolicyScreen(titleKey: 'refundPolicy', clausePrefix: 'refC', clauses: 5);

  /// (heading, body) of a clause text.
  static (String, String) split(String clause) {
    final i = clause.indexOf('\n');
    return i < 0 ? (clause, '') : (clause.substring(0, i), clause.substring(i + 1));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, titleKey))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (webUrl != null) _WebLink(url: webUrl!()!),
          for (var i = 1; i <= clauses; i++) ...[
            Builder(builder: (context) {
              final (head, body) = split(tr(context, '$clausePrefix$i'));
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(head, key: ValueKey('$clausePrefix$i'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(body, style: const TextStyle(fontSize: 15, height: 1.4)),
                const SizedBox(height: 18),
              ]);
            }),
          ],
        ],
      ),
    );
  }
}

class _WebLink extends StatelessWidget {
  final String url;
  const _WebLink({required this.url});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppCard(
        key: const ValueKey('policyWebLink'),
        onTap: () async {
          var ok = false;
          try {
            ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          } catch (_) {}
          if (!ok && context.mounted) {
            await Clipboard.setData(ClipboardData(text: url));
            if (context.mounted) showSnack(context, tr(context, 'policyLinkCopied'));
          }
        },
        child: Row(children: [
          const Icon(Icons.public_rounded),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(context, 'policyPublicPage'), style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(url, style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ])),
        ]),
      ),
    );
  }
}
