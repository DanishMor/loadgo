import 'package:flutter/widgets.dart';

import '../features/features.dart';
import '../services/features_service.dart';

/// Shows [child] only while the feature [featureKey] is on (`config/features`).
class FeatureGate extends StatelessWidget {
  final String featureKey;
  final Widget child;
  final Widget otherwise;

  const FeatureGate({super.key, required this.featureKey, required this.child, this.otherwise = const SizedBox.shrink()});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Features>(
        valueListenable: FeaturesService.notifier,
        builder: (context, f, _) => f.isOn(featureKey) ? child : otherwise,
      );
}
