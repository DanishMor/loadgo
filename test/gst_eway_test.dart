import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/adapters/eway_adapter.dart';
import 'package:transport_app/core/documents/invoice_pdf.dart';
import 'package:transport_app/core/gst/gst_rules.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/invoice.dart';
import 'package:transport_app/core/services/server_actions.dart';

const _mh = '27ABCDE1234F1Z5'; // Maharashtra
const _dl = '07ABCDE1234F1Z5'; // Delhi

TripInvoice _inv({String seller = _mh, String buyer = '', int cgst = 450, int sgst = 450}) => TripInvoice(
      bookingId: 'b1', issuerId: 'd1', customerId: 'c1', number: 'LG/2026-27/00001', seq: 1, fy: '2026-27', gstPercent: 5,
      taxablePaise: 18000, cgstPaise: cgst, sgstPaise: sgst, totalPaise: 18000 + cgst + sgst, sellerName: 'Asha Transport',
      sellerGstin: seller, buyerGstin: buyer,
    );

Booking _booking({String drop = 'Jaipur'}) => Booking.fromMap('b1', {
      'customerId': 'c1', 'driverId': 'd1', 'status': 'delivered', 'pickup': 'Mumbai', 'drop': drop, 'loadId': 'l', 'vehicleId': 'v',
      'cargoType': 'FMCG', 'weight': 2, 'vehicleType': '14ft', 'notes': '', 'vehicleNumber': 'MH12AB1234', 'driverName': 'D', 'driverPhone': '1',
      'timeline': <String, Object?>{},
    });

class _Server implements ServerGateway {
  Object? error;
  Map<String, dynamic> answer = {'number': '331234567890', 'validUntilMs': 1800000000000};
  final calls = <Map<String, Object?>>[];
  @override
  Future<Map<String, dynamic>> call(String name, Map<String, Object?> data) async {
    expect(name, 'ewayGenerate');
    calls.add(data);
    if (error != null) throw error!;
    return answer;
  }
}

void main() {
  group('states and supply kind', () {
    test('the state comes from the first two digits of a GSTIN', () {
      expect(gstinStateName(_mh), 'Maharashtra');
      expect(gstinStateCode(_dl), '07');
      expect(gstinStateName('99ABCDE1234F1Z5'), isNull);
      expect(gstinStateName('x'), isNull);
      expect(gstinStateName(''), isNull);
    });

    test('same state is CGST + SGST, another state is IGST, missing facts are unknown', () {
      expect(supplyKind(sellerGstin: _mh, placeOfSupplyState: 'Maharashtra'), SupplyKind.intraState);
      expect(supplyKind(sellerGstin: _mh, placeOfSupplyState: ' maharashtra '), SupplyKind.intraState);
      expect(supplyKind(sellerGstin: _mh, placeOfSupplyState: 'Rajasthan'), SupplyKind.interState);
      expect(supplyKind(sellerGstin: '', placeOfSupplyState: 'Rajasthan'), SupplyKind.unknown);
      expect(supplyKind(sellerGstin: _mh, placeOfSupplyState: null), SupplyKind.unknown);
    });
  });

  group('e-way bill rules', () {
    test('numbers and vehicles', () {
      expect(isValidEwayBillNo('331234567890'), isTrue);
      for (final bad in ['33123456789', '3312345678901', '33123456789a', '']) {
        expect(isValidEwayBillNo(bad), isFalse, reason: bad);
      }
      expect(isValidEwayVehicle('MH 12-AB 1234'), isTrue);
      expect(isValidEwayVehicle('MH12'), isFalse);
      expect(isValidEwayVehicle('MH12AB1234XYZW'), isFalse);
    });

    test('needed above 50,000 rupees, with the threshold from config', () {
      expect(ewayRequired(5000000), isFalse);
      expect(ewayRequired(5000001), isTrue);
      expect(ewayRequired(100, thresholdPaise: 50), isTrue);
    });

    test('validity: a day for each 200 km or part, at least one; 20 km for over-dimensional cargo', () {
      expect([0, 1, 100, 200, 201, 400, 401, 1000].map(ewayValidityDays), [1, 1, 1, 1, 2, 2, 3, 5]);
      expect(ewayValidityDays(40, overDimensional: true), 2);
      expect(ewayValidityDays(41, overDimensional: true), 3);
    });

    test('valid until the end of the last day, counted from the day it was made', () {
      final made = DateTime(2026, 10, 16, 14, 30);
      expect(ewayValidUntil(made, 150), DateTime(2026, 10, 16, 23, 59, 59));
      expect(ewayValidUntil(made, 450), DateTime(2026, 10, 18, 23, 59, 59));
      expect(ewayValidUntil(DateTime(2026, 12, 31, 9), 250), DateTime(2027, 1, 1, 23, 59, 59), reason: 'across a year end');
    });

    test('request problems are named', () {
      expect(ewayRequestProblems(sellerGstin: _mh, buyerGstin: '', vehicleNumber: 'MH12AB1234', distanceKm: 300, goodsValuePaise: 6000000), isEmpty);
      expect(
        ewayRequestProblems(sellerGstin: 'bad', buyerGstin: 'also bad', vehicleNumber: 'x', distanceKm: 0, goodsValuePaise: 0, hsn: '12'),
        ['sellerGstin', 'buyerGstin', 'vehicle', 'distance', 'value', 'hsn'],
      );
      expect(ewayRequestProblems(sellerGstin: _mh, buyerGstin: _dl, vehicleNumber: 'MH12AB1234', distanceKm: 4001, goodsValuePaise: 1), ['distance']);
    });
  });

  group('contract: every provider answers calmly and checks the request first', () {
    final good = EwayBillRequest(sellerGstin: _mh, vehicleNumber: 'MH12AB1234', distanceKm: 300, goodsValuePaise: 6000000);
    final bad = EwayBillRequest(sellerGstin: 'nope', vehicleNumber: 'x', distanceKm: 0, goodsValuePaise: 0);

    test('the default makes nothing', () async {
      expect((await const NoEwayBillProvider().generate(good)).failure, EwayFailure.notConfigured);
    });

    test('the fake makes a 12-digit number and a validity from the distance; a bad request is refused with the reasons', () async {
      final p = FakeEwayBillProvider(now: () => DateTime(2026, 10, 16, 10));
      final a = await p.generate(good);
      expect(a.ok, isTrue);
      expect(isValidEwayBillNo(a.number!), isTrue);
      expect(a.validUntil, DateTime(2026, 10, 17, 23, 59, 59));
      expect((await p.generate(good)).number, isNot(a.number));
      final r = await p.generate(bad);
      expect((r.ok, r.failure), (false, EwayFailure.invalidRequest));
      expect(r.problems, containsAll(['sellerGstin', 'vehicle', 'distance', 'value']));
    });

    test('the GSP skeleton checks first (no call for a bad request), then follows the server; a missing server is not configured', () async {
      final s = _Server();
      final p = GspEwayBillProvider(s);
      expect((await p.generate(bad)).failure, EwayFailure.invalidRequest);
      expect(s.calls, isEmpty);
      final ok = await p.generate(good);
      expect(ok.number, '331234567890');
      expect(s.calls.single['valuePaise'], 6000000);
      s.answer = {'number': '12', 'validUntilMs': 1};
      expect((await p.generate(good)).failure, EwayFailure.refused);
      s.error = StateError('no function');
      expect((await p.generate(good)).failure, EwayFailure.notConfigured);
    });
  });

  group('invoice fields', () {
    test('place of supply: the buyer GSTIN state first, else the drop city state, else nothing', () {
      expect(invoicePlaceOfSupply(_inv(buyer: _dl), _booking()), 'Delhi');
      expect(invoicePlaceOfSupply(_inv(), _booking(drop: 'Jaipur')), 'Rajasthan');
      expect(invoicePlaceOfSupply(_inv(), _booking(drop: 'Nowhereville')), isNull);
    });

    test('the PDF builds for a same-state invoice, an inter-state one and one with no GSTIN at all', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      for (final inv in [_inv(buyer: _mh), _inv(), _inv(seller: '')]) {
        final bytes = await buildInvoicePdf(inv, _booking());
        expect(bytes.length, greaterThan(1000));
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      }
    });
  });
}
