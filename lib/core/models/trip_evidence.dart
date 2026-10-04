import 'package:cloud_firestore/cloud_firestore.dart';

/// Kinds of cargo document a booking can reference (records only: nothing is
/// uploaded or checked against an authority).
class CargoDocType {
  CargoDocType._();
  static const invoice = 'invoice';
  static const packingList = 'packing_list';
  static const billOfLading = 'bill_of_lading';
  static const shippingBill = 'shipping_bill';
  static const billOfEntry = 'bill_of_entry';
  static const certificate = 'certificate';
  static const ewayBill = 'eway_bill';
  static const other = 'other';

  static const all = [invoice, packingList, billOfLading, shippingBill, billOfEntry, certificate, ewayBill, other];
}

/// `bookings/{id}/cargo_docs/{auto}`: append-only reference to a document
/// (type, number, note, which leg). A changed document is a new record, so
/// the history is every record of that type, newest last.
class CargoDoc {
  final String id;
  final String type;
  final String number;
  final String note;
  final int? leg;
  final String addedBy;
  final DateTime? createdAt;

  const CargoDoc({required this.id, required this.type, required this.number, this.note = '', this.leg, required this.addedBy, this.createdAt});

  factory CargoDoc.fromDoc(String id, Map<String, dynamic> d) => CargoDoc(
        id: id,
        type: d['type'] as String? ?? CargoDocType.other,
        number: d['number'] as String? ?? '',
        note: d['note'] as String? ?? '',
        leg: (d['leg'] as num?)?.toInt(),
        addedBy: d['addedBy'] as String? ?? '',
        createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      );

  /// The newest record of each type.
  static Map<String, CargoDoc> latestByType(Iterable<CargoDoc> docs) {
    final out = <String, CargoDoc>{};
    for (final d in docs) {
      final key = '${d.type}#${d.leg ?? 0}';
      final cur = out[key];
      if (cur == null || (d.createdAt ?? DateTime(0)).isAfter(cur.createdAt ?? DateTime(0))) out[key] = d;
    }
    return out;
  }
}

/// A receiver signature drawn on the screen: strokes of normalised points
/// (x and y between 0 and 1). Stored as data, not as an image (images need
/// Storage: LATER(paid)).
class SignatureStrokes {
  final List<List<({double x, double y})>> strokes;
  const SignatureStrokes(this.strokes);

  static const maxStrokes = 30;
  static const maxPointsPerStroke = 200;

  bool get isEmpty => strokes.every((s) => s.length < 2);

  /// Firestore form: arrays of arrays are not allowed, so each stroke is a
  /// map holding a flat list `[x1, y1, x2, y2, ...]`.
  List<Map<String, Object>> toFirestore() => [
        for (final s in strokes.take(maxStrokes))
          if (s.length >= 2)
            {
              'p': [
                for (final p in s.take(maxPointsPerStroke)) ...[_r(p.x), _r(p.y)],
              ]
            },
      ];

  static double _r(double v) => (v.clamp(0, 1) * 1000).round() / 1000;

  factory SignatureStrokes.fromFirestore(Object? raw) {
    final out = <List<({double x, double y})>>[];
    for (final m in (raw as List?) ?? const []) {
      final p = (m is Map ? m['p'] : null) as List? ?? const [];
      final pts = <({double x, double y})>[];
      for (var i = 0; i + 1 < p.length; i += 2) {
        pts.add((x: (p[i] as num).toDouble(), y: (p[i + 1] as num).toDouble()));
      }
      out.add(pts);
    }
    return SignatureStrokes(out);
  }
}
