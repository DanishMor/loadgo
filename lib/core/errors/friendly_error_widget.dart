import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// What a screen shows when one of its widgets throws while building. In a
/// release build this replaces the grey/red framework error box with a calm
/// sentence in the person's language (MASTER-5 Task 18); the exception itself
/// still goes to CrashService through FlutterError.onError.
Widget friendlyErrorWidget(FlutterErrorDetails details) {
  final rtl = languageNotifier.value == AppLanguage.urdu || languageNotifier.value == AppLanguage.kashmiri;
  return Directionality(
    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 40, color: Color(0xFF757575)),
            const SizedBox(height: 12),
            Text(
              T.get('errorGeneric', languageNotifier.value),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: Color(0xFF424242), decoration: TextDecoration.none, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    ),
  );
}
