import 'backend.dart';

/// `config/support`, edited by an admin in the config editor:
/// `{"phone": "+911800...", "hours": "Mon-Sat 9am-6pm"}`. Without it the app
/// shows no call button. LATER(paid): a provider-managed support line.
class SupportConfig {
  final String phone;
  final String hours;

  const SupportConfig({this.phone = '', this.hours = ''});

  bool get hasPhone => phone.trim().isNotEmpty;

  /// Digits and a leading plus only: 7 to 15 digits.
  static bool validPhone(String s) => RegExp(r'^\+?[0-9]{7,15}$').hasMatch(s.replaceAll(RegExp(r'[\s-]'), ''));

  factory SupportConfig.fromMap(Map<String, dynamic>? m) {
    final phone = (m?['phone'] as String?)?.trim() ?? '';
    return SupportConfig(
      phone: validPhone(phone) ? phone : '',
      hours: (m?['hours'] as String?)?.trim() ?? '',
    );
  }

  static Future<SupportConfig> load() async {
    try {
      return SupportConfig.fromMap((await Backend.db.collection('config').doc('support').get()).data());
    } catch (_) {
      return const SupportConfig();
    }
  }
}
