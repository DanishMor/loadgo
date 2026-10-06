import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// A policy made of clauses. Each clause string is "Heading\nBody".
class PolicyScreen extends StatelessWidget {
  final String titleKey;
  final String clausePrefix;
  final int clauses;

  const PolicyScreen({super.key, required this.titleKey, required this.clausePrefix, required this.clauses});

  static const terms = PolicyScreen(titleKey: 'termsOfService', clausePrefix: 'tosC', clauses: 5);
  static const privacy = PolicyScreen(titleKey: 'privacyPolicy', clausePrefix: 'privC', clauses: 5);
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
