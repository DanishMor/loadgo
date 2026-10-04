import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../widgets/common.dart';

/// A Profile-tab row that opens another screen. Role folders hand these to
/// `ProfileView.extraTiles`, so core/ never imports a role's screens.
class ProfileNavTile extends StatelessWidget {
  final IconData icon;

  /// Translation key of the title.
  final String titleKey;
  final WidgetBuilder screen;

  const ProfileNavTile({super.key, required this.icon, required this.titleKey, required this.screen});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.muted),
      title: Text(tr(context, titleKey)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: screen)),
    );
  }
}
