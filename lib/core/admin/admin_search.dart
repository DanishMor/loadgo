import '../identity/kyc_validators.dart';
import 'staff_roles.dart';

/// Admin global search (MASTER-6 Task 10): one box for a person's name or
/// phone, a vehicle number, a booking id or an LR number. Firestore cannot
/// search inside text, so the query is classified and each kind is looked up
/// exactly (names by prefix). What a staff role may look up follows
/// `staffAreas`.
enum AdminLookup { booking, lr, vehicle, phone, name }

class AdminSearchPlan {
  /// Lookups to run, with the value each one uses.
  final Map<AdminLookup, String> lookups;
  const AdminSearchPlan(this.lookups);

  bool get isEmpty => lookups.isEmpty;
}

class AdminSearch {
  AdminSearch._();

  /// Staff who may look a vehicle up by its number (the money role may not).
  static const vehicleRoles = [StaffRole.superAdmin, StaffRole.verifier, StaffRole.ops, StaffRole.support];

  static const minLength = 3;
  static const maxLength = 40;

  static final _lr = RegExp(r'^(TR|CS)-\d{4}-\d{1,6}$');
  static final _bookingId = RegExp(r'^[A-Za-z0-9]{15,40}$');

  /// The same cleaning the vehicle form applies; a phone is only its digits.
  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  /// "9876543210", "+91 98765 43210", "09876543210" -> "+919876543210"; null if not a mobile.
  static String? phoneOf(String q) {
    if (RegExp(r'[A-Za-z]').hasMatch(q)) return null;
    if (!isValidIndianMobile(q)) return null;
    final d = _digits(q);
    return '+91${d.substring(d.length - 10)}';
  }

  static AdminSearchPlan plan(String raw, {required String? role}) {
    final q = raw.trim();
    if (q.length < minLength || q.length > maxLength) return const AdminSearchPlan({});
    final out = <AdminLookup, String>{};
    final up = q.toUpperCase().replaceAll(RegExp(r'\s+'), '');
    if (_bookingId.hasMatch(q) && RegExp(r'[A-Za-z]').hasMatch(q) && RegExp(r'[0-9]').hasMatch(q)) out[AdminLookup.booking] = q;
    if (_lr.hasMatch(up)) out[AdminLookup.lr] = up;
    final plate = normaliseDocNumber(q);
    final isPlate = isValidVehicleNumber(plate);
    if (isPlate && vehicleRoles.contains(StaffRole.normalise(role))) out[AdminLookup.vehicle] = plate;
    final phone = phoneOf(q);
    if (phone != null) out[AdminLookup.phone] = phone;
    // A name only when the text is none of the exact kinds (so a plate the role cannot look up is not tried as a name).
    final exactKind = isPlate || phone != null || _lr.hasMatch(up) || out.containsKey(AdminLookup.booking);
    if (RegExp(r'[\p{L}]', unicode: true).hasMatch(q) && !exactKind) out[AdminLookup.name] = q;
    return AdminSearchPlan(out);
  }

  /// Prefix bounds for a name query in the spellings people store: as typed,
  /// Capitalised and Title Case words.
  static List<String> nameVariants(String q) {
    final t = q.trim();
    String cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
    final lower = t.toLowerCase();
    return {t, cap(lower), lower.split(RegExp(r'\s+')).map(cap).join(' ')}.toList();
  }
}

/// One result row.
class AdminHit {
  final AdminLookup kind;
  final String id;
  final String title;
  final String subtitle;

  /// A person to open (the user, or a vehicle's owner); null for bookings and LRs.
  final String? uid;
  final String? bookingId;
  const AdminHit({required this.kind, required this.id, required this.title, this.subtitle = '', this.uid, this.bookingId});
}
