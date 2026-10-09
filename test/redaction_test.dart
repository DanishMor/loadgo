import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/services/breadcrumbs.dart';
import 'package:transport_app/core/services/error_log_service.dart';

/// MASTER-6 Task 42: logs never carry personal data.
void main() {
  setUp(Breadcrumbs.clear);

  const samples = {
    'mail asha.k@example.com failed': 'asha.k@example.com',
    'pay ramesh@okbank now': 'ramesh@okbank',
    'see https://loadgo.example/t/abc123 please': 'https://',
    'call +91 98765 43210 now': '98765',
    'phone 9876543210': '9876543210',
    'aadhaar 1234 5678 9012': '5678',
    'PAN ABCDE1234F found': 'ABCDE1234F',
    'GST 27ABCDE1234F1Z5 bad': '27ABCDE1234F1Z5',
    'truck MH12AB1234 stopped': 'MH12AB1234',
    'truck MH 12 AB 1234 stopped': 'AB 1234',
    'otp 482913 wrong': '482913',
    'at 19.07600, 72.87770 now': '19.07600',
    'user abcdefghijklmnopqrstuvwxyz12 missing': 'abcdefghijklmnopqrstuvwxyz12',
  };

  test('each kind of personal data is removed', () {
    samples.forEach((text, secret) {
      final out = Redactor.clean(text);
      expect(out.contains(secret), isFalse, reason: '"$text" -> "$out"');
    });
  });

  test('ordinary words and short numbers stay readable', () {
    expect(Redactor.clean('Bad state: no element at index 3'), 'Bad state: no element at index 3');
    expect(Redactor.clean('RangeError (index): 5'), 'RangeError (index): 5');
  });

  test('the error log uses the same cleaning and keeps one line within the limit', () {
    expect(ErrorLogService.sanitize('a\n\n b   c ${'x' * 400}', maxLength: 20).length, lessThanOrEqualTo(20));
    expect(ErrorLogService.sanitize('fail for 9876543210 at asha@x.com'), isNot(contains('9876543210')));
  });

  test('breadcrumbs keep the newest 25 short, cleaned labels', () {
    for (var i = 0; i < 40; i++) {
      Breadcrumbs.add('step $i');
    }
    expect(Breadcrumbs.items.length, Breadcrumbs.capacity);
    expect(Breadcrumbs.items.first, 'step 15');
    expect(Breadcrumbs.items.last, 'step 39');
    Breadcrumbs.clear();
    Breadcrumbs.add('opened chat with 9876543210 and asha@x.com ${'z' * 100}');
    final c = Breadcrumbs.items.single;
    expect(c.length, lessThanOrEqualTo(40));
    expect(c.contains('9876543210') || c.contains('@'), isFalse);
  });

  test('the trail is one line, newest last, within the limit', () {
    for (var i = 0; i < 25; i++) {
      Breadcrumbs.add('open Screen$i');
    }
    final t = Breadcrumbs.trail(maxLength: 100);
    expect(t.length, lessThanOrEqualTo(100));
    expect(t.endsWith('Screen24'), isTrue);
    expect(t.contains('\n'), isFalse);
  });

  testWidgets('the observer records screens by name only', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: nav, navigatorObservers: [BreadcrumbObserver()], home: const Text('home')));
    Breadcrumbs.clear();
    nav.currentState!.push<void>(MaterialPageRoute(settings: const RouteSettings(name: 'trip'), builder: (_) => const Text('x')));
    await tester.pumpAndSettle();
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(Breadcrumbs.items, ['open trip', 'back MaterialPageRoute']);
  });
}
