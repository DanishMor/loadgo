import '../gst/gst_rules.dart';
import '../services/server_actions.dart';

/// What the GST portal (through a GSP) needs to make an e-way bill. Money in paise.
class EwayBillRequest {
  final String sellerGstin;
  final String buyerGstin;
  final String vehicleNumber;
  final int distanceKm;
  final int goodsValuePaise;
  final String hsn;
  final String invoiceNumber;
  const EwayBillRequest({
    required this.sellerGstin,
    this.buyerGstin = '',
    required this.vehicleNumber,
    required this.distanceKm,
    required this.goodsValuePaise,
    this.hsn = '996511',
    this.invoiceNumber = '',
  });
}

enum EwayFailure { notConfigured, invalidRequest, refused, unavailable }

class EwayBillResult {
  final String? number;
  final DateTime? validUntil;
  final EwayFailure? failure;
  final List<String> problems;
  const EwayBillResult.made(String this.number, DateTime this.validUntil)
      : failure = null,
        problems = const [];
  const EwayBillResult.failed(EwayFailure this.failure, [this.problems = const []])
      : number = null,
        validUntil = null;
  bool get ok => number != null;
}

/// LATER(paid): a GST Suvidha Provider (GSP). Today the app only RECORDS an e-way bill number the person made on the
/// portal; this interface is where a paid GSP plugs in. Checks of the request are free and run first.
abstract class EwayBillProvider {
  Future<EwayBillResult> generate(EwayBillRequest request);
}

/// Default: nothing is generated, the person keeps using the portal.
class NoEwayBillProvider implements EwayBillProvider {
  const NoEwayBillProvider();
  @override
  Future<EwayBillResult> generate(EwayBillRequest request) async => const EwayBillResult.failed(EwayFailure.notConfigured);
}

List<String> _problems(EwayBillRequest r) => ewayRequestProblems(
      sellerGstin: r.sellerGstin,
      buyerGstin: r.buyerGstin,
      vehicleNumber: r.vehicleNumber,
      distanceKm: r.distanceKm,
      goodsValuePaise: r.goodsValuePaise,
      hsn: r.hsn,
    );

/// For tests and demos: checks the request like the portal would and invents a 12-digit number.
class FakeEwayBillProvider implements EwayBillProvider {
  final DateTime Function() now;
  int _n = 0;
  FakeEwayBillProvider({DateTime Function()? now}) : now = now ?? DateTime.now;

  @override
  Future<EwayBillResult> generate(EwayBillRequest request) async {
    final p = _problems(request);
    if (p.isNotEmpty) return EwayBillResult.failed(EwayFailure.invalidRequest, p);
    final number = (330000000000 + ++_n).toString();
    return EwayBillResult.made(number, ewayValidUntil(now(), request.distanceKm));
  }
}

/// A GSP behind the `ewayGenerate` server function (skeleton: the function is not written until a GSP is chosen,
/// so every call answers "not configured" and the app keeps recording the number by hand).
class GspEwayBillProvider implements EwayBillProvider {
  final ServerGateway server;
  GspEwayBillProvider([ServerGateway? server]) : server = server ?? ServerActions.gateway;

  @override
  Future<EwayBillResult> generate(EwayBillRequest request) async {
    final p = _problems(request);
    if (p.isNotEmpty) return EwayBillResult.failed(EwayFailure.invalidRequest, p);
    try {
      final r = await server.call('ewayGenerate', {
        'sellerGstin': request.sellerGstin,
        'buyerGstin': request.buyerGstin,
        'vehicle': request.vehicleNumber,
        'distanceKm': request.distanceKm,
        'valuePaise': request.goodsValuePaise,
        'hsn': request.hsn,
        'invoice': request.invoiceNumber,
      });
      final no = r['number'];
      final until = r['validUntilMs'];
      if (no is String && isValidEwayBillNo(no) && until is int) {
        return EwayBillResult.made(no, DateTime.fromMillisecondsSinceEpoch(until));
      }
      return const EwayBillResult.failed(EwayFailure.refused);
    } catch (_) {
      return const EwayBillResult.failed(EwayFailure.notConfigured);
    }
  }
}
