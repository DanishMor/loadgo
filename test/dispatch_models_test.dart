import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/dispatch/dispatch_models.dart';
import 'package:transport_app/core/features/features.dart';

/// U10: the Part 4 data model, with safe defaults for old documents.
void main() {
  test('LoadMode: unknown, missing or damaged values are instant (old loads)', () {
    expect(LoadMode.fromValue(null), LoadMode.instant);
    expect(LoadMode.fromValue('auction'), LoadMode.instant);
    expect(LoadMode.fromValue(7), LoadMode.instant);
    expect(LoadMode.fromValue('bid'), LoadMode.bid);
    expect(LoadMode.fromValue('scheduled'), LoadMode.scheduled);
  });

  test('BidNote codes are the ones the rules accept', () {
    final rules = File('firestore.rules').readAsStringSync();
    for (final c in BidNote.codes) {
      expect(rules.contains("'$c'"), isTrue, reason: c);
    }
    expect(BidNote.fromValue('call_me'), isNull);
    expect(BidNote.fromValue('on_the_way'), BidNote.onTheWay);
  });

  group('AutoAccept', () {
    test('a valid map reads; a damaged one is null so it never accepts a bid', () {
      expect(AutoAccept.fromMap({'maxPaise': 2500000, 'minRating': 4, 'verifiedOnly': true})!.maxPaise, 2500000);
      for (final bad in [null, 'x', {}, {'maxPaise': 0}, {'maxPaise': 1.5}, {'maxPaise': -5}, {'maxPaise': 100000001}, {'maxPaise': 10, 'minRating': 6}, {'maxPaise': 10, 'minRating': -1}]) {
        expect(AutoAccept.fromMap(bad), isNull, reason: '$bad');
      }
    });

    test('accepts: price at most the limit, rating at least the minimum, verified when asked', () {
      const a = AutoAccept(maxPaise: 100000, minRating: 4, verifiedOnly: true);
      expect(a.accepts(const BidFacts(pricePaise: 100000, rating: 4.0, verified: true)), isTrue);
      expect(a.accepts(const BidFacts(pricePaise: 100001, rating: 5, verified: true)), isFalse);
      expect(a.accepts(const BidFacts(pricePaise: 90000, rating: 3.9, verified: true)), isFalse);
      expect(a.accepts(const BidFacts(pricePaise: 90000, rating: 5, verified: false)), isFalse);
      expect(a.accepts(const BidFacts(pricePaise: 90000, verified: true)), isFalse, reason: 'no rating yet fails a minimum');
      expect(a.accepts(const BidFacts(pricePaise: 0, rating: 5, verified: true)), isFalse);
      const loose = AutoAccept(maxPaise: 100000);
      expect(loose.accepts(const BidFacts(pricePaise: 5)), isTrue);
    });

    test('toMap round trips and matches the shape the rules allow', () {
      const a = AutoAccept(maxPaise: 12345, minRating: 3.5, verifiedOnly: true);
      final b = AutoAccept.fromMap(jsonDecode(jsonEncode(a.toMap())))!;
      expect((b.maxPaise, b.minRating, b.verifiedOnly), (12345, 3.5, true));
      expect(a.toMap().keys.toSet(), {'maxPaise', 'minRating', 'verifiedOnly'});
    });
  });

  group('DispatchConfig', () {
    test('defaults are 3/7/15 km, 0/30/60 s, 30 s to accept, 10 minute window', () {
      const d = DispatchConfig.defaults;
      expect(d.ringsKm, [3, 7, 15]);
      expect(d.ringDelaySeconds, [0, 30, 60]);
      expect((d.acceptSeconds, d.bidWindowMinutes), (30, 10));
      expect(DispatchConfig.fromMap(null).ringsKm, [3, 7, 15]);
    });

    test('a good document is read', () {
      final c = DispatchConfig.fromMap({'ringsKm': [2, 5, 10, 20], 'ringDelaySeconds': [0, 20, 40, 90], 'acceptSeconds': 45, 'bidWindowMinutes': 15});
      expect(c.ringsKm, [2, 5, 10, 20]);
      expect(c.ringDelaySeconds, [0, 20, 40, 90]);
      expect((c.acceptSeconds, c.bidWindowMinutes), (45, 15));
    });

    test('damaged values fall back to the defaults, never to something absurd', () {
      final bad = <Map<String, dynamic>>[
        {'ringsKm': [7, 3, 15]},
        {'ringsKm': [3]},
        {'ringsKm': ['a', 'b']},
        {'ringsKm': [0, 5]},
        {'ringsKm': [3, 7, 15], 'ringDelaySeconds': [0, 30]},
        {'ringDelaySeconds': [10, 30, 60]},
        {'ringDelaySeconds': [0, 30, 5000]},
        {'acceptSeconds': 1},
        {'acceptSeconds': 9999},
        {'acceptSeconds': 1.5},
        {'bidWindowMinutes': 0},
        {'bidWindowMinutes': 61},
      ];
      for (final m in bad) {
        final c = DispatchConfig.fromMap(m);
        expect(c.ringsKm, [3, 7, 15], reason: '$m');
        expect(c.ringDelaySeconds, [0, 30, 60], reason: '$m');
        expect(c.acceptSeconds, 30, reason: '$m');
        expect(c.bidWindowMinutes, 10, reason: '$m');
      }
    });

    test('a city override changes only what it names, and the city name is not case sensitive', () {
      final c = DispatchConfig.fromMap({
        'acceptSeconds': 40,
        'cities': {
          'Delhi': {'ringsKm': [2, 5, 9], 'acceptSeconds': 20},
          'pune': {'ringsKm': [9, 3]}, // damaged: ignored
        },
      });
      final d = c.forCity('  DELHI ');
      expect(d.ringsKm, [2, 5, 9]);
      expect(d.ringDelaySeconds, [0, 30, 60]);
      expect(d.acceptSeconds, 20);
      expect(d.bidWindowMinutes, 10);
      expect(c.forCity('Pune').ringsKm, [3, 7, 15]);
      expect(c.forCity('Nagpur').acceptSeconds, 40);
      expect(c.forCity(null).acceptSeconds, 40);
    });
  });

  test('uiV2 is ON and dispatchV2 is OFF by default, in pilot mode and in normal mode', () {
    for (final pilot in [true, false]) {
      final f = Features(pilotMode: pilot);
      expect(f.isOn(FeatureKey.uiV2), isTrue, reason: 'pilot=$pilot');
      expect(f.isOn(FeatureKey.dispatchV2), isFalse, reason: 'pilot=$pilot');
    }
  });
}
