import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/user_service.dart';

void main() {
  test('a new account or the same role is allowed', () {
    expect(() => UserService.ensureRoleAllowed(null, 'driver'), returnsNormally);
    expect(() => UserService.ensureRoleAllowed('customer', 'customer'), returnsNormally);
  });

  test('logging in through the other role throws with both roles', () {
    expect(
      () => UserService.ensureRoleAllowed('driver', 'customer'),
      throwsA(isA<RoleMismatchException>()
          .having((e) => e.existing, 'existing', 'driver')
          .having((e) => e.requested, 'requested', 'customer')),
    );
  });

  test('the mismatch message names the role in every language', () {
    for (final lang in AppLanguage.values) {
      final msg = T.get('roleMismatch', lang).replaceAll('{role}', T.get('roleNameDriver', lang));
      expect(msg.contains('{role}'), isFalse);
      expect(msg.contains(T.get('roleNameDriver', lang)), isTrue, reason: lang.name);
    }
  });
}
