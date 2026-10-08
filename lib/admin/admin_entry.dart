import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/services/admin_console_service.dart';
import 'admin_dashboard_screen.dart';
import 'admin_guard.dart';

/// Profile-menu row that appears only for users in the `admins` allowlist.
/// Hiding it is cosmetic; Firestore rules are the real gate.
class AdminEntryTile extends StatelessWidget {
  const AdminEntryTile({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: AdminConsoleService.isAdminStream(),
      builder: (context, snap) {
        if (snap.data != true) return const SizedBox.shrink();
        return ListTile(
          key: const ValueKey('profileAdmin'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.admin_panel_settings_outlined),
          title: Text(tr(context, 'adminPanel')),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminGuard(child: AdminDashboardScreen()))),
        );
      },
    );
  }
}
