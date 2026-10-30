import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/booking/part_load.dart';

/// E28b: part-load share, price and fit (logic only; the flag stays planned until its rules are published).
void main() {
  test('share is the larger of weight and volume, kept within 0..1', () {
    expect(spaceShare(weightTons: 2, truckTons: 8), 0.25);
    expect(spaceShare(weightTons: 1, truckTons: 8, volumeCft: 600, truckCft: 1200), 0.5);
    expect(spaceShare(weightTons: 12, truckTons: 8), 1);
    expect(spaceShare(weightTons: 1, truckTons: 0), 1);
  });

  test('advice: too small, fine, or book the whole truck', () {
    expect(partLoadAdvice(0.05), PartLoadAdvice.tooSmall);
    expect(partLoadAdvice(0.4), PartLoadAdvice.ok);
    expect(partLoadAdvice(0.8), PartLoadAdvice.bookFullTruck);
  });

  test('price: share plus handling, at least the minimum share, rounded to ten rupees, never above the full truck', () {
    expect(partLoadPricePaise(2000000, 0.25), 575000);
    expect(partLoadPricePaise(2000000, 0.01), partLoadPricePaise(2000000, 0.1));
    expect(partLoadPricePaise(2000000, 0.95), 2000000);
    expect(partLoadPricePaise(0, 0.5), 0);
    expect(partLoadPricePaise(1234567, 0.33) % 1000, 0);
  });

  test('shares on one truck must fit; config falls back on bad documents', () {
    expect(fitsTruck([0.4, 0.3], 0.3), isTrue);
    expect(fitsTruck([0.4, 0.3], 0.31), isFalse);
    expect(PartLoadConfig.fromMap({'minShare': 0.2, 'maxShare': 0.6, 'handling': 0.1}).maxShare, 0.6);
    for (final bad in <Map<String, dynamic>?>[null, {'minShare': 0.8, 'maxShare': 0.6, 'handling': 0.1}, {'minShare': 0.1, 'maxShare': 0.6, 'handling': 2}, {'minShare': 'x'}]) {
      expect(PartLoadConfig.fromMap(bad).minShare, PartLoadConfig.standard.minShare, reason: '$bad');
    }
  });
}
