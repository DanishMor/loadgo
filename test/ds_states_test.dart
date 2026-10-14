import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/connectivity_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/theme/design_tokens.dart';
import 'package:transport_app/core/widgets/common.dart';
import 'package:transport_app/core/widgets/ds/illustrations.dart';
import 'package:transport_app/core/widgets/ds/skeleton.dart';
import 'package:transport_app/core/widgets/live_stream.dart';

/// L10: skeletons, drawn illustrations, empty and error states.
Widget host(Widget child, {Brightness b = Brightness.light, double scale = 1.0, AppLanguage lang = AppLanguage.english, bool disableAnimations = false, bool lowEnd = false}) {
  final language = ValueNotifier(lang);
  final dir = (lang == AppLanguage.urdu || lang == AppLanguage.kashmiri) ? TextDirection.rtl : TextDirection.ltr;
  return LanguageScope(
    notifier: language,
    child: MaterialApp(
      theme: AppTheme.build(b, lowEnd: lowEnd),
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: disableAnimations),
        child: Directionality(textDirection: dir, child: w!),
      ),
      home: Scaffold(body: child),
    ),
  );
}

/// Paints [kind] on a 160 x 120 canvas and returns the RGBA bytes.
Future<List<int>> pixels(IllustrationKind kind, DsColors c) async {
  final rec = ui.PictureRecorder();
  IllustrationPainter(kind, c).paint(Canvas(rec), const Size(160, 120));
  final img = await rec.endRecording().toImage(160, 120);
  final bytes = await img.toByteData();
  return bytes!.buffer.asUint8List();
}

void main() {
  group('illustrations', () {
    for (final kind in IllustrationKind.values) {
      test('${kind.name} draws something, differs from the others, and follows light / dark', () async {
        final light = await pixels(kind, DsColors.light);
        final dark = await pixels(kind, DsColors.dark);
        final drawn = [for (var i = 3; i < light.length; i += 4) light[i]].where((a) => a > 0).length;
        expect(drawn, greaterThan(160 * 120 ~/ 8), reason: 'a visible picture, not an empty canvas');
        expect(light, isNot(dark));
        for (final other in IllustrationKind.values.where((k) => k != kind)) {
          expect(await pixels(other, DsColors.light), isNot(light), reason: '${kind.name} vs ${other.name}');
        }
      });
    }

    test('the painter repaints only when the kind or the colours change', () {
      const a = IllustrationPainter(IllustrationKind.error, DsColors.light);
      expect(a.shouldRepaint(const IllustrationPainter(IllustrationKind.error, DsColors.light)), isFalse);
      expect(a.shouldRepaint(const IllustrationPainter(IllustrationKind.error, DsColors.dark)), isTrue);
      expect(a.shouldRepaint(const IllustrationPainter(IllustrationKind.success, DsColors.light)), isTrue);
    });

    testWidgets('the view has 4:3 size and no semantics (decoration only)', (t) async {
      final h = t.ensureSemantics();
      await t.pumpWidget(host(const Center(child: IllustrationView(IllustrationKind.noTrips, width: 200))));
      expect(t.getSize(find.byType(IllustrationView)), const Size(200, 150));
      expect(find.descendant(of: find.byType(IllustrationView), matching: find.byType(Semantics)).evaluate().where((e) => (e.widget as Semantics).properties.label != null), isEmpty);
      h.dispose();
    });
  });

  group('Skeleton', () {
    testWidgets('a list of grey cards pulses and is announced as Loading', (t) async {
      final h = t.ensureSemantics();
      await t.pumpWidget(host(const SkeletonList(count: 3)));
      expect(find.byType(SkeletonCard), findsNWidgets(3));
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
      final fade = find.descendant(of: find.byType(Skeleton), matching: find.byType(FadeTransition));
      final o1 = t.widget<FadeTransition>(fade.first).opacity.value;
      await t.pump(const Duration(milliseconds: 450));
      final o2 = t.widget<FadeTransition>(fade.first).opacity.value;
      expect(o1, isNot(o2), reason: 'it breathes');
      expect(o1, inInclusiveRange(0.45, 1.0));
      h.dispose();
    });

    testWidgets('it stands still with "remove animations" and in Low-end mode', (t) async {
      await t.pumpWidget(host(const SkeletonList(), disableAnimations: true));
      final fade = find.descendant(of: find.byType(Skeleton), matching: find.byType(FadeTransition));
      final a = t.widget<FadeTransition>(fade.first).opacity.value;
      await t.pump(const Duration(milliseconds: 500));
      expect(t.widget<FadeTransition>(fade.first).opacity.value, a);
      expect(a, 1.0);
      addTearDown(() => DsMotion.lowEnd = false);
      await t.pumpWidget(host(const SkeletonList(), lowEnd: true));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(t.widget<FadeTransition>(find.descendant(of: find.byType(Skeleton), matching: find.byType(FadeTransition)).first).opacity.value, 1.0);
    });

    testWidgets('a custom item and count, and boxes with a size', (t) async {
      await t.pumpWidget(host(SkeletonList(count: 2, itemBuilder: (_) => const SkeletonBox(height: 40))));
      expect(find.byType(SkeletonBox), findsNWidgets(2));
      expect(find.byType(SkeletonCard), findsNothing);
      await t.pumpWidget(host(const Skeleton(child: SkeletonBox(width: 120, height: 24, radius: 12))));
      expect(t.getSize(find.byType(SkeletonBox)), const Size(120, 24));
    });

    for (final b in Brightness.values) {
      testWidgets('fits 360x640 at 2.0x text, ${b.name}', (t) async {
        t.view.physicalSize = const Size(360, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(host(const SkeletonList(count: 6), b: b, scale: 2.0));
        expect(t.takeException(), isNull);
      });
    }
  });

  group('EmptyState', () {
    testWidgets('icon tile by default, picture when asked, the title is a header', (t) async {
      final h = t.ensureSemantics();
      await t.pumpWidget(host(const EmptyState(icon: Icons.inbox_outlined, title: 'No loads yet', subtitle: 'Post your first load')));
      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
      expect(find.byType(IllustrationView), findsNothing);
      expect(find.text('Post your first load'), findsOneWidget);
      await t.pumpWidget(host(const EmptyState(icon: Icons.inbox_outlined, illustration: IllustrationKind.emptyBox, title: 'No loads yet')));
      expect(find.byType(IllustrationView), findsOneWidget);
      expect(find.byIcon(Icons.inbox_outlined), findsNothing);
      expect(t.getSemantics(find.text('No loads yet')).flagsCollection.isHeader, isTrue);
      h.dispose();
    });

    testWidgets('the action shows and works', (t) async {
      var taps = 0;
      await t.pumpWidget(host(EmptyState(icon: Icons.add, title: 'Empty', action: TextButton(onPressed: () => taps++, child: const Text('Add')))));
      await t.tap(find.text('Add'));
      expect(taps, 1);
    });

    for (final lang in [AppLanguage.english, AppLanguage.tamil, AppLanguage.urdu]) {
      for (final b in Brightness.values) {
        testWidgets('picture + long text + action scroll instead of overflow at 2.0x on 360x640: ${lang.name} ${b.name}', (t) async {
          t.view.physicalSize = const Size(360, 640);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          await t.pumpWidget(host(
            EmptyState(
              icon: Icons.local_shipping_outlined,
              illustration: IllustrationKind.noTrips,
              title: 'இன்னும் எந்தப் பயணமும் இல்லை, முதல் சரக்கைப் பதிவு செய்யுங்கள்',
              subtitle: 'ڈرائیور آپ کے لوڈ کی قیمت بھیجیں گے اور آپ ایک چن سکتے ہیں',
              action: ElevatedButton(onPressed: () {}, child: const Text('Post a load')),
            ),
            b: b,
            scale: 2.0,
            lang: lang,
          ));
          expect(t.takeException(), isNull);
        });
      }
    }
  });

  group('ErrorRetry, ErrorState, LiveStream', () {
    setUp(() => ConnectivityService.online.value = true);

    testWidgets('offline gets the no-network picture, other errors the warning, both with Retry', (t) async {
      var retries = 0;
      await t.pumpWidget(host(ErrorRetry(messageKey: 'errorOffline', onRetry: () => retries++)));
      expect(t.widget<IllustrationView>(find.byType(IllustrationView)).kind, IllustrationKind.noNetwork);
      await t.tap(find.text('Retry'));
      expect(retries, 1);
      await t.pumpWidget(host(ErrorRetry(messageKey: 'errorSlow', onRetry: () {})));
      expect(t.widget<IllustrationView>(find.byType(IllustrationView)).kind, IllustrationKind.error);
    });

    testWidgets('the compact form stays a one-line card without a picture', (t) async {
      await t.pumpWidget(host(ErrorRetry(messageKey: 'errorSlow', onRetry: () {}, compact: true)));
      expect(find.byType(IllustrationView), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('ErrorState follows the connection', (t) async {
      await t.pumpWidget(host(const ErrorState(error: 'boom')));
      expect(t.widget<IllustrationView>(find.byType(IllustrationView)).kind, IllustrationKind.error);
      ConnectivityService.online.value = false;
      await t.pumpWidget(host(const ErrorState(error: 'boom', onRetry: _noop)));
      expect(t.widget<IllustrationView>(find.byType(IllustrationView)).kind, IllustrationKind.noNetwork);
    });

    testWidgets('LiveStream: a spinner by default, the loadingBuilder when given, data when it arrives', (t) async {
      final ctrl = StreamController<int>();
      addTearDown(ctrl.close);
      await t.pumpWidget(host(LiveStream<int>(stream: () => ctrl.stream, builder: (c, d) => Text('got $d'))));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.pumpWidget(host(LiveStream<int>(stream: () => ctrl.stream, loadingBuilder: (_) => const SkeletonList(), builder: (c, d) => Text('got $d'))));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(SkeletonList), findsOneWidget);
      ctrl.add(7);
      await t.pump();
      expect(find.text('got 7'), findsOneWidget);
      expect(find.byType(SkeletonList), findsNothing);
    });

    testWidgets('OfflineBanner appears only offline, in token colours', (t) async {
      await t.pumpWidget(host(const OfflineBanner()));
      expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);
      ConnectivityService.online.value = false;
      await t.pump();
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
      final m = t.widget<Material>(find.descendant(of: find.byType(OfflineBanner), matching: find.byType(Material)).first);
      expect(m.color, DsColors.light.text);
    });
  });
}

void _noop() {}
