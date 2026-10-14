import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/design_tokens.dart';

/// One tab of the bottom bar. [badge] is a count of new things (0 = none).
class AppNavItem {
  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final int badge;
  final Key? key;

  const AppNavItem({required this.icon, this.selectedIcon, required this.label, this.badge = 0, this.key});
}

/// The bottom navigation of every home screen: 3 to 5 tabs, an icon and a
/// label on each (the label is always shown), a navy indicator, and a count
/// badge that is also spoken ("3 new"). Built on NavigationBar, so its theme
/// (tokens) and the old screens' `NavigationBar` look the same.
class AppBottomNav extends StatelessWidget {
  final List<AppNavItem> items;
  final int index;
  final ValueChanged<int> onChanged;

  const AppBottomNav({super.key, required this.items, required this.index, required this.onChanged})
      : assert(items.length >= 2 && items.length <= 5, 'a bottom bar has 2 to 5 tabs');

  Widget _icon(BuildContext context, AppNavItem it, IconData data) {
    final icon = Icon(data);
    if (it.badge <= 0) return icon;
    return Semantics(
      label: trf(context, 'dsNewCount', {'n': it.badge}),
      child: Badge(label: Text(it.badge > 99 ? '99+' : '${it.badge}'), child: ExcludeSemantics(child: icon)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: index.clamp(0, items.length - 1),
      onDestinationSelected: onChanged,
      height: DsSpace.tapMin + DsSpace.s6,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: [
        for (final it in items)
          NavigationDestination(
            key: it.key,
            icon: _icon(context, it, it.icon),
            selectedIcon: _icon(context, it, it.selectedIcon ?? it.icon),
            label: it.label,
          ),
      ],
    );
  }
}
