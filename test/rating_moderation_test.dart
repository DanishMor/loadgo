import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_rating_flags_screen.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/backend.dart';

import 'test_utils.dart';

/// MASTER-5 Task 33: support can hide an abusive comment; the stars stay.
void main() {
  late FakeFirebaseFirestore db;

  setUp(() async {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'sup1');
    await db.collection('ratings').doc('B1_c1').set({'bookingId': 'B1', 'raterId': 'c1', 'ratedId': 'd1', 'stars': 1, 'comment': 'rude words', 'createdAt': Timestamp.now()});
    await db.collection('rating_flags').doc('B1_c1').set({'bookingId': 'B1', 'raterId': 'c1', 'ratedId': 'd1', 'stars': 1, 'status': 'open'});
  });

  testWidgets('the flag shows the comment; Hide comment blanks it, keeps the stars and writes an audit event', (tester) async {
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: AdminRatingFlagsScreen())));
    await settle(tester);
    expect(find.byKey(const ValueKey('flagComment_B1_c1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('flagHide_B1_c1')));
    await settle(tester);
    expect(find.byKey(const ValueKey('flagComment_B1_c1')), findsNothing);
    expect(find.text('Comment hidden by support'), findsOneWidget);
    final r = (await db.collection('ratings').doc('B1_c1').get()).data()!;
    expect(r['comment'], '');
    expect(r['moderated'], true);
    expect(r['stars'], 1);
    final audit = (await db.collection('audit_events').get()).docs.single.data();
    expect(audit['type'], 'user_action');
    expect((audit['data'] as Map)['action'], 'rating_comment_hidden');
  });
}
