/// Spots messages that move contact or payment off LoadGo: Indian mobile
/// numbers, UPI ids and "pay outside" style phrases (English + Hinglish).
library;

final _phone = RegExp(r'(?:\+?91[\s-]?)?(?<!\d)[6-9](?:[\s-]?\d){9}(?!\d)');
final _upi = RegExp(r'\b[\w.\-]{2,}@(?:ok\w+|ybl|ibl|axl|upi|paytm|apl|ptyes|ptsbi|ptaxis|pthdfc|axisbank|icici|sbi|hdfcbank|kotak|yesbank|freecharge|jio|airtel|waicici|wahdfcbank|waaxis|wasbi|fbl|barodampay)\b',
    caseSensitive: false);
final _phrases = RegExp(
  r'pay\s*(?:me\s*)?outside|outside\s*(?:the\s*)?app|direct\s*payment|pay\s*direct(?:ly)?|bahar\s*(?:se\s*)?payment|app\s*ke\s*bahar|cash\s*me\s*(?:de|do)\s*dena|whats\s*app\s*(?:pe|par|me)?\s*(?:baat|call)|call\s*me\s*on|google\s*pay\s*kar|phone\s*pe\s*kar|gpay\s*kar',
  caseSensitive: false,
);

/// Why a message looks off-platform, or null when it looks fine.
enum OffPlatformReason { phone, upi, phrase }

OffPlatformReason? offPlatformReason(String text) {
  if (_upi.hasMatch(text)) return OffPlatformReason.upi;
  if (_phone.hasMatch(text)) return OffPlatformReason.phone;
  if (_phrases.hasMatch(text)) return OffPlatformReason.phrase;
  return null;
}

bool looksOffPlatform(String text) => offPlatformReason(text) != null;
