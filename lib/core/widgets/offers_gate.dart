import 'package:flutter/material.dart';

import '../offers/offers_switch.dart';
import '../services/offers_switch_service.dart';

/// Shows [child] only while [test] is true for the admin switches in
/// `config/offers` (promo, credits and referral are OFF by default).
class OffersGate extends StatelessWidget {
  final bool Function(OffersSwitch s) test;
  final Widget child;

  const OffersGate({super.key, required this.test, required this.child});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<OffersSwitch>(
        valueListenable: OffersSwitchService.notifier,
        builder: (context, s, _) => test(s) ? child : const SizedBox.shrink(),
      );
}
