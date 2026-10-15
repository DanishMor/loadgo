import 'package:flutter/material.dart';

import 'common.dart';
import '../theme/design_tokens.dart';

/// One labelled number on an analytics screen.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const StatTile({super.key, required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(children: [
        Icon(icon, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: DsStyle.inherit.copyWith(color: AppColors.muted))),
        Text(value, style: DsStyle.t18w700.copyWith(color: AppColors.title)),
      ]),
    );
  }
}
