import 'package:flutter/material.dart';

import 'core/navigation/app_routes.dart';
import 'core/widgets/load_by_id_screen.dart';
import 'customer/booking_tracking_screen.dart';
import 'customer/post_load_screen.dart';
import 'driver/available_loads_view.dart' show AcceptLoadButton;
import 'driver/driver_trip_screen.dart';

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
  AppRoutes.openPostLoad = (context, {pickup, drop}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostLoadScreen(initialPickup: pickup, initialDrop: drop)));
}
