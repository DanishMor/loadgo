import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Part 5 (H25): a live listener on a collection query with no limit reads every matching document at the start and
/// again for each change, so one busy account costs more and more. This counts the listeners with no limit near them
/// and may only go down. When a listener gets a limit (or is a single document), lower [baseline].
void main() {
  // Measured in Part 5. A line is counted when `.snapshots()` is on it and none of the 4 lines before it has a limit,
  // a paging helper or a single-document reference.
  const baseline = 57;

  List<String> unbounded() {
    final safe = RegExp(r'limit\(|newestPage|watchLimit|\.doc\(|_doc\(|_user\(|_grant\(|_req\(|_readMark\(|_block\(|doc\(\w+\)\.snapshots');
    final out = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('.snapshots()')) continue;
        final from = i - 4 < 0 ? 0 : i - 4;
        if (safe.hasMatch(lines.sublist(from, i + 1).join(' '))) continue;
        out.add('${f.path.replaceAll(r'\', '/')}:${i + 1}');
      }
    }
    return out;
  }

  test('listeners without a limit never grow in number', () {
    final now = unbounded();
    expect(now.length, lessThanOrEqualTo(baseline), reason: 'a new unbounded listener was added:\n${now.join('\n')}');
  });

  test('the listeners that grow with an account (bookings and notifications of one person) have a limit', () {
    final booking = File('lib/core/services/booking_service.dart').readAsStringSync();
    expect(booking.contains('newestPage(_col.where(field, isEqualTo: uid), watchAllCap)'), isTrue, reason: 'BookingService.watchFor... must be limited');
    final notes = File('lib/core/services/notification_service.dart').readAsStringSync();
    expect(notes.contains("newestPage(_col.where('userId', isEqualTo: uid), watchCap)"), isTrue, reason: 'notifications must be limited');
  });
}
