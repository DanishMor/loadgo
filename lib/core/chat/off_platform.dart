/// Spots messages that move contact or payment off LoadGo. Thin wrapper over
/// [ContactFilter] (Task 68), kept for the callers that only need a reason.
library;

import '../comm/contact_filter.dart';

/// Why a message looks off-platform, or null when it looks fine.
enum OffPlatformReason { phone, upi, phrase }

OffPlatformReason? offPlatformReason(String text, {Iterable<String> recent = const []}) => switch (ContactFilter.check(text, recent: recent)) {
      ContactKind.phone => OffPlatformReason.phone,
      ContactKind.upi => OffPlatformReason.upi,
      ContactKind.app || ContactKind.payment => OffPlatformReason.phrase,
      null => null,
    };

bool looksOffPlatform(String text) => offPlatformReason(text) != null;
