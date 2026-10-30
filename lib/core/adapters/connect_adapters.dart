import 'dart:typed_data';

import 'maps_adapter.dart';

/// E4: the outside services added for the Elite plan. Each one is an interface, a `No...` default
/// (no network, answers notConfigured) and a `Fake...` for tests. Real classes call Cloud Functions,
/// so no key is ever in the app. Built only through `ConnectKit` (connect_registry.dart).

enum ConnectFailure { notConfigured, invalidInput, capped, providerError }

class ConnectResult {
  final String? id;
  final ConnectFailure? failure;
  const ConnectResult.ok(String this.id) : failure = null;
  const ConnectResult.failed(ConnectFailure this.failure) : id = null;
  bool get ok => failure == null;
}

// ---- Toll ----
abstract class TollEstimator {
  /// Approximate toll in paise for one trip, or null when unknown.
  Future<int?> tollPaise(GeoPoint2 from, GeoPoint2 to, {required int axles});
}

class NoTollEstimator implements TollEstimator {
  const NoTollEstimator();
  @override
  Future<int?> tollPaise(GeoPoint2 from, GeoPoint2 to, {required int axles}) async => null;
}

class FakeTollEstimator implements TollEstimator {
  /// Test rate: paise per km per axle (not a real tariff).
  final int paisePerKmAxle;
  const FakeTollEstimator({this.paisePerKmAxle = 50});
  @override
  Future<int?> tollPaise(GeoPoint2 from, GeoPoint2 to, {required int axles}) async {
    if (axles < 2 || axles > 20) return null;
    final km = ((from.lat - to.lat).abs() + (from.lng - to.lng).abs()) * 111;
    return (km * axles * paisePerKmAxle).round();
  }
}

// ---- Demand ----
/// E22: how many open loads start in an area near the driver right now (a server count, never the loads).
class DemandCell {
  final String area;
  final int openLoads;
  const DemandCell(this.area, this.openLoads);
}

abstract class DemandFeed {
  /// The busiest areas near a point, busiest first, at most [max]. Empty when unknown.
  Future<List<DemandCell>> near(GeoPoint2 at, {int max = 5});
}

class NoDemandFeed implements DemandFeed {
  const NoDemandFeed();
  @override
  Future<List<DemandCell>> near(GeoPoint2 at, {int max = 5}) async => const [];
}

class FakeDemandFeed implements DemandFeed {
  final List<DemandCell> cells;
  const FakeDemandFeed([this.cells = const [DemandCell('Bhiwandi', 14), DemandCell('Vashi', 9), DemandCell('Taloja', 4)]]);
  @override
  Future<List<DemandCell>> near(GeoPoint2 at, {int max = 5}) async {
    if (at.lat.abs() > 90 || at.lng.abs() > 180 || max < 1) return const [];
    final sorted = [...cells]..sort((a, b) => b.openLoads.compareTo(a.openLoads));
    return sorted.take(max).toList();
  }
}

// ---- Places ----
enum PlaceKind { fuel, dhaba, mechanic, tyre, weighbridge }

class PlaceHit {
  final String name;
  final PlaceKind kind;
  final GeoPoint2 at;
  const PlaceHit(this.name, this.kind, this.at);
}

/// At most [maxPlaces] results per call.
const maxPlaces = 20;

abstract class PlacesFinder {
  Future<List<PlaceHit>> nearby(GeoPoint2 at, PlaceKind kind, {int radiusMeters = 5000});
}

class NoPlacesFinder implements PlacesFinder {
  const NoPlacesFinder();
  @override
  Future<List<PlaceHit>> nearby(GeoPoint2 at, PlaceKind kind, {int radiusMeters = 5000}) async => const [];
}

class FakePlacesFinder implements PlacesFinder {
  final List<PlaceHit> places;
  const FakePlacesFinder([this.places = const []]);
  @override
  Future<List<PlaceHit>> nearby(GeoPoint2 at, PlaceKind kind, {int radiusMeters = 5000}) async {
    final deg = radiusMeters / 111000;
    return places.where((p) => p.kind == kind && (p.at.lat - at.lat).abs() <= deg && (p.at.lng - at.lng).abs() <= deg).take(maxPlaces).toList();
  }
}

// ---- WhatsApp ----
abstract class WhatsAppGateway {
  /// Only pre-approved templates; [params] fill the template, no free text.
  Future<ConnectResult> sendTemplate(String toE164, String templateId, List<String> params);
}

class NoWhatsAppGateway implements WhatsAppGateway {
  const NoWhatsAppGateway();
  @override
  Future<ConnectResult> sendTemplate(String toE164, String templateId, List<String> params) async => const ConnectResult.failed(ConnectFailure.notConfigured);
}

class FakeWhatsAppGateway implements WhatsAppGateway {
  final List<(String, String, List<String>)> sent = [];
  @override
  Future<ConnectResult> sendTemplate(String toE164, String templateId, List<String> params) async {
    if (!RegExp(r'^\+[1-9]\d{9,14}$').hasMatch(toE164) || templateId.isEmpty || params.length > 10) {
      return const ConnectResult.failed(ConnectFailure.invalidInput);
    }
    sent.add((toE164, templateId, params));
    return ConnectResult.ok('wa${sent.length}');
  }
}

// ---- Payout (legalGatePayout) ----
abstract class PayoutGateway {
  /// [idempotencyKey] makes a retry safe: the same key never pays twice.
  Future<ConnectResult> payout(int amountPaise, String beneficiaryRef, String idempotencyKey);
}

class NoPayoutGateway implements PayoutGateway {
  const NoPayoutGateway();
  @override
  Future<ConnectResult> payout(int amountPaise, String beneficiaryRef, String idempotencyKey) async => const ConnectResult.failed(ConnectFailure.notConfigured);
}

class FakePayoutGateway implements PayoutGateway {
  final Map<String, int> paid = {};
  @override
  Future<ConnectResult> payout(int amountPaise, String beneficiaryRef, String idempotencyKey) async {
    if (amountPaise <= 0 || amountPaise > 10000000 || beneficiaryRef.isEmpty || idempotencyKey.isEmpty) {
      return const ConnectResult.failed(ConnectFailure.invalidInput);
    }
    paid.putIfAbsent(idempotencyKey, () => amountPaise);
    return ConnectResult.ok('po_$idempotencyKey');
  }
}

// ---- Liveness ----
enum LivenessStatus { live, notLive, unavailable }

abstract class LivenessChecker {
  Future<LivenessStatus> check(Uint8List selfieJpeg);
}

class NoLivenessChecker implements LivenessChecker {
  const NoLivenessChecker();
  @override
  Future<LivenessStatus> check(Uint8List selfieJpeg) async => LivenessStatus.unavailable;
}

class FakeLivenessChecker implements LivenessChecker {
  final LivenessStatus answer;
  const FakeLivenessChecker([this.answer = LivenessStatus.live]);
  @override
  Future<LivenessStatus> check(Uint8List selfieJpeg) async => selfieJpeg.isEmpty ? LivenessStatus.notLive : answer;
}

// ---- OCR ----
enum OcrKind { licence, rc, plate }

abstract class OcrReader {
  /// Field name to text. Empty when nothing was read. The person always confirms the result.
  Future<Map<String, String>> read(Uint8List image, OcrKind kind);
}

class NoOcrReader implements OcrReader {
  const NoOcrReader();
  @override
  Future<Map<String, String>> read(Uint8List image, OcrKind kind) async => const {};
}

class FakeOcrReader implements OcrReader {
  final Map<OcrKind, Map<String, String>> answers;
  const FakeOcrReader([this.answers = const {}]);
  @override
  Future<Map<String, String>> read(Uint8List image, OcrKind kind) async => image.isEmpty ? const {} : (answers[kind] ?? const {});
}

// ---- Translation ----
abstract class Translator {
  /// Null when it cannot translate; the original text is then shown.
  Future<String?> translate(String text, {required String from, required String to});
}

class NoTranslator implements Translator {
  const NoTranslator();
  @override
  Future<String?> translate(String text, {required String from, required String to}) async => null;
}

class FakeTranslator implements Translator {
  const FakeTranslator();
  @override
  Future<String?> translate(String text, {required String from, required String to}) async => text.isEmpty || text.length > 1000 ? null : '[$to] $text';
}

// ---- TTS and speech ----
abstract class SpeechAdapter {
  /// False when the phone cannot speak this language; the app then plays a chime.
  Future<bool> speak(String text, String languageCode);

  /// Null when listening is not available or nothing was heard.
  Future<String?> listen(String languageCode);
}

class NoSpeechAdapter implements SpeechAdapter {
  const NoSpeechAdapter();
  @override
  Future<bool> speak(String text, String languageCode) async => false;
  @override
  Future<String?> listen(String languageCode) async => null;
}

class FakeSpeechAdapter implements SpeechAdapter {
  final List<(String, String)> spoken = [];
  String? heard;
  FakeSpeechAdapter({this.heard});
  @override
  Future<bool> speak(String text, String languageCode) async {
    spoken.add((text, languageCode));
    return true;
  }

  @override
  Future<String?> listen(String languageCode) async => heard;
}

// ---- Device telemetry (reefer temperature, GPS box) ----
class DeviceReading {
  final String deviceId;

  /// Tenths of a degree Celsius (integer, no float drift); null when the device has no sensor.
  final int? tempDeci;
  final GeoPoint2? at;
  final DateTime time;
  const DeviceReading(this.deviceId, this.time, {this.tempDeci, this.at});
}

abstract class DeviceTelemetry {
  Future<DeviceReading?> latest(String deviceId);
}

class NoDeviceTelemetry implements DeviceTelemetry {
  const NoDeviceTelemetry();
  @override
  Future<DeviceReading?> latest(String deviceId) async => null;
}

class FakeDeviceTelemetry implements DeviceTelemetry {
  final Map<String, DeviceReading> readings = {};
  @override
  Future<DeviceReading?> latest(String deviceId) async => readings[deviceId];
}

// ---- Insurance (legalGateInsurance): a quote request only, never a sale ----
abstract class InsuranceQuotes {
  Future<ConnectResult> requestQuote({required int cargoValuePaise, required String goods, required String bookingId});
}

class NoInsuranceQuotes implements InsuranceQuotes {
  const NoInsuranceQuotes();
  @override
  Future<ConnectResult> requestQuote({required int cargoValuePaise, required String goods, required String bookingId}) async => const ConnectResult.failed(ConnectFailure.notConfigured);
}

class FakeInsuranceQuotes implements InsuranceQuotes {
  int _n = 0;
  @override
  Future<ConnectResult> requestQuote({required int cargoValuePaise, required String goods, required String bookingId}) async {
    if (cargoValuePaise <= 0 || goods.trim().isEmpty || bookingId.isEmpty) return const ConnectResult.failed(ConnectFailure.invalidInput);
    return ConnectResult.ok('q${++_n}');
  }
}

// ---- Credit partner links (legalGateCredit): a link out only, no lending logic ----
enum CreditLinkKind { fastag, fuelCard, driverAdvance }

abstract class CreditPartnerLinks {
  /// Null when no partner is set up. Only https links are returned.
  Uri? linkFor(CreditLinkKind kind);
}

class NoCreditPartnerLinks implements CreditPartnerLinks {
  const NoCreditPartnerLinks();
  @override
  Uri? linkFor(CreditLinkKind kind) => null;
}

class FakeCreditPartnerLinks implements CreditPartnerLinks {
  final Map<CreditLinkKind, String> links;
  const FakeCreditPartnerLinks([this.links = const {}]);
  @override
  Uri? linkFor(CreditLinkKind kind) {
    final u = Uri.tryParse(links[kind] ?? '');
    return u != null && u.scheme == 'https' && u.host.isNotEmpty ? u : null;
  }
}

// ---- ERP webhooks: signed on the server, the app only queues events ----
abstract class ErpWebhooks {
  Future<ConnectResult> deliver(String event, Map<String, Object?> payload);
}

class NoErpWebhooks implements ErpWebhooks {
  const NoErpWebhooks();
  @override
  Future<ConnectResult> deliver(String event, Map<String, Object?> payload) async => const ConnectResult.failed(ConnectFailure.notConfigured);
}

class FakeErpWebhooks implements ErpWebhooks {
  final List<(String, Map<String, Object?>)> delivered = [];
  @override
  Future<ConnectResult> deliver(String event, Map<String, Object?> payload) async {
    if (!RegExp(r'^[a-z]+(\.[a-z_]+)+$').hasMatch(event) || payload.length > 50) return const ConnectResult.failed(ConnectFailure.invalidInput);
    delivered.add((event, payload));
    return ConnectResult.ok('wh${delivered.length}');
  }
}
