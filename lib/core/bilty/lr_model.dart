import 'package:cloud_firestore/cloud_firestore.dart';

/// Copy types of an LR (Task 70).
class LrCopy {
  LrCopy._();
  static const full = 'full';
  static const driver = 'driver';
  static const consignee = 'consignee';
  static const all = [full, driver, consignee];
}

class LrStatus {
  LrStatus._();
  static const issued = 'issued';
  static const superseded = 'superseded';
  static const cancelled = 'cancelled';
}

/// Who made the LR. The customer's one is a "Consignor LR / booking slip".
class LrIssuerRole {
  LrIssuerRole._();
  static const transporter = 'transporter';
  static const customer = 'customer';
}

/// Owner's choice for the compliance group (goods value, invoice no, party
/// GSTIN, e-way bill no) towards the driver (Task 71). Default hide.
class ComplianceMode {
  ComplianceMode._();
  static const hide = 'hide';
  static const show = 'show';
  static const inspectionOnRequest = 'inspection_on_request';
  static const all = [hide, show, inspectionOnRequest];
  static String normalise(Object? v) => all.contains(v) ? v as String : hide;
}

/// Field keys used in a copy's snapshot. The three groups are the privacy
/// model: public (everyone with the copy), rate (freight, advance, balance,
/// margin, GST) and compliance; phones sit with the rate group.
class LrFields {
  LrFields._();
  static const publicKeys = ['lrNo', 'date', 'route', 'goods', 'packages', 'weightTons', 'vehicleNumber', 'driverName', 'consignorName', 'consigneeName', 'issuerName', 'status', 'version'];
  static const rateKeys = ['freightPaise', 'advancePaise', 'balancePaise', 'gstPaise'];
  static const marginKey = 'marginPaise';
  static const phoneKeys = ['consignorPhone', 'consigneePhone'];
  static const complianceKeys = ['goodsValuePaise', 'invoiceNo', 'consignorGstin', 'consigneeGstin', 'ewayBillNo', 'ewayValidUntil'];
  static const verifyKeys = ['lrNo', 'route', 'status', 'issuerName'];
}

/// "TR-2026-000012": prefix by issuer role, calendar year, 6-digit number.
String lrNumber(String issuerRole, int year, int seq) =>
    '${issuerRole == LrIssuerRole.transporter ? 'TR' : 'CS'}-$year-${seq.toString().padLeft(6, '0')}';

String lrDocId(String issuerId, int year, int seq, int version) => '${issuerId}_${year}_${seq}_v$version';

DateTime? _dt(Object? v) => v is Timestamp ? v.toDate() : null;

/// The public part: lrs/{lrId}.
class LrPublic {
  final String id;
  final String bookingId;
  final String issuerId;
  final String issuerRole;
  final String customerId;
  final String? fleetOwnerId;
  final String lrNo;
  final int seq;
  final int year;
  final int version;
  final String status;
  final String cancelReason;
  final int? supersededBy;
  final DateTime? date;
  final String pickup;
  final String drop;
  final String route;
  final String goods;
  final int packages;
  final num weightTons;
  final String vehicleNumber;
  final String driverName;
  final String consignorName;
  final String consigneeName;
  final String issuerName;
  final String complianceMode;

  const LrPublic({
    required this.id,
    required this.bookingId,
    required this.issuerId,
    required this.issuerRole,
    required this.customerId,
    this.fleetOwnerId,
    required this.lrNo,
    required this.seq,
    required this.year,
    required this.version,
    required this.status,
    this.cancelReason = '',
    this.supersededBy,
    this.date,
    this.pickup = '',
    this.drop = '',
    this.route = '',
    this.goods = '',
    this.packages = 0,
    this.weightTons = 0,
    this.vehicleNumber = '',
    this.driverName = '',
    this.consignorName = '',
    this.consigneeName = '',
    this.issuerName = '',
    this.complianceMode = ComplianceMode.hide,
  });

  bool get isCurrent => status == LrStatus.issued;
  bool get isCancelled => status == LrStatus.cancelled;
  bool get isSlip => issuerRole == LrIssuerRole.customer;

  factory LrPublic.fromDoc(String id, Map<String, dynamic> d) => LrPublic(
        id: id,
        bookingId: d['bookingId'] as String? ?? '',
        issuerId: d['issuerId'] as String? ?? '',
        issuerRole: d['issuerRole'] as String? ?? LrIssuerRole.transporter,
        customerId: d['customerId'] as String? ?? '',
        fleetOwnerId: d['fleetOwnerId'] as String?,
        lrNo: d['lrNo'] as String? ?? '',
        seq: (d['seq'] as num?)?.toInt() ?? 0,
        year: (d['year'] as num?)?.toInt() ?? 0,
        version: (d['version'] as num?)?.toInt() ?? 1,
        status: d['status'] as String? ?? LrStatus.issued,
        cancelReason: d['cancelReason'] as String? ?? '',
        supersededBy: (d['supersededBy'] as num?)?.toInt(),
        date: _dt(d['date']),
        pickup: d['pickup'] as String? ?? '',
        drop: d['drop'] as String? ?? '',
        route: d['route'] as String? ?? '',
        goods: d['goods'] as String? ?? '',
        packages: (d['packages'] as num?)?.toInt() ?? 0,
        weightTons: d['weightTons'] as num? ?? 0,
        vehicleNumber: d['vehicleNumber'] as String? ?? '',
        driverName: d['driverName'] as String? ?? '',
        consignorName: d['consignorName'] as String? ?? '',
        consigneeName: d['consigneeName'] as String? ?? '',
        issuerName: d['issuerName'] as String? ?? '',
        complianceMode: ComplianceMode.normalise(d['complianceMode']),
      );

  /// What a snapshot of the public group holds, keyed by [LrFields.publicKeys].
  Map<String, Object> publicFields() => {
        'lrNo': lrNo,
        if (date != null) 'date': date!.toIso8601String().substring(0, 10),
        'route': route.isEmpty ? '$pickup → $drop' : route,
        'goods': goods,
        'packages': packages,
        'weightTons': weightTons,
        'vehicleNumber': vehicleNumber,
        'driverName': driverName,
        'consignorName': consignorName,
        'consigneeName': consigneeName,
        'issuerName': issuerName,
        'status': status,
        'version': version,
      };
}

/// lrs/{id}/private/details: the rate group, GST and phones. Paise are integers.
class LrDetails {
  final int freightPaise;
  final int advancePaise;
  final int balancePaise;
  final int marginPaise;
  final int gstPaise;
  final String consignorPhone;
  final String consigneePhone;
  const LrDetails({this.freightPaise = 0, this.advancePaise = 0, this.balancePaise = 0, this.marginPaise = 0, this.gstPaise = 0, this.consignorPhone = '', this.consigneePhone = ''});

  factory LrDetails.fromMap(Map<String, dynamic> d) => LrDetails(
        freightPaise: (d['freightPaise'] as num?)?.toInt() ?? 0,
        advancePaise: (d['advancePaise'] as num?)?.toInt() ?? 0,
        balancePaise: (d['balancePaise'] as num?)?.toInt() ?? 0,
        marginPaise: (d['marginPaise'] as num?)?.toInt() ?? 0,
        gstPaise: (d['gstPaise'] as num?)?.toInt() ?? 0,
        consignorPhone: d['consignorPhone'] as String? ?? '',
        consigneePhone: d['consigneePhone'] as String? ?? '',
      );

  Map<String, Object> toMap() => {
        'freightPaise': freightPaise,
        'advancePaise': advancePaise,
        'balancePaise': balancePaise,
        'marginPaise': marginPaise,
        'gstPaise': gstPaise,
        'consignorPhone': consignorPhone,
        'consigneePhone': consigneePhone,
      };
}

/// lrs/{id}/private/compliance: goods value, invoice no, party GSTIN, e-way bill record.
/// LATER(paid): generate the e-way bill through a GSP API; today this is only a record.
class LrCompliance {
  final int goodsValuePaise;
  final String invoiceNo;
  final String consignorGstin;
  final String consigneeGstin;
  final String ewayBillNo;
  final DateTime? ewayValidUntil;
  const LrCompliance({this.goodsValuePaise = 0, this.invoiceNo = '', this.consignorGstin = '', this.consigneeGstin = '', this.ewayBillNo = '', this.ewayValidUntil});

  factory LrCompliance.fromMap(Map<String, dynamic> d) => LrCompliance(
        goodsValuePaise: (d['goodsValuePaise'] as num?)?.toInt() ?? 0,
        invoiceNo: d['invoiceNo'] as String? ?? '',
        consignorGstin: d['consignorGstin'] as String? ?? '',
        consigneeGstin: d['consigneeGstin'] as String? ?? '',
        ewayBillNo: d['ewayBillNo'] as String? ?? '',
        ewayValidUntil: _dt(d['ewayValidUntil']),
      );

  Map<String, Object> toMap() => {
        'goodsValuePaise': goodsValuePaise,
        'invoiceNo': invoiceNo,
        'consignorGstin': consignorGstin,
        'consigneeGstin': consigneeGstin,
        'ewayBillNo': ewayBillNo,
        if (ewayValidUntil != null) 'ewayValidUntil': Timestamp.fromDate(ewayValidUntil!),
      };

  bool get isEmpty => goodsValuePaise == 0 && invoiceNo.isEmpty && consignorGstin.isEmpty && consigneeGstin.isEmpty && ewayBillNo.isEmpty;
}

/// An LR with the parts the viewer was allowed to read (null = not readable).
class LrBundle {
  final LrPublic pub;
  final LrDetails? details;
  final LrCompliance? compliance;
  const LrBundle(this.pub, {this.details, this.compliance});
}
