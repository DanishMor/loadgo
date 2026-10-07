import 'package:cloud_firestore/cloud_firestore.dart';

/// One document of the demo set.
class DemoDoc {
  final String collection;
  final String id;
  final Map<String, Object?> data;
  const DemoDoc(this.collection, this.id, this.data);
}

/// When demo data may be created or removed. Debug and profile builds always;
/// a release build only when `config/app.allowDemo` is true (demo loads would
/// otherwise show to real drivers).
class DemoGuard {
  DemoGuard._();

  static bool allowed({required bool release, required bool allowDemo}) => !release || allowDemo;
}

/// Pure builders for demo users, vehicles, loads and bookings. Every document
/// has `demo: true` and an id starting with `demo_` (the rules need both).
/// Deterministic: the same [now] gives the same documents. Money is paise.
class DemoSeed {
  DemoSeed._();

  static const idPrefix = 'demo_';
  static const collections = ['users', 'vehicles', 'loads', 'bookings'];

  static const _routes = [
    ('Delhi', 'Jaipur', 280),
    ('Mumbai', 'Pune', 150),
    ('Chennai', 'Bengaluru', 345),
    ('Ahmedabad', 'Surat', 265),
    ('Kolkata', 'Patna', 590),
    ('Hyderabad', 'Nagpur', 500),
  ];
  static const _cargo = ['Steel', 'Cement', 'Furniture', 'Grain', 'Textiles', 'Machinery'];
  static const _vehicleTypes = ['mini_truck', 'lcv', 'truck_14ft', 'truck_20ft'];
  static const _names = ['Asha', 'Bala', 'Chitra', 'Dev', 'Esha', 'Farid'];

  /// [customers] and [drivers] users, one vehicle per driver, [loads] loads
  /// (the first [bookings] of them are booked and delivered).
  static List<DemoDoc> build({int customers = 3, int drivers = 3, int loads = 6, int bookings = 3, DateTime? now}) {
    final at = now ?? DateTime.now();
    final nBookings = bookings.clamp(0, loads).clamp(0, drivers == 0 ? 0 : loads);
    final out = <DemoDoc>[];
    String name(int i) => 'Demo ${_names[i % _names.length]}';
    for (var i = 0; i < customers; i++) {
      out.add(DemoDoc('users', '${idPrefix}c$i', {
        'demo': true,
        'role': 'customer',
        'selectedRole': 'customer',
        'name': name(i),
        'phone': '+91000000${(100 + i).toString().padLeft(4, '0')}',
        'riskTier': 'normal',
        'createdAt': Timestamp.fromDate(at),
      }));
    }
    for (var i = 0; i < drivers; i++) {
      out.add(DemoDoc('users', '${idPrefix}d$i', {
        'demo': true,
        'role': 'driver',
        'selectedRole': 'driver',
        'name': name(i + 3),
        'phone': '+91000000${(200 + i).toString().padLeft(4, '0')}',
        'riskTier': 'normal',
        'verified': true,
        'verificationStatus': 'approved',
        'createdAt': Timestamp.fromDate(at),
      }));
      out.add(DemoDoc('vehicles', '${idPrefix}v$i', {
        'demo': true,
        'ownerId': '${idPrefix}d$i',
        'number': 'DEMO${(1000 + i)}',
        'type': _vehicleTypes[i % _vehicleTypes.length],
        'capacity': 2 + i * 2,
        'rcNumber': 'DEMORC$i',
        'status': 'active',
        'availability': 'available',
        'createdAt': Timestamp.fromDate(at),
      }));
    }
    for (var i = 0; i < loads && customers > 0; i++) {
      final r = _routes[i % _routes.length];
      final booked = i < nBookings;
      final fare = (r.$3 * 2200 + 150000) * 100 ~/ 100;
      final base = <String, Object?>{
        'demo': true,
        'pickup': r.$1,
        'drop': r.$2,
        'cargoType': _cargo[i % _cargo.length],
        'weight': 2 + i,
        'vehicleType': _vehicleTypes[i % _vehicleTypes.length],
        'budget': fare ~/ 100,
        'pickupDate': Timestamp.fromDate(at.add(Duration(days: i + 1))),
        'notes': 'Demo data',
        'paymentMode': 'cash',
        'createdAt': Timestamp.fromDate(at.subtract(Duration(hours: i))),
      };
      final customer = '${idPrefix}c${i % customers}';
      out.add(DemoDoc('loads', '${idPrefix}l$i', {
        ...base,
        'shipperId': customer,
        'status': booked ? 'closed' : 'open',
        if (booked) 'driverId': '${idPrefix}d${i % drivers}',
        if (booked) 'bookingId': '${idPrefix}b$i',
      }));
      if (booked) {
        out.add(DemoDoc('bookings', '${idPrefix}b$i', {
          ...base,
          'loadId': '${idPrefix}l$i',
          'customerId': customer,
          'driverId': '${idPrefix}d${i % drivers}',
          'vehicleId': '${idPrefix}v${i % drivers}',
          'vehicleNumber': 'DEMO${1000 + i % drivers}',
          'driverName': name((i % drivers) + 3),
          'driverPhone': '',
          'status': 'delivered',
          'agreedFarePaise': fare,
          'paymentStatus': 'pending',
          'timeline': {'accepted': Timestamp.fromDate(at.subtract(Duration(hours: i + 2)))},
        }));
      }
    }
    return out;
  }
}
