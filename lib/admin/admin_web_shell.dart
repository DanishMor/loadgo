import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/services/admin_console_service.dart';
import '../core/services/backend.dart';
import '../core/theme/design_tokens.dart';
import '../core/widgets/ds/app_button.dart';
import 'admin_dashboard_screen.dart';
import 'admin_guard.dart';

/// The admin web build (APP_MODE=admin, F32). Signed out: the normal sign-in
/// pages below it. Signed in as an admin: only the admin console. Signed in as
/// anyone else: a calm sentence and Sign out; no customer, driver or fleet
/// screen is ever reachable from here. The real gate is still the rules.
class AdminWebShell extends StatelessWidget {
  final Widget child;
  final Stream<bool>? signedIn;
  final Stream<bool>? adminStream;
  const AdminWebShell({super.key, required this.child, this.signedIn, this.adminStream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: signedIn ?? Backend.auth.authStateChanges().map((u) => u != null),
      builder: (context, auth) {
        if (auth.data != true) return child;
        return StreamBuilder<bool>(
          stream: adminStream ?? AdminConsoleService.isAdminStream(),
          builder: (context, admin) {
            if (admin.data == true) return AdminGuard(adminStream: adminStream, child: const AdminDashboardScreen());
            if (admin.data == false) return const _NotAdmin();
            return const Scaffold(key: ValueKey('adminWebWaiting'), body: Center(child: CircularProgressIndicator()));
          },
        );
      },
    );
  }
}

class _NotAdmin extends StatelessWidget {
  const _NotAdmin();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('adminWebNotAdmin'),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(DsSpace.s5),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(tr(context, 'adminWebNotAdmin'), textAlign: TextAlign.center, style: DsType.title.copyWith(color: context.ds.text)),
            const SizedBox(height: DsSpace.s4),
            AppButton(key: const ValueKey('adminWebSignOut'), label: tr(context, 'adminWebSignOut'), kind: AppButtonKind.secondary, expand: false, onPressed: () => Backend.auth.signOut()),
          ]),
        ),
      ),
    );
  }
}
