import 'package:share_plus/share_plus.dart';

/// Opens the system share sheet with CSV [text]. Returns false when sharing
/// is not possible on this device.
Future<bool> shareCsv(String text, String subject) async {
  try {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
    return true;
  } catch (_) {
    return false;
  }
}
