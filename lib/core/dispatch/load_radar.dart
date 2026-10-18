import 'dart:async';

import '../matching/load_ranker.dart';
import '../matching/nearest.dart';
import '../models/load.dart';
import '../models/vehicle.dart';
import '../pricing/cities.dart';
import 'dispatch_config_service.dart';
import 'dispatch_models.dart';
import 'dispatch_window.dart';

/// One load waiting to be shown to the driver as a card (U16).
class RadarItem {
  final Load load;

  /// The distance to the pickup in km, or null when it cannot be told.
  final int? km;

  /// When the card opened for this driver (the ring unlocked, or the customer asked again) and when it closes.
  final DateTime opensAt;
  final DateTime endsAt;

  const RadarItem({required this.load, required this.km, required this.opensAt, required this.endsAt});

  /// A new price or a wider search is a new question to the driver, so it has a new key and can come back after a skip.
  String get key => RadarEngine.keyOf(load);

  int secondsLeft(DateTime now) {
    final ms = endsAt.difference(now).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }
}

/// What the radar shows right now: the card on screen and the ones waiting behind it.
class RadarState {
  final RadarItem? current;
  final List<RadarItem> queue;
  const RadarState({this.current, this.queue = const []});

  static const empty = RadarState();
  int get waiting => queue.length;
}

/// The one rule for "which loads become a full-screen card for this driver, in which order" (U16). Pure: the same
/// loads, vehicles, place and time always give the same answer, so the screen can be rebuilt at any moment.
///
/// A load is a card when it is open, not the driver's own, not blocked for them, carried by one of their vehicles,
/// unlocked for their ring (when `dispatchV2` is on), still inside its accept window and not skipped. Cards are
/// shown one after another, the earliest-opened first, the nearer one first when two opened together.
class RadarEngine {
  RadarEngine._();

  static String keyOf(Load load) => '${load.id}@${load.budget ?? 0}@${load.ringBoost}';

  static RadarState compute({
    required List<Load> loads,
    required List<Vehicle>? vehicles,
    required LatLng? origin,
    required DateTime now,
    required String? driverId,
    required DispatchConfig config,
    required bool waves,
    Set<String> skipped = const {},
  }) {
    final items = <RadarItem>[];
    final seen = <String>{};
    for (final load in loads) {
      if (!seen.add(load.id)) continue; // one card per load, however many streams delivered it
      if (!load.isOpen || load.shipperId == driverId || load.blocks(driverId)) continue;
      if (load.mode == LoadMode.scheduled) continue; // advance bookings are browsed, they do not ring
      if (vehicles != null && !vehicles.any((v) => LoadRanker.vehicleFits(v, vehicleType: load.vehicleType, weight: load.weight, now: now, allowOnTrip: true))) continue;
      final km = origin == null ? null : kmToPickup(origin, load);
      final cfg = waves ? config.forCity(findCity(load.pickup)?.name) : config;
      final created = load.createdAt?.toDate();
      if (created == null) continue; // not stamped by the server yet
      final invited = driverId != null && load.invitedDriverId == driverId;
      final need = waves ? DispatchWindow(cfg).secondsUntilVisible(km?.toDouble(), boost: load.ringBoost) : 0;
      if (need == null && !invited) continue; // outside every ring
      var opens = created.add(Duration(seconds: invited ? 0 : need ?? 0));
      final touched = load.updatedAt?.toDate();
      if (touched != null && touched.isAfter(opens)) opens = touched; // asked again
      final ends = opens.add(Duration(seconds: cfg.acceptSeconds));
      if (now.isBefore(opens) || !now.isBefore(ends)) continue;
      if (skipped.contains(keyOf(load))) continue;
      items.add(RadarItem(load: load, km: km, opensAt: opens, endsAt: ends));
    }
    items.sort((a, b) {
      final c = a.opensAt.compareTo(b.opensAt);
      if (c != 0) return c;
      final ka = a.km, kb = b.km;
      if (ka != null && kb != null && ka != kb) return ka.compareTo(kb);
      if (ka == null && kb != null) return 1;
      if (ka != null && kb == null) return -1;
      return a.load.id.compareTo(b.load.id);
    });
    if (items.isEmpty) return RadarState.empty;
    return RadarState(current: items.first, queue: items.sublist(1));
  }
}

/// Watches the open loads for the signed-in driver and publishes [RadarState] (U16). The sources are given in, so the
/// service owns no Firestore code and a test drives it with plain streams and a fake clock.
class LoadRadar {
  final Stream<List<Load>> loads;
  final Future<List<Vehicle>> Function() vehicles;
  final LatLng? Function() origin;
  final String? Function() driverId;
  final bool Function() wavesOn;
  final DispatchConfig Function() config;
  final DateTime Function() now;

  /// How often the state is worked out again so a card closes and the next opens on time.
  final Duration tick;

  LoadRadar({
    required this.loads,
    required this.vehicles,
    required this.origin,
    required this.driverId,
    required this.wavesOn,
    DispatchConfig Function()? config,
    DateTime Function()? now,
    this.tick = const Duration(seconds: 1),
  })  : config = config ?? (() => DispatchConfigService.current),
        now = now ?? DateTime.now;

  final _out = StreamController<RadarState>.broadcast();
  StreamSubscription<List<Load>>? _sub;
  Timer? _timer;
  List<Load> _loads = const [];
  List<Vehicle>? _vehicles;
  final Set<String> _skipped = {};
  RadarState _state = RadarState.empty;

  Stream<RadarState> get states => _out.stream;
  RadarState get state => _state;

  void start() {
    if (_sub != null) return;
    _sub = loads.listen((l) {
      _loads = l;
      _recompute();
    }, onError: (_) {});
    vehicles().then((v) {
      _vehicles = v;
      _recompute();
    }, onError: (_) {});
    _timer = Timer.periodic(tick, (_) => _recompute());
    _recompute();
  }

  /// The driver skipped this card (the key says which question: a raised price is a new key).
  void skip(RadarItem item) {
    _skipped.add(item.key);
    _recompute();
  }

  void _recompute() {
    if (_out.isClosed) return;
    final next = RadarEngine.compute(
      loads: _loads,
      vehicles: _vehicles,
      origin: origin(),
      now: now(),
      driverId: driverId(),
      config: config(),
      waves: wavesOn(),
      skipped: _skipped,
    );
    final changed = next.current?.key != _state.current?.key || next.queue.length != _state.queue.length;
    _state = next;
    // The ring text counts down every second, so listeners get every tick while a card is open.
    if (changed || next.current != null) _out.add(next);
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _sub?.cancel();
    _sub = null;
    await _out.close();
  }
}
