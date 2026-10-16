import 'package:flutter/material.dart';

import 'core/navigation/app_routes.dart';
import 'core/widgets/load_by_id_screen.dart';
import 'customer/booking_tracking_screen.dart';
import 'customer/post_load_screen.dart';
import 'driver/available_loads_view.dart' show AcceptLoadButton;
import 'core/features/features.dart';
import 'core/services/features_service.dart';
import 'core/wallet/hub/hub_screens.dart';
import 'core/wallet/txn_history_screen.dart';
import 'driver/driver_trip_screen.dart';
import 'driver/wallet_entry.dart';

/// Gives core/ the screens it must open but may not import: a booking for
/// either role, a load by id (drivers get Accept) and Post Load from a place.
/// Called once from main().
void registerRouteHooks() {
  AppRoutes.openBooking = (context, id, {required isDriver}) => isDriver ? openDriverTrip(context, id) : openBookingTracking(context, id);
  AppRoutes.openLoad = (context, id, {required isDriver}) => Navigator.of(context).push(MaterialPageRoute(
        builder: (inner) => LoadByIdScreen(
          loadId: id,
          action: isDriver ? (load) => AcceptLoadButton(load: load, onAccepted: (bookingId) => openDriverTrip(inner, bookingId)) : null,
        ),
      ));
  AppRoutes.openWallet = (context, {required isDriver}) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => isDriver
            ? driverWalletPage()
            : (FeaturesService.isOn(FeatureKey.walletHub) ? const CustomerHubScreen() : const TxnHistoryScreen(isDriver: false)),
      ));
  AppRoutes.openPostLoad = (context, {pickup, drop}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostLoadScreen(initialPickup: pickup, initialDrop: drop)));
}
