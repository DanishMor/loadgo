import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../identity/masking.dart';
import '../l10n/l10n.dart';
import 'common.dart';

/// Status of one identity item. LoadGo only checks formats and reviews
/// drivers by hand; nothing is verified against an official source yet
/// (LATER(paid): Parivahan / NSDL / GST / UIDAI partners).
enum BadgeState { verifiedByOtp, reviewed, providedUnverified, missing }

class BadgeItem {
  final String labelKey;
  final String? value;
  final BadgeState state;

  /// The value before masking, for admins who tap "show".
  final String? raw;

  const BadgeItem({required this.labelKey, this.value, required this.state, this.raw});
}

/// The badges for one user document: per document type, not one flag.
List<BadgeItem> verificationBadges(Map<String, dynamic> user, {required bool isDriver}) {
  final reviewed = user['verified'] == true;
  BadgeState docState(String? v) => (v == null || v.isEmpty)
      ? BadgeState.missing
      : (reviewed ? BadgeState.reviewed : BadgeState.providedUnverified);
  final out = <BadgeItem>[
    BadgeItem(
      labelKey: 'phone',
      state: (user['phone'] as String?)?.isNotEmpty == true ? BadgeState.verifiedByOtp : BadgeState.missing,
    ),
  ];
  if (isDriver) {
    final k = (user['driverKyc'] as Map?) ?? const {};
    String? s(String key) => k[key] as String?;
    out.addAll([
      BadgeItem(labelKey: 'dlNumber', value: maskId(s('dlNumber')), raw: s('dlNumber'), state: docState(s('dlNumber'))),
      BadgeItem(labelKey: 'panNumber', value: maskId(s('pan')), raw: s('pan'), state: docState(s('pan'))),
      BadgeItem(labelKey: 'rcVehicleNumber', value: maskId(s('rcNumber')), raw: s('rcNumber'), state: docState(s('rcNumber'))),
      BadgeItem(labelKey: 'aadhaarLast4', value: maskAadhaarLast4(s('aadhaarLast4')), raw: maskAadhaarLast4(s('aadhaarLast4')), state: docState(s('aadhaarLast4'))),
    ]);
  } else {
    final gst = (user['business'] as Map?)?['gstin'] as String?;
    if (gst != null && gst.isNotEmpty) {
      out.add(BadgeItem(labelKey: 'gstin', value: maskId(gst), raw: gst, state: BadgeState.providedUnverified));
    }
  }
  return out;
}

/// Who reviewed the account and when (`verificationMeta`), if anyone did.
({String source, DateTime? at})? reviewInfo(Map<String, dynamic> user) {
  final m = user['verificationMeta'];
  if (m is! Map) return null;
  return (source: m['source'] as String? ?? '', at: (m['at'] as Timestamp?)?.toDate());
}

/// Per-type verification badges. Values are masked unless [reveal].
class VerificationBadges extends StatelessWidget {
  final Map<String, dynamic> user;
  final bool isDriver;
  final bool reveal;

  const VerificationBadges({super.key, required this.user, required this.isDriver, this.reveal = false});

  (String, Color) _look(BuildContext context, BadgeState s) => switch (s) {
        BadgeState.verifiedByOtp => (tr(context, 'badgeOtpVerified'), AppColors.success),
        BadgeState.reviewed => (tr(context, 'badgeReviewed'), AppColors.success),
        BadgeState.providedUnverified => (tr(context, 'unverified'), AppColors.warning),
        BadgeState.missing => (tr(context, 'badgeMissing'), AppColors.faint),
      };

  @override
  Widget build(BuildContext context) {
    final items = verificationBadges(user, isDriver: isDriver);
    final info = reviewInfo(user);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final b in items)
          Padding(
            key: ValueKey('badge_${b.labelKey}'),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(context, b.labelKey), style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  if ((b.value ?? '').isNotEmpty)
                    Text(reveal ? (b.raw ?? '') : b.value!, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.title)),
                ]),
              ),
              StatusChip(label: _look(context, b.state).$1, color: _look(context, b.state).$2),
            ]),
          ),
        if (info != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              info.at == null ? tr(context, 'badgeReviewedManual') : trf(context, 'badgeReviewedOn', {'date': formatDate(info.at)}),
              key: const ValueKey('reviewInfo'),
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
      ],
    );
  }
}
