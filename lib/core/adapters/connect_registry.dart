import '../features/features.dart';
import 'cost_guard.dart';

/// E4: one line per outside service. [flag] is its switch (a key in docs/FLAGS.md; Elite keys stay
/// `planned` until the feature ships, and an unregistered key is always OFF). [doc] is the owner's
/// connect sheet. [caps] are the cost limits; [paid] is false only for services that cost nothing per call.
class ConnectSpec {
  final String id;
  final String flag;
  final String doc;
  final CostCaps caps;
  final bool paid;
  const ConnectSpec(this.id, this.flag, this.doc, this.caps, {this.paid = true});
}

/// `config/providers` (super admin writes, signed-in users read): `{<id>: {configured: bool, daily: int, perUser: int}}`.
/// `configured` is set by the owner after the key is saved as a server secret. No key is ever in this document.
class ProviderConfig {
  final Map<String, Map<String, dynamic>> byId;
  const ProviderConfig([this.byId = const {}]);

  factory ProviderConfig.fromMap(Map<String, dynamic>? m) => ProviderConfig({
        for (final e in (m ?? const {}).entries)
          if (e.value is Map) e.key: Map<String, dynamic>.from(e.value as Map),
      });

  bool configured(String id) => byId[id]?['configured'] == true;
}

class ConnectKit {
  ConnectKit._();

  static const specs = <ConnectSpec>[
    ConnectSpec('photo', FeatureKey.photoUploads, 'docs/CONNECT_PHOTO.md', CostCaps(daily: 2000, perUser: 40)),
    ConnectSpec('maps', FeatureKey.maps, 'docs/CONNECT_MAPS.md', CostCaps(daily: 3000, perUser: 60)),
    ConnectSpec('toll', 'tollEstimate', 'docs/CONNECT_TOLL.md', CostCaps(daily: 1000, perUser: 30)),
    ConnectSpec('places', 'nearbyServices', 'docs/CONNECT_PLACES.md', CostCaps(daily: 1000, perUser: 30)),
    ConnectSpec('push', FeatureKey.pushNotifications, 'docs/CONNECT_PUSH.md', CostCaps(daily: 20000, perUser: 50), paid: false),
    ConnectSpec('sms', FeatureKey.smsGateway, 'docs/CONNECT_SMS.md', CostCaps(daily: 200, perUser: 5)),
    ConnectSpec('whatsapp', 'whatsappGateway', 'docs/CONNECT_WHATSAPP.md', CostCaps(daily: 500, perUser: 10)),
    ConnectSpec('payment', FeatureKey.paymentGateway, 'docs/CONNECT_PAYMENT.md', CostCaps(daily: 1000, perUser: 20)),
    ConnectSpec('payout', 'legalGatePayout', 'docs/CONNECT_PAYOUT.md', CostCaps(daily: 200, perUser: 3)),
    ConnectSpec('kyc', FeatureKey.kycVerify, 'docs/CONNECT_KYC.md', CostCaps(daily: 300, perUser: 5)),
    ConnectSpec('liveness', 'kycLiveness', 'docs/CONNECT_LIVENESS.md', CostCaps(daily: 300, perUser: 3)),
    ConnectSpec('ocr', 'ocrAutofill', 'docs/CONNECT_OCR.md', CostCaps(daily: 500, perUser: 10)),
    ConnectSpec('translation', 'autoTranslate', 'docs/CONNECT_TRANSLATION.md', CostCaps(daily: 5000, perUser: 200)),
    ConnectSpec('speech', 'voiceAnnounce', 'docs/CONNECT_SPEECH.md', CostCaps(daily: 5000, perUser: 300), paid: false),
    ConnectSpec('telemetry', 'deviceIngest', 'docs/CONNECT_TELEMETRY.md', CostCaps(daily: 5000, perUser: 500)),
    ConnectSpec('insurance', 'legalGateInsurance', 'docs/CONNECT_INSURANCE.md', CostCaps(daily: 100, perUser: 3)),
    ConnectSpec('credit', 'legalGateCredit', 'docs/CONNECT_CREDIT.md', CostCaps(daily: 500, perUser: 10), paid: false),
    ConnectSpec('erp', 'erpApi', 'docs/CONNECT_ERP.md', CostCaps(daily: 5000, perUser: 1000)),
  ];

  static ConnectSpec spec(String id) => specs.firstWhere((s) => s.id == id);

  /// True only when the switch is ON and the owner marked the provider configured. Otherwise the
  /// app keeps the `No...` default: no paid call can happen by default.
  static bool useReal(String id, Features features, ProviderConfig providers) => features.isOn(spec(id).flag) && providers.configured(id);

  /// Picks the real adapter or the safe default.
  static T pick<T>(String id, Features features, ProviderConfig providers, {required T Function() real, required T fallback}) =>
      useReal(id, features, providers) ? real() : fallback;

  /// A guard whose kill switch is the adapter's own flag: switching the flag (or its kill group) off stops calls at once.
  static CostGuard guard(String id, Features Function() features, ProviderConfig providers, {DateTime Function()? now}) {
    final s = spec(id);
    return CostGuard(s.caps.lowered(providers.byId[id]), killed: () => !features().isOn(s.flag), now: now);
  }
}
