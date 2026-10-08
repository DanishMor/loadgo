import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import 'common.dart';

/// The three first-time steps of a role (MASTER-5 Task 27).
class RoleTour {
  RoleTour._();

  static const customer = 'customer';
  static const driver = 'driver';
  static const fleet = 'fleet';
  static const roles = [customer, driver, fleet];

  /// (title key, step keys) for [role].
  static (String, List<String>) keys(String role) => switch (role) {
        driver => ('tourDrvTitle', ['tourDrv1', 'tourDrv2', 'tourDrv3']),
        fleet => ('tourTrTitle', ['tourTr1', 'tourTr2', 'tourTr3']),
        _ => ('tourCustTitle', ['tourCust1', 'tourCust2', 'tourCust3']),
      };

  static String _key(String role) => 'tour_seen_$role';

  static Future<bool> seen(String role) async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_key(role)) ?? false;
    } catch (_) {
      return true; // storage unavailable: never nag
    }
  }

  static Future<void> markSeen(String role) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_key(role), true);
    } catch (_) {}
  }
}

/// A dismissible "how it works" card at the top of a home screen. Shown once
/// per role on this device; "Got it" hides it for good.
class RoleTourCard extends StatefulWidget {
  final String role;
  const RoleTourCard({super.key, required this.role});

  @override
  State<RoleTourCard> createState() => _RoleTourCardState();
}

class _RoleTourCardState extends State<RoleTourCard> {
  late final Future<bool> _seen = RoleTour.seen(widget.role);
  bool _hidden = false;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _seen,
      builder: (context, snap) {
        if (_hidden || snap.data != false) return const SizedBox.shrink();
        final (title, steps) = RoleTour.keys(widget.role);
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: AppCard(
            key: ValueKey('tour_${widget.role}'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.lightbulb_outline_rounded, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(tr(context, title), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.title))),
              ]),
              const SizedBox(height: 8),
              for (final k in steps)
                Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(tr(context, k), style: TextStyle(color: AppColors.body, height: 1.35))),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  key: const ValueKey('tourGotIt'),
                  onPressed: () {
                    setState(() => _hidden = true);
                    RoleTour.markSeen(widget.role);
                  },
                  child: Text(tr(context, 'tourGotIt')),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}
