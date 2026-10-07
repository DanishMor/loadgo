import 'package:flutter/foundation.dart';

import '../demo/demo_seed.dart';
import 'backend.dart';

class DemoBlockedException implements Exception {
  const DemoBlockedException();
}

/// Admin > Demo data: writes the [DemoSeed] documents and removes every
/// document flagged `demo: true`. Rules: super admin only, ids start with demo_.
class DemoService {
  DemoService._();

  static const batchSize = 400;

  /// Overridable for tests.
  static bool release = kReleaseMode;

  static Future<bool> allowDemoConfig() async {
    try {
      final snap = await Backend.db.collection('config').doc('app').get();
      return snap.data()?['allowDemo'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> allowed() async => DemoGuard.allowed(release: release, allowDemo: !release || await allowDemoConfig());

  /// Creates the demo set; returns the number of documents. Throws
  /// [DemoBlockedException] in a release build unless `config/app.allowDemo`.
  static Future<int> create({DateTime? now}) async {
    if (!await allowed()) throw const DemoBlockedException();
    final docs = DemoSeed.build(now: now);
    for (var i = 0; i < docs.length; i += batchSize) {
      final batch = Backend.db.batch();
      for (final d in docs.skip(i).take(batchSize)) {
        batch.set(Backend.db.collection(d.collection).doc(d.id), d.data);
      }
      await batch.commit();
    }
    return docs.length;
  }

  /// How many demo documents exist.
  static Future<int> count() async {
    var n = 0;
    for (final c in DemoSeed.collections) {
      final snap = await Backend.db.collection(c).where('demo', isEqualTo: true).get();
      n += snap.docs.where((d) => d.id.startsWith(DemoSeed.idPrefix)).length;
    }
    return n;
  }

  /// Deletes every demo document, [batchSize] at a time; returns how many.
  /// Allowed in release builds too (cleaning up must always work).
  static Future<int> removeAll() async {
    var n = 0;
    for (final c in DemoSeed.collections) {
      while (true) {
        final snap = await Backend.db.collection(c).where('demo', isEqualTo: true).limit(batchSize).get();
        final mine = snap.docs.where((d) => d.id.startsWith(DemoSeed.idPrefix)).toList();
        if (mine.isEmpty) break;
        final batch = Backend.db.batch();
        for (final d in mine) {
          batch.delete(d.reference);
        }
        await batch.commit();
        n += mine.length;
        if (mine.length < snap.docs.length || snap.docs.length < batchSize) break;
      }
    }
    return n;
  }
}
