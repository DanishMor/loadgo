import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/errors/friendly_error_widget.dart';
import 'package:transport_app/core/l10n/l10n.dart';

/// MASTER-5 Task 18: a widget that throws while building shows a calm sentence.
void main() {
  for (final lang in [AppLanguage.english, AppLanguage.hindi, AppLanguage.urdu, AppLanguage.tamil]) {
    testWidgets('friendly error widget in ${lang.name}', (tester) async {
      languageNotifier.value = lang;
      addTearDown(() => languageNotifier.value = AppLanguage.english);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: friendlyErrorWidget(FlutterErrorDetails(exception: StateError('x'))))));
      expect(find.text(T.get('errorGeneric', lang)), findsOneWidget);
      expect(find.textContaining('StateError'), findsNothing);
    });
  }
}
