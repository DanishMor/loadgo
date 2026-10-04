import 'package:cloud_firestore/cloud_firestore.dart';

import '../enterprise/validators.dart';

/// `users/{uid}.business`. Never verified by LoadGo (LATER(paid): GST API),
/// so the UI always shows it as "Not verified".
class BusinessProfile {
  final String legalName;
  final String gstin;
  final String address;

  const BusinessProfile({this.legalName = '', this.gstin = '', this.address = ''});

  static const empty = BusinessProfile();

  bool get isEmpty => legalName.isEmpty && gstin.isEmpty && address.isEmpty;

  factory BusinessProfile.fromMap(Object? m) {
    final d = m is Map ? m : const {};
    return BusinessProfile(
      legalName: d['legalName'] as String? ?? '',
      gstin: d['gstin'] as String? ?? '',
      address: d['address'] as String? ?? '',
    );
  }

  Map<String, String> toMap() => {'legalName': legalName, 'gstin': gstin, 'address': address};

  /// GSTIN is optional but, when given, must have the right format.
  bool get gstinOk => gstin.isEmpty || isValidGstinFormat(gstin);
}

/// Kind of a business branch. Must stay in sync with firestore.rules.
class BranchType {
  BranchType._();
  static const warehouse = 'warehouse';
  static const factory = 'factory';
  static const port = 'port';
  static const cfs = 'cfs';
  static const all = [warehouse, factory, port, cfs];
}

/// `users/{uid}/branches/{id}`.
class Branch {
  static const maxBranches = 20;

  final String id;
  final String type;
  final String name;
  final String address;
  final String city;

  const Branch({required this.id, required this.type, required this.name, required this.address, required this.city});

  /// Text for a pickup/drop field.
  String get place => [name, if (address.isNotEmpty) address, if (city.isNotEmpty) city].join(', ');

  factory Branch.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Branch(
      id: doc.id,
      type: d['type'] as String? ?? BranchType.warehouse,
      name: d['name'] as String? ?? '',
      address: d['address'] as String? ?? '',
      city: d['city'] as String? ?? '',
    );
  }
}

/// `shipments/{id}`: a two-leg import/export move, origin -> hub -> destination.
class Shipment {
  final String id;
  final String kind; // export | import
  final String origin;
  final String hub;
  final String destination;
  final String containerNumber;
  final String sealNumber;
  final String leg1LoadId;
  final String leg2LoadId;
  final DateTime? createdAt;

  const Shipment({
    required this.id,
    required this.kind,
    required this.origin,
    required this.hub,
    required this.destination,
    required this.containerNumber,
    required this.sealNumber,
    required this.leg1LoadId,
    required this.leg2LoadId,
    this.createdAt,
  });

  static const export = 'export';
  static const import = 'import';

  factory Shipment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Shipment(
      id: doc.id,
      kind: d['kind'] as String? ?? export,
      origin: d['origin'] as String? ?? '',
      hub: d['hub'] as String? ?? '',
      destination: d['destination'] as String? ?? '',
      containerNumber: d['containerNumber'] as String? ?? '',
      sealNumber: d['sealNumber'] as String? ?? '',
      leg1LoadId: d['leg1LoadId'] as String? ?? '',
      leg2LoadId: d['leg2LoadId'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
