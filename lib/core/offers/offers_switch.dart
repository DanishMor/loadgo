/// `config/offers` admin switches. Promo codes, credits and referral are OFF
/// until an admin turns them on (the rules enforce the same switches).
class OffersSwitch {
  final bool promo;
  final bool credits;
  final bool referral;

  const OffersSwitch({this.promo = false, this.credits = false, this.referral = false});

  static const allOff = OffersSwitch();

  bool get any => promo || credits || referral;

  factory OffersSwitch.fromMap(Map<String, dynamic>? m) => OffersSwitch(
        promo: m?['promoEnabled'] == true,
        credits: m?['creditsEnabled'] == true,
        referral: m?['referralEnabled'] == true,
      );

  Map<String, dynamic> toMap() => {'promoEnabled': promo, 'creditsEnabled': credits, 'referralEnabled': referral};

  OffersSwitch copyWith({bool? promo, bool? credits, bool? referral}) =>
      OffersSwitch(promo: promo ?? this.promo, credits: credits ?? this.credits, referral: referral ?? this.referral);

  @override
  bool operator ==(Object other) => other is OffersSwitch && other.promo == promo && other.credits == credits && other.referral == referral;

  @override
  int get hashCode => Object.hash(promo, credits, referral);
}
