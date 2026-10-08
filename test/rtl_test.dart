import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';

/// MASTER-5 Task 24: only Urdu and Kashmiri are right to left.
void main() {
  test('direction by language', () {
    for (final l in AppLanguage.values) {
      final rtl = l == AppLanguage.urdu || l == AppLanguage.kashmiri;
      expect(l.isRtl, rtl, reason: l.name);
      expect(l.textDirection, rtl ? TextDirection.rtl : TextDirection.ltr);
    }
  });

  testWidgets('a row flips for Urdu: the first child sits on the right', (tester) async {
    Future<double> firstX(AppLanguage l) async {
      await tester.pumpWidget(Directionality(
        textDirection: l.textDirection,
        child: const Row(children: [SizedBox(key: ValueKey('first'), width: 40, height: 10), Spacer()]),
      ));
      return tester.getTopLeft(find.byKey(const ValueKey('first'))).dx;
    }

    expect(await firstX(AppLanguage.english), 0);
    expect(await firstX(AppLanguage.urdu), greaterThan(700));
  });
}
