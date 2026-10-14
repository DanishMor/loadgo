import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/design_tokens.dart';

/// The app bar of the design system: a title (and an optional second line), a
/// back button that is always 48 dp and spoken, actions, and an optional thin
/// line in the colour of the person's role ('customer', 'driver',
/// 'transporter') as a light touch of identity. Admin screens keep their own
/// "Admin mode" banner.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final String? role;
  final bool showBack;
  final VoidCallback? onBack;

  const AppTopBar({super.key, required this.title, this.subtitle, this.actions = const [], this.role, this.showBack = true, this.onBack});

  @override
  Size get preferredSize => Size.fromHeight((subtitle == null ? kToolbarHeight : 72) + (role == null ? 0 : 3));

  @override
  Widget build(BuildContext context) {
    final c = DsColors.of(Theme.of(context).brightness);
    final canPop = Navigator.maybeOf(context)?.canPop() ?? false;
    final accent = role == null ? null : RoleAccents.of(context).forRole(role, c.primary);
    return AppBar(
      automaticallyImplyLeading: false,
      leading: showBack && (canPop || onBack != null)
          ? IconButton(
              tooltip: tr(context, 'dsBack'),
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: onBack ?? () => Navigator.maybeOf(context)?.maybePop(),
            )
          : null,
      titleSpacing: showBack && (canPop || onBack != null) ? 0 : DsSpace.gutter,
      title: Semantics(
        header: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: DsType.title.copyWith(color: c.text)),
            if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: DsType.caption.copyWith(color: c.textMuted)),
          ],
        ),
      ),
      actions: [...actions, const SizedBox(width: DsSpace.s2)],
      bottom: accent == null
          ? null
          : PreferredSize(preferredSize: const Size.fromHeight(3), child: Container(height: 3, color: accent)),
    );
  }
}
