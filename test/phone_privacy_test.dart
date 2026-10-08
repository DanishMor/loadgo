import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Task 4 (MASTER-5): a phone number is written to a document only in the
/// places that need it. A new place must be added here on purpose, after
/// asking "who can read this document?".
void main() {
  final key = RegExp(r"'(phone|driverPhone|consignorPhone|consigneePhone|receiverPhone|customerPhone|memberPhone)'\s*:");
  const allowed = {
    'lib/core/demo/demo_seed.dart': 'demo data only, fake numbers',
    'lib/admin/admin_config_screen.dart': 'an empty phone in the support-line template (admin-only config)',
    'lib/core/bilty/lr_model.dart': 'LR private/details, never readable by the driver',
    'lib/core/services/admin_console_service.dart': 'writes an empty driverPhone on reassign',
    'lib/core/services/safety_service.dart': 'own emergency contacts on the own profile',
    'lib/core/services/user_service.dart': 'own profile (users/{uid} is owner + admin only)',
    'lib/core/services/booking_service.dart': 'writes an empty driverPhone',
    'lib/core/services/fleet_service.dart': 'invite by phone; member doc read by owner and that driver only',
    'lib/core/services/business_service.dart': 'invite by phone; read by owner and that member only',
    'lib/core/services/phone_change_service.dart': 'own profile',
    'lib/core/models/booking.dart': 'delivery receiver, seen by the two booking parties',
    'lib/core/settings/account_deletion_screen.dart': 'a masked label, not a write',
  };

  test('phone keys are written only in the known files', () {
    final found = <String>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.contains('l10n')) continue;
      if (key.hasMatch(f.readAsStringSync())) found.add(f.path);
    }
    expect(found.difference(allowed.keys.toSet()), isEmpty, reason: 'new phone writers: review who can read the document');
  });

  test('a new booking and a reassign store an empty driver phone', () {
    for (final p in ['lib/core/services/booking_service.dart', 'lib/core/services/admin_console_service.dart']) {
      expect(File(p).readAsStringSync(), contains("'driverPhone': ''"));
    }
  });
}
