import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/services/match_service.dart';
import '../core/widgets/common.dart';

/// "N matching vehicles available" for the load being posted. Re-counts when
/// the vehicle type or weight changes; stays silent while the weight is
/// missing or the lookup fails.
class MatchingVehiclesLine extends StatefulWidget {
  final String vehicleType;
  final num? weight;

  const MatchingVehiclesLine({super.key, required this.vehicleType, required this.weight});

  @override
  State<MatchingVehiclesLine> createState() => _MatchingVehiclesLineState();
}

class _MatchingVehiclesLineState extends State<MatchingVehiclesLine> {
  int? _count;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MatchingVehiclesLine old) {
    super.didUpdateWidget(old);
    if (old.vehicleType != widget.vehicleType || old.weight != widget.weight) _load();
  }

  Future<void> _load() async {
    final w = widget.weight;
    final id = ++_request;
    if (w == null || w <= 0) {
      setState(() => _count = null);
      return;
    }
    try {
      final n = await MatchService.countMatchingVehicles(vehicleType: widget.vehicleType, weight: w);
      if (mounted && id == _request) setState(() => _count = n);
    } catch (_) {
      if (mounted && id == _request) setState(() => _count = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = _count;
    if (n == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        Icon(n > 0 ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
            size: 18, color: n > 0 ? AppColors.success : AppColors.warning),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            n > 0 ? trf(context, 'matchingVehiclesCount', {'n': n}) : tr(context, 'noMatchingVehicles'),
            key: const ValueKey('matchingVehicles'),
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          ),
        ),
      ]),
    );
  }
}
