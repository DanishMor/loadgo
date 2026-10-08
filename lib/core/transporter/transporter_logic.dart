import '../constants/logistics.dart';
import '../enterprise/validators.dart';
import '../identity/kyc_validators.dart';
import '../models/booking.dart';
import '../models/fleet.dart';
import '../models/load.dart';
import '../models/vehicle.dart';
import '../trip/trip_eta.dart';

/// Transporter rules (Task 67), all pure so they can be tested without
/// Firebase. The Firestore rules repeat the checks that matter.

/// The company profile of a transporter: `users.companyName`,
/// `users.business.gstin` and `users.fleet.{pan, officeCity, routes,
/// vehicleTypes, vehicleCount}`. Nothing here is verified against a
/// government source (LATER(paid): GST / PAN API); the "Verified transporter"
/// badge comes only from an admin approving the account.
class TransporterProfile {
  final String company;
  final String gstin;
  final String pan;
  final String officeCity;
  final List<String> routes;
  final List<String> vehicleTypes;
  final int vehicleCount;

  const TransporterProfile({
    this.company = '',
    this.gstin = '',
    this.pan = '',
    this.officeCity = '',
    this.routes = const [],
    this.vehicleTypes = const [],
    this.vehicleCount = 0,
  });

  static const maxRoutes = 10;
  static const maxVehicleTypes = 12;
  static const maxVehicles = 100000;

  /// Splits what a person typed ("Indore - Pune, Delhi to Jaipur") into at
  /// most [max] distinct, trimmed entries.
  static List<String> parseList(String raw, {int max = maxRoutes}) {
    final seen = <String>{};
    final out = <String>[];
    for (final part in raw.split(RegExp(r'[,\n;]'))) {
      final p = part.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (p.isEmpty || p.length > 60 || !seen.add(p.toLowerCase())) continue;
      out.add(p);
      if (out.length == max) break;
    }
    return out;
  }

  /// Keys of the fields that are wrong (empty = fine): `company`, `gstin`,
  /// `pan`, `city`, `vehicleCount`. GST is optional but checked when typed.
  List<String> errors() => [
        if (company.trim().length < 2 || company.trim().length > 100) 'company',
        if (gstin.trim().isNotEmpty && !isValidGstin(gstin)) 'gstin',
        if (!isValidPan(pan)) 'pan',
        if (officeCity.trim().length < 2 || officeCity.trim().length > 60) 'city',
        if (vehicleCount < 0 || vehicleCount > maxVehicles) 'vehicleCount',
      ];

  bool get isValid => errors().isEmpty;

  /// The `users.fleet` map written to the profile.
  Map<String, Object?> toFleetMap() => {
        'pan': normaliseDocNumber(pan),
        'officeCity': officeCity.trim(),
        'routes': routes.take(maxRoutes).toList(),
        'vehicleTypes': vehicleTypes.take(maxVehicleTypes).toList(),
        'vehicleCount': vehicleCount,
      };

  /// Reads an old or new `users` document; missing fields stay empty.
  factory TransporterProfile.fromUser(Map<String, dynamic>? u) {
    final fleet = u?['fleet'] is Map ? Map<String, dynamic>.from(u!['fleet'] as Map) : const <String, dynamic>{};
    final business = u?['business'] is Map ? Map<String, dynamic>.from(u!['business'] as Map) : const <String, dynamic>{};
    List<String> strings(Object? v) => v is List ? [for (final x in v) if (x is String && x.isNotEmpty) x] : const [];
    return TransporterProfile(
      company: u?['companyName'] as String? ?? '',
      gstin: business['gstin'] as String? ?? '',
      pan: fleet['pan'] as String? ?? '',
      officeCity: fleet['officeCity'] as String? ?? '',
      routes: strings(fleet['routes']),
      vehicleTypes: strings(fleet['vehicleTypes']),
      vehicleCount: (fleet['vehicleCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// A profile made before Task 67 has no city / count: ask once.
  bool get needsCompletion => officeCity.trim().isEmpty;
}

/// "Verified transporter": the admin approved this account (`users.verified`,
/// only an admin can write it).
bool isVerifiedTransporter(Map<String, dynamic>? user) => user?['role'] == 'fleet' && user?['verified'] == true;

/// One paper of one vehicle that is about to expire or already has.
class DocReminder {
  final Vehicle vehicle;
  final String kind;
  final DateTime expiry;
  final int daysLeft;

  const DocReminder(this.vehicle, this.kind, this.expiry, this.daysLeft);

  bool get expired => daysLeft < 0;
}

/// Reminders for the whole fleet, most urgent first: every paper that expires
/// within [days] (expired ones included) on vehicles that are active. Day
/// granularity, like the booking rules: a paper that expires today still
/// works today (daysLeft 0).
List<DocReminder> docReminders(Iterable<Vehicle> vehicles, DateTime now, {int days = 30}) {
  final today = DateTime(now.year, now.month, now.day);
  final out = <DocReminder>[];
  for (final v in vehicles) {
    if (!v.isActive) continue;
    for (final k in VehicleDocKind.all) {
      final e = v.docs[k]?.expiry;
      if (e == null) continue;
      final left = DateTime(e.year, e.month, e.day).difference(today).inDays;
      if (left <= days) out.add(DocReminder(v, k, e, left));
    }
  }
  out.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
  return out;
}

/// A member driver whose licence ends soon (shared by the driver with this fleet).
class LicenceReminder {
  final FleetMember member;
  final DateTime expiry;
  final int daysLeft;

  const LicenceReminder(this.member, this.expiry, this.daysLeft);

  bool get expired => daysLeft < 0;
}

/// Licences of active members that end within [days] (expired included), soonest first.
/// A member who has not shared a date is not listed.
List<LicenceReminder> licenceReminders(Iterable<FleetMember> members, DateTime now, {int days = 30}) {
  final today = DateTime(now.year, now.month, now.day);
  final out = <LicenceReminder>[];
  for (final m in members) {
    final e = m.licenceExpiry;
    if (!m.active || e == null) continue;
    final left = DateTime(e.year, e.month, e.day).difference(today).inDays;
    if (left <= days) out.add(LicenceReminder(m, e, left));
  }
  out.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
  return out;
}

/// Why a vehicle / driver pair cannot be assigned to a booking, or null when
/// it can. Reasons: `status` (loading is over), `not_member`, `vehicle`
/// (not the transporter's own or an attached one), `busy`, `papers`,
/// `capacity`, `same` (nothing would change).
String? assignmentProblem({
  required Booking booking,
  required String transporterId,
  required Vehicle vehicle,
  required FleetMember? member,
  required DateTime now,
}) {
  const allowed = [BookingStatus.accepted, BookingStatus.driverArriving, BookingStatus.loading];
  if (booking.fleetOwnerId != transporterId || !allowed.contains(booking.status)) return 'status';
  if (member == null || !member.active) return 'not_member';
  if (vehicle.ownerId != transporterId && vehicle.attachedTo != transporterId) return 'vehicle';
  if (!vehicle.isActive || vehicle.papersBlocked(now)) return 'papers';
  final current = booking.assignedVehicleId ?? booking.vehicleId;
  if (vehicle.id != current && vehicle.availability != VehicleAvailability.available) return 'busy';
  if (vehicle.capacity < booking.weight) return 'capacity';
  if (booking.assignedDriverId == member.driverId && current == vehicle.id) return 'same';
  return null;
}

/// A trip of the company that is running late (past the estimate and grace).
class DelayAlert {
  final Booking booking;
  final int minutesLate;

  const DelayAlert(this.booking, this.minutesLate);

  static List<DelayAlert> compute(Iterable<Booking> bookings, DateTime now, int? Function(Booking b) km) {
    final out = <DelayAlert>[];
    for (final b in bookings) {
      final late = TripEta.delayMinutes(b, TripEta.eta(b, km(b)), now);
      if (late != null) out.add(DelayAlert(b, late));
    }
    out.sort((a, b) => b.minutesLate.compareTo(a.minutesLate));
    return out;
  }
}

/// The transporter's books for one trip (`transporter_accounts/{bookingId}`),
/// integer paise, a record only.
class TripAccount {
  final String bookingId;
  final String partyId;
  final String partyName;

  /// What the party pays for the trip.
  final int revenuePaise;

  /// What the transporter owes the driver for it.
  final int driverPayPaise;
  final int otherCostPaise;

  /// What the party has already paid.
  final int receivedPaise;

  const TripAccount({
    required this.bookingId,
    required this.partyId,
    this.partyName = '',
    this.revenuePaise = 0,
    this.driverPayPaise = 0,
    this.otherCostPaise = 0,
    this.receivedPaise = 0,
  });

  int get marginPaise => revenuePaise - driverPayPaise - otherCostPaise;

  /// Still to come from the party (never negative).
  int get dueFromPartyPaise => revenuePaise > receivedPaise ? revenuePaise - receivedPaise : 0;

  factory TripAccount.fromMap(String id, Map<String, dynamic> d) => TripAccount(
        bookingId: id,
        partyId: d['partyId'] as String? ?? '',
        partyName: d['partyName'] as String? ?? '',
        revenuePaise: (d['revenuePaise'] as num?)?.round() ?? 0,
        driverPayPaise: (d['driverPayPaise'] as num?)?.round() ?? 0,
        otherCostPaise: (d['otherCostPaise'] as num?)?.round() ?? 0,
        receivedPaise: (d['receivedPaise'] as num?)?.round() ?? 0,
      );

  /// Whole rupees typed by a person -> paise; null for junk or out of range.
  static int? paiseFromRupees(String raw) {
    final t = raw.trim().replaceAll(',', '');
    if (t.isEmpty) return 0;
    final m = RegExp(r'^(\d{1,9})(?:\.(\d{1,2}))?$').firstMatch(t);
    if (m == null) return null;
    final rupees = int.parse(m.group(1)!);
    final frac = m.group(2) == null ? 0 : int.parse(m.group(2)!.padRight(2, '0'));
    final paise = rupees * 100 + frac;
    return paise > 100000000 ? null : paise;
  }
}

/// A party's total across trips.
class PartyBalance {
  final String partyId;
  final String partyName;
  final int trips;
  final int revenuePaise;
  final int receivedPaise;

  const PartyBalance(this.partyId, this.partyName, this.trips, this.revenuePaise, this.receivedPaise);

  int get duePaise => revenuePaise > receivedPaise ? revenuePaise - receivedPaise : 0;
}

/// The books over all trips: totals and party-wise balance (largest due first).
class TransporterBooks {
  final List<TripAccount> accounts;
  final int revenuePaise;
  final int driverPayPaise;
  final int otherCostPaise;
  final int marginPaise;
  final int dueFromPartiesPaise;
  final List<PartyBalance> parties;

  const TransporterBooks._(this.accounts, this.revenuePaise, this.driverPayPaise, this.otherCostPaise, this.marginPaise, this.dueFromPartiesPaise, this.parties);

  factory TransporterBooks.from(Iterable<TripAccount> accounts) {
    final list = accounts.toList();
    final byParty = <String, List<TripAccount>>{};
    for (final a in list) {
      byParty.putIfAbsent(a.partyId, () => []).add(a);
    }
    final parties = [
      for (final e in byParty.entries)
        PartyBalance(
          e.key,
          e.value.map((a) => a.partyName).firstWhere((n) => n.isNotEmpty, orElse: () => ''),
          e.value.length,
          e.value.fold(0, (s, a) => s + a.revenuePaise),
          e.value.fold(0, (s, a) => s + a.receivedPaise),
        ),
    ]..sort((a, b) => b.duePaise.compareTo(a.duePaise));
    int sum(int Function(TripAccount) f) => list.fold(0, (s, a) => s + f(a));
    return TransporterBooks._(
      list,
      sum((a) => a.revenuePaise),
      sum((a) => a.driverPayPaise),
      sum((a) => a.otherCostPaise),
      sum((a) => a.marginPaise),
      parties.fold(0, (s, p) => s + p.duePaise),
      parties,
    );
  }
}

/// How well an open load fits a transporter's profile (routes, vehicle types,
/// office city). Used to list the loads that fit first and to filter.
class LoadFit {
  final Load load;
  final bool route;
  final bool vehicleType;
  final bool nearOffice;

  const LoadFit(this.load, {this.route = false, this.vehicleType = false, this.nearOffice = false});

  int get score => (route ? 4 : 0) + (vehicleType ? 2 : 0) + (nearOffice ? 1 : 0);

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u0900-\u0dff\u0600-\u06ff ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// "Indore - Pune", "Delhi to Jaipur", "Mumbai → Surat" -> the two ends.
  static (String, String)? routeEnds(String route) {
    final parts = route.split(RegExp(r'\s*(?:-|–|—|→|=>|>|\bto\b)\s*', caseSensitive: false)).map(_norm).where((p) => p.isNotEmpty).toList();
    return parts.length >= 2 ? (parts.first, parts.last) : null;
  }

  static bool _same(String place, String city) => city.isNotEmpty && (place.contains(city) || (city.contains(place) && place.length >= 3));

  /// True when the load runs between the two ends of [route], either way round
  /// (a return load counts).
  static bool onRoute(Load l, String route) {
    final ends = routeEnds(route);
    if (ends == null) return false;
    final a = _norm(l.pickup), b = _norm(l.drop);
    return (_same(a, ends.$1) && _same(b, ends.$2)) || (_same(a, ends.$2) && _same(b, ends.$1));
  }

  static LoadFit of(Load l, TransporterProfile p) => LoadFit(
        l,
        route: p.routes.any((r) => onRoute(l, r)),
        vehicleType: p.vehicleTypes.any((t) => t.trim().toLowerCase() == l.vehicleType.trim().toLowerCase()),
        nearOffice: p.officeCity.trim().length >= 2 && _same(_norm(l.pickup), _norm(p.officeCity)),
      );

  /// Best fit first; loads with the same fit keep their order.
  static List<LoadFit> rank(Iterable<Load> loads, TransporterProfile p) {
    final list = [for (final l in loads) of(l, p)];
    final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])]..sort((a, b) => b.$2.score != a.$2.score ? b.$2.score.compareTo(a.$2.score) : a.$1.compareTo(b.$1));
    return [for (final e in indexed) e.$2];
  }
}
