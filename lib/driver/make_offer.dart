import '../core/models/risk.dart';
import 'package:flutter/material.dart';
import '../core/services/rate_limit_service.dart';

import '../core/l10n/l10n.dart';
import '../core/models/load.dart';
import '../core/models/offer.dart';
import '../core/models/vehicle.dart';
import '../core/services/offer_service.dart';
import '../core/services/vehicle_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/logistics_labels.dart';

/// Driver sends a price for an open load (next to the direct Accept).
class MakeOfferButton extends StatefulWidget {
  final Load load;
  const MakeOfferButton({super.key, required this.load});

  @override
  State<MakeOfferButton> createState() => _MakeOfferButtonState();
}

class _MakeOfferButtonState extends State<MakeOfferButton> {
  bool _busy = false;

  Future<Vehicle?> _pickVehicle(List<Vehicle> vehicles) {
    if (vehicles.length == 1) return Future.value(vehicles.single);
    return showDialog<Vehicle>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(tr(c, 'chooseVehicle')),
        children: [
          for (final v in vehicles)
            SimpleDialogOption(
              onPressed: () => Navigator.of(c).pop(v),
              child: Text('${v.number} • ${vehicleTypeLabel(c, v.type)}'),
            ),
        ],
      ),
    );
  }

  Future<void> _offer() async {
    setState(() => _busy = true);
    try {
      final vehicles = (await VehicleService.fetchMyActive()).where((v) => v.canTakeBooking).toList();
      if (!mounted) return;
      if (vehicles.isEmpty) {
        showSnack(context, tr(context, 'needVehicleFirst'));
        return;
      }
      final vehicle = await _pickVehicle(vehicles);
      if (vehicle == null || !mounted) return;
      final price = await askPricePaise(
        context,
        title: tr(context, 'makeOffer'),
        label: tr(context, 'yourPrice'),
        initialPaise: widget.load.estimate?.total,
      );
      if (price == null || !mounted) return;
      await OfferService.send(load: widget.load, vehicle: vehicle, pricePaise: price);
      if (mounted) showSnack(context, tr(context, 'offerSent'));
    } on AccountRestrictedException {
      if (mounted) showSnack(context, tr(context, 'accountRestricted'));
    } on RateLimitException catch (e) {
      if (mounted) showSnack(context, trf(context, 'rateLimited', {'m': e.minutesLeft}));
    } on OfferExistsException {
      if (mounted) showSnack(context, tr(context, 'offerExists'));
    } on OfferStateException {
      if (mounted) showSnack(context, tr(context, 'loadUnavailable'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: OutlinedButton.icon(
        key: ValueKey('makeOffer_${widget.load.id}'),
        onPressed: _busy ? null : _offer,
        style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        icon: const Icon(Icons.local_offer_outlined),
        label: Text(tr(context, 'makeOffer')),
      ),
    );
  }
}
