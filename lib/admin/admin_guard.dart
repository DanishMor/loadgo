import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/services/admin_console_service.dart';

/// Colour of the Admin mode banner; no other part of the app uses it.
const adminModeColor = Color(0xFF6A1B9A);

/// Route guard for the whole admin area (Task 69). It watches `admins/{uid}`
/// live: while the answer is unknown, or when the user is not an admin, the
/// child is never built (so no admin screen loads any data) and the route
/// closes at once. Admins get an "Admin mode" banner above every admin screen.
/// Hiding is cosmetic; Firestore rules are the real gate.
class AdminGuard extends StatefulWidget {
  final Widget child;
  final Stream<bool>? adminStream;
  const AdminGuard({super.key, required this.child, this.adminStream});

  @override
  State<AdminGuard> createState() => _AdminGuardState();
}

class _AdminGuardState extends State<AdminGuard> {
  late final Stream<bool> _stream = widget.adminStream ?? AdminConsoleService.isAdminStream();
  bool _leaving = false;

  void _leave() {
    if (_leaving) return;
    _leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context, rootNavigator: true).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasData && snap.data == false) _leave();
        if (snap.data != true) {
          return const Scaffold(key: ValueKey('adminGuardWaiting'), body: Center(child: CircularProgressIndicator()));
        }
        return Material(
          child: Column(children: [
            const AdminModeBanner(),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: NavigatorPopHandler(
                  onPopWithResult: (_) => Navigator.of(context, rootNavigator: true).maybePop(),
                  child: Navigator(onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => widget.child)),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class AdminModeBanner extends StatelessWidget {
  const AdminModeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('adminModeBanner'),
      width: double.infinity,
      color: adminModeColor,
      padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 4, 16, 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 16),
        const SizedBox(width: 6),
        Text(tr(context, 'adminModeBanner'),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12, decoration: TextDecoration.none)),
      ]),
    );
  }
}
