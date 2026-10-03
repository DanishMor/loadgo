import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/share_text.dart';
import 'package:transport_app/features/loads/load_card.dart';

void main() {
  final load = Load(
    id: 'L1', shipperId: 'c1', pickup: 'Delhi', drop: 'Mumbai', cargoType: 'FMCG', weight: 8,
    vehicleType: '20ft', budget: 25000, pickupDate: DateTime(2026, 10, 5), notes: '', status: 'open',
    createdAt: Timestamp.now(),
  );

  test('load share text has route, cargo, budget and id', () {
    final t = loadShareText(load);
    expect(t, contains('Delhi -> Mumbai'));
    expect(t, contains('FMCG, 8 T, 20ft'));
    expect(t, contains('Budget: ₹ 25000'));
    expect(t, contains('ID: L1'));
  });

  testWidgets('share button copies the summary', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: LoadCard(load: load))));
    await tester.tap(find.byTooltip('Share'));
    await tester.pump();
    expect(copied, loadShareText(load));
    expect(find.text('Details copied to clipboard'), findsOneWidget);
  });
}
