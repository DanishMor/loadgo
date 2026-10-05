import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/booking.dart';
import '../models/load.dart';
import '../models/offer.dart';
import '../models/vehicle.dart';
import '../reminders/reminders.dart';
import 'backend.dart';
import 'booking_service.dart';
import 'load_service.dart';
import 'offer_service.dart';
import 'vehicle_service.dart';
import 'settings_service.dart';
import 'pricing_service.dart';
import '../trip/trip_eta.dart';

/// Live in-app reminders for the signed-in user: the latest bookings, loads,
/// offers, vehicles and licence expiry fed through [ReminderEngine], and
/// re-worked every minute so "pickup in 40 minutes" stays current.
class ReminderService {
  ReminderService._();

  /// Re-evaluation period (the rules depend on the clock).
  static const tick = Duration(minutes: 1);

  static Stream<List<Reminder>> watch({required bool isDriver, DateTime Function()? clock}) {
    final now = clock ?? DateTime.now;
    late StreamController<List<Reminder>> out;
    final subs = <StreamSubscription<dynamic>>[];
    Timer? timer;

    var bookings = const <Booking>[];
    var loads = const <Load>[];
    var offers = const <Offer>[];
    var vehicles = const <Vehicle>[];
    DateTime? licence;

    void emit() {
      if (out.isClosed) return;
      final prefs = SettingsService.prefs.value;
      out.add([for (final r in ReminderEngine.compute(ReminderInput(
        now: now(),
        isDriver: isDriver,
        bookings: bookings,
        loads: loads,
        offers: offers,
        vehicles: vehicles,
        licenceExpiry: licence,
        etaOf: (b) => TripEta.eta(b, PricingService.estimateRouteKm([b.pickup, ...b.extraPickups, ...b.extraDrops, b.drop])),
      ))) if (prefs.allowsReminder(r.kind)) r]);
    }

    void onPrefs() => emit();

    void listen<T>(Stream<T> s, void Function(T) onData) {
      subs.add(s.listen((v) {
        onData(v);
        emit();
      }, onError: (_) {}));
    }

    out = StreamController<List<Reminder>>(
      onListen: () {
        if (isDriver) {
          listen(BookingService.watchForDriver(), (v) => bookings = v);
          listen(OfferService.watchMine(), (v) => offers = v);
          listen(LoadService.watchOpen(), (v) => loads = v);
          listen(VehicleService.watchMine(), (v) => vehicles = v);
          final uid = Backend.uid;
          if (uid != null) {
            listen(Backend.db.collection('users').doc(uid).snapshots(), (DocumentSnapshot<Map<String, dynamic>> s) {
              licence = ((s.data()?['driverKyc'] as Map?)?['dlExpiry'] as Timestamp?)?.toDate();
            });
          }
        } else {
          listen(BookingService.watchForCustomer(), (v) => bookings = v);
          listen(LoadService.watchMine(), (v) => loads = v);
          listen(OfferService.watchForCustomer(), (v) => offers = v);
        }
        SettingsService.prefs.addListener(onPrefs);
        emit();
        timer = Timer.periodic(tick, (_) => emit());
      },
      onCancel: () async {
        SettingsService.prefs.removeListener(onPrefs);
        timer?.cancel();
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return out.stream;
  }
}
