import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/navigation/app_routes.dart';
import '../core/widgets/common.dart';

/// Shown at start to an account an admin banned.
class BannedScreen extends StatelessWidget {
  const BannedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.block_rounded, size: 72, color: Colors.redAccent),
            const SizedBox(height: 20),
            Text(tr(context, 'auBannedTitle'), key: const ValueKey('bannedTitle'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(tr(context, 'auBannedBody'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 24),
            OutlinedButton(key: const ValueKey('bannedLogout'), onPressed: () => AppRoutes.logout(context), child: Text(tr(context, 'logout'))),
          ]),
        ),
      ),
    );
  }
}
