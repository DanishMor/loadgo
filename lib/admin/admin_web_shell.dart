import 'dart:async';

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
      // A failed sign-in check is treated as signed out: the sign-in pages show.
      builder: (context, auth) => !auth.hasError && auth.data == true ? _AdminGate(adminStream: adminStream) : child,
    );
  }
}

/// Exists only while someone is signed in. It listens to "is this an admin?" once and gives the same
/// answer to the page and to the guard below it, so both change in the same frame (the guard would
/// otherwise try to close a route that this shell has no navigator for).
class _AdminGate extends StatefulWidget {
  final Stream<bool>? adminStream;
  const _AdminGate({this.adminStream});

  @override
  State<_AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<_AdminGate> {
  final StreamController<bool> _changes = StreamController<bool>.broadcast();
  StreamSubscription<bool>? _sub;
  bool? _isAdmin;

  @override
  void initState() {
    super.initState();
    _sub = (widget.adminStream ?? AdminConsoleService.isAdminStream()).listen((v) {
      if (!mounted) return;
      setState(() => _isAdmin = v);
      _changes.add(v);
    }, onError: (_) {
      if (mounted) setState(() => _isAdmin = false);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _changes.close();
    super.dispose();
  }

  // What the guard sees: the answer we already have, then every change.
  Stream<bool> _forGuard() async* {
    yield _isAdmin == true;
    yield* _changes.stream;
  }

  @override
  Widget build(BuildContext context) {
    if (_isAdmin == true) return AdminGuard(adminStream: _forGuard(), child: const AdminDashboardScreen());
    if (_isAdmin == false) return const _NotAdmin();
    return const Scaffold(key: ValueKey('adminWebWaiting'), body: Center(child: CircularProgressIndicator()));
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
