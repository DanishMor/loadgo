import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/design_tokens.dart';
import 'person_kit.dart';
import 'status_badge.dart';

/// A driver in one row: a round initial, the name, the rating, finished trips and a
/// verified mark. Never a phone number. [trust] is a slot for the public trust card;
/// the caller shows it only when `tripTrustCard` is on, so this widget knows no flag.
class DriverMiniCard extends StatelessWidget {
  final String name;
  final double? rating;
  final int trips;
  final bool verified;
  final String? vehicle;
  final Widget? trust;

  const DriverMiniCard({super.key, required this.name, this.rating, this.trips = 0, this.verified = false, this.vehicle, this.trust});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final facts = <String>[
      if (rating != null) rating!.toStringAsFixed(1),
      trips > 0 ? trf(context, 'uxTripsN', {'n': trips}) : tr(context, 'uxNewDriver'),
      if (vehicle != null && vehicle!.isNotEmpty) vehicle!,
    ];
    return Semantics(
      container: true,
      label: '$name. ${verified ? '${tr(context, 'uxVerified')}. ' : ''}${facts.join(', ')}',
      excludeSemantics: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          AppAvatar(name: name, size: 44),
          const SizedBox(width: DsSpace.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: DsType.subtitle.copyWith(color: c.textStrong)),
              Wrap(spacing: DsSpace.s2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (rating != null) Icon(Icons.star_rounded, size: 16, color: c.accentStrong),
                Text(facts.join(' · '), style: DsType.bodySmall.copyWith(color: c.textMuted)),
              ]),
              if (verified) Padding(padding: const EdgeInsets.only(top: DsSpace.s1), child: StatusBadge(label: tr(context, 'uxVerified'), tone: StatusTone.success, icon: Icons.verified_rounded)),
            ]),
          ),
        ]),
        ?trust,
      ]),
    );
  }
}
