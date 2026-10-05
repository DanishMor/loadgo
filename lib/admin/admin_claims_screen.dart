import 'package:flutter/material.dart';

import '../core/claims/claim_screens.dart';
import '../core/l10n/l10n.dart';
import '../core/models/claim.dart';
import '../core/services/claim_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// Admin > Claims: open ones first; tap one to review and resolve.
class AdminClaimsScreen extends StatelessWidget {
  const AdminClaimsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'adminDisputes'))),
      body: LiveStream<List<Claim>>(
        stream: ClaimService.watchAll,
        builder: (context, list) {
          if (list.isEmpty) return EmptyState(icon: Icons.report_problem_outlined, title: tr(context, 'dspNone'));
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final c = list[i];
              return Card(
                child: ListTile(
                  key: ValueKey('adminClaim_${c.id}'),
                  title: Text('${tr(context, 'dspType_${c.type}')} · ${c.bookingId}'),
                  subtitle: Text('${claimStatusLabel(context, c)}\n${c.description}', maxLines: 3, overflow: TextOverflow.ellipsis),
                  isThreeLine: true,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClaimScreen(claimId: c.id, admin: true))),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
