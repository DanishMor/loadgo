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

/// E29 (flag bulkUpload): the header row of the template; a first line that starts with "pickup" is skipped.
const bulkHeader = 'pickup,drop,cargo,weight_t,vehicle_type,budget_rupees';

/// E29: a CSV template with the header and two example rows (the first vehicle type ids given).
String bulkTemplate(List<String> vehicleTypeIds) {
  final a = vehicleTypeIds.isEmpty ? '14ft' : vehicleTypeIds.first;
  final b = vehicleTypeIds.length > 1 ? vehicleTypeIds[1] : a;
  return '$bulkHeader\nPune,Mumbai,FMCG cartons,3,$a,18000\n"Bhiwandi, Thane",Surat,Textile rolls,5.5,$b,\n';
}

/// E29: one CSV line as Excel writes it: comma, tab or semicolon separated, "quoted" fields may hold separators,
/// and "" inside quotes is one quote.
List<String> splitCsvLine(String line) {
  final out = <String>[];
  final cur = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          cur.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cur.write(ch);
      }
    } else if (ch == '"' && cur.toString().trim().isEmpty) {
      quoted = true;
      cur.clear();
    } else if (ch == ',' || ch == '\t' || ch == ';') {
      out.add(cur.toString().trim());
      cur.clear();
    } else {
      cur.write(ch);
    }
  }
  out.add(cur.toString().trim());
  return out;
}

/// Parses pasted CSV lines (comma or tab separated). [vehicleTypeIds] are the
/// valid ids; matching ignores case. Pure, so it is easy to test. With [v2] (E29, flag bulkUpload): a byte-order mark
/// and the template header row are dropped, and quoted fields and semicolons work (CSV saved from Excel); line
/// numbers still count from the first line of the text.
BulkParseResult parseBulkLoads(String text, {required List<String> vehicleTypeIds, num Function(String)? maxTonsFor, bool v2 = false}) {
  final rows = <BulkLoadRow>[];
  final errors = <BulkLineError>[];
  final body = v2 && text.startsWith('\uFEFF') ? text.substring(1) : text;
  var lines = body.split('\n').asMap().entries.where((e) => e.value.trim().isNotEmpty).toList();
  if (v2 && lines.isNotEmpty && lines.first.value.trim().toLowerCase().replaceAll('"', '').startsWith('pickup')) lines = lines.skip(1).toList();
  final tooMany = lines.length > maxBulkLoads;
  for (final e in lines.take(maxBulkLoads)) {
    final n = e.key + 1;
    final cols = v2 ? splitCsvLine(e.value.replaceAll('\r', '')) : e.value.split(RegExp(r'[,\t]')).map((c) => c.trim()).toList();
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
