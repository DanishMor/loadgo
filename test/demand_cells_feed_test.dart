import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/adapters/demand_cells_feed.dart';
import 'package:transport_app/core/adapters/maps_adapter.dart';
import 'package:transport_app/core/location/geohash.dart';

/// E36: the app reads demand_cells around the driver (flag demandFeed).
void main() {
  final now = DateTime(2027, 5, 20, 12);
  const mumbai = GeoPoint2(19.076, 72.8777);

  test('fresh busy cells near the driver, busiest first, named after the nearest city; old, empty and far cells left out', () async {
    final db = FakeFirebaseFirestore();
    final here = geohashEncode(mumbai.lat, mumbai.lng, precision: 4);
    final around = geohashCells(mumbai.lat, mumbai.lng, 4).where((c) => c != here).toList();
    await db.doc('demand_cells/$here').set({'openLoads': 3, 'updatedAt': Timestamp.fromDate(now.subtract(const Duration(minutes: 5)))});
    await db.doc('demand_cells/${around.first}').set({'openLoads': 9, 'updatedAt': Timestamp.fromDate(now.subtract(const Duration(minutes: 2)))});
    await db.doc('demand_cells/${around[1]}').set({'openLoads': 5, 'updatedAt': Timestamp.fromDate(now.subtract(const Duration(hours: 2)))});
    await db.doc('demand_cells/${around[2]}').set({'openLoads': 0, 'updatedAt': Timestamp.fromDate(now)});
    await db.doc('demand_cells/tdr1').set({'openLoads': 50, 'updatedAt': Timestamp.fromDate(now)});
    final cells = await FirestoreDemandFeed(db: db, now: () => now).near(mumbai);
    expect(cells.map((c) => c.openLoads), [9, 3]);
    expect(cells.last.area, 'Mumbai');
  });

  test('bad points and errors give nothing', () async {
    expect(await FirestoreDemandFeed(db: FakeFirebaseFirestore(), now: () => now).near(const GeoPoint2(120, 0)), isEmpty);
    expect(await FirestoreDemandFeed(db: FakeFirebaseFirestore(), now: () => now).near(mumbai, max: 0), isEmpty);
  });
}
