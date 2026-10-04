import '../constants/prohibited_cargo.dart';
import '../services/vehicle_type_service.dart';

/// At most this many loads per bulk post.
const int maxBulkLoads = 10;

/// One parsed line of a bulk post: `pickup, drop, cargo, weight, vehicleType[, budget]`.
class BulkLoadRow {
  final int line;
  final String pickup;
  final String drop;
  final String cargoType;
  final num weight;
  final String vehicleType;
  final num? budget;

  const BulkLoadRow({
    required this.line,
    required this.pickup,
    required this.drop,
    required this.cargoType,
    required this.weight,
    required this.vehicleType,
    this.budget,
  });
}

enum BulkError { columns, place, weight, vehicleType, tooHeavy, budget, prohibited }

class BulkLineError {
  final int line;
  final BulkError error;
  const BulkLineError(this.line, this.error);
}

class BulkParseResult {
  final List<BulkLoadRow> rows;
  final List<BulkLineError> errors;

  /// More than [maxBulkLoads] non-empty lines were given; the extra ones are ignored.
  final bool tooMany;

  const BulkParseResult(this.rows, this.errors, {this.tooMany = false});

  bool get ok => rows.isNotEmpty && errors.isEmpty && !tooMany;
}

/// Parses pasted CSV lines (comma or tab separated). [vehicleTypeIds] are the
/// valid ids; matching ignores case. Pure, so it is easy to test.
BulkParseResult parseBulkLoads(String text, {required List<String> vehicleTypeIds, num Function(String)? maxTonsFor}) {
  final rows = <BulkLoadRow>[];
  final errors = <BulkLineError>[];
  final lines = text.split('\n').asMap().entries.where((e) => e.value.trim().isNotEmpty).toList();
  final tooMany = lines.length > maxBulkLoads;
  for (final e in lines.take(maxBulkLoads)) {
    final n = e.key + 1;
    final cols = e.value.split(RegExp(r'[,\t]')).map((c) => c.trim()).toList();
    if (cols.length < 5 || cols.length > 6) {
      errors.add(BulkLineError(n, BulkError.columns));
      continue;
    }
    final pickup = cols[0], drop = cols[1], cargo = cols[2];
    final weight = num.tryParse(cols[3]);
    final type = vehicleTypeIds.where((t) => t.toLowerCase() == cols[4].toLowerCase()).firstOrNull;
    final budget = cols.length == 6 && cols[5].isNotEmpty ? num.tryParse(cols[5]) : null;
    if (pickup.length < 2 || drop.length < 2) {
      errors.add(BulkLineError(n, BulkError.place));
    } else if (weight == null || weight <= 0 || weight > 100) {
      errors.add(BulkLineError(n, BulkError.weight));
    } else if (type == null) {
      errors.add(BulkLineError(n, BulkError.vehicleType));
    } else if (maxTonsFor != null && weight > maxTonsFor(type)) {
      errors.add(BulkLineError(n, BulkError.tooHeavy));
    } else if (cols.length == 6 && cols[5].isNotEmpty && (budget == null || budget <= 0)) {
      errors.add(BulkLineError(n, BulkError.budget));
    } else if (prohibitedCargoMatch(cargo) != null) {
      errors.add(BulkLineError(n, BulkError.prohibited));
    } else {
      rows.add(BulkLoadRow(
          line: n, pickup: pickup, drop: drop, cargoType: cargo.isEmpty ? 'General' : cargo, weight: weight, vehicleType: type, budget: budget));
    }
  }
  return BulkParseResult(rows, errors, tooMany: tooMany);
}

/// Max tonnes for a vehicle type id from the live config (unknown: no limit).
num maxTonsOf(String typeId) => VehicleTypeService.byId(typeId)?.maxTons ?? 1000;
