import '../constants/logistics.dart';
import '../models/load.dart';
import '../models/vehicle.dart';
import '../pricing/cities.dart';

/// A driver's last known place, used to say where an empty truck is.
typedef DriverSpot = ({double lat, double lng});

enum Balance { short, balanced, surplus }

/// One city: open loads starting there against free trucks standing there.
class SupplyDemandRow {
  final String city;
  final int demand;
  final int supply;
  const SupplyDemandRow({required this.city, required this.demand, required this.supply});

  /// Shortage: loads waiting and fewer than one truck for every two loads.
  /// Surplus: more than two trucks for every load. Otherwise balanced.
  Balance get balance {
    if (demand > 0 && supply * 2 < demand) return Balance.short;
    if (supply > 0 && supply > demand * 2) return Balance.surplus;
    return Balance.balanced;
  }

  /// Loads minus trucks (positive = trucks missing).
  int get gap => demand - supply;
}

/// Open loads against free trucks, per city and per vehicle type. Pure.
/// A truck is "free" when it is active, available, and has a known driver
/// position inside a city of the offline table (80 km). Trucks with no
/// position count in [unlocatedSupply] only. LATER(paid): real positions and
/// a heat map.
class SupplyDemand {
  final List<SupplyDemandRow> cities;
  final Map<String, SupplyDemandRow> types;
  final int totalDemand;
  final int totalSupply;
  final int unlocatedSupply;

  const SupplyDemand({required this.cities, required this.types, required this.totalDemand, required this.totalSupply, required this.unlocatedSupply});

  /// [spotOf] gives the position of the driver who runs a vehicle (null when
  /// unknown). Cities are listed biggest gap first.
  factory SupplyDemand.compute(Iterable<Load> loads, Iterable<Vehicle> vehicles, DriverSpot? Function(Vehicle v) spotOf) {
    final demandCity = <String, int>{};
    final demandType = <String, int>{};
    var demand = 0;
    for (final l in loads) {
      if (!l.isOpen) continue;
      demand++;
      final city = findCity(l.pickup)?.name ?? '';
      demandCity[city] = (demandCity[city] ?? 0) + 1;
      demandType[l.vehicleType] = (demandType[l.vehicleType] ?? 0) + 1;
    }
    final supplyCity = <String, int>{};
    final supplyType = <String, int>{};
    var supply = 0, unlocated = 0;
    for (final v in vehicles) {
      if (v.status != VehicleStatus.active || v.availability != VehicleAvailability.available) continue;
      supply++;
      supplyType[v.type] = (supplyType[v.type] ?? 0) + 1;
      final spot = spotOf(v);
      final city = spot == null ? null : nearestCity(spot.lat, spot.lng)?.name;
      if (city == null) {
        unlocated++;
      } else {
        supplyCity[city] = (supplyCity[city] ?? 0) + 1;
      }
    }
    final names = {...demandCity.keys, ...supplyCity.keys};
    final rows = [
      for (final n in names) SupplyDemandRow(city: n, demand: demandCity[n] ?? 0, supply: supplyCity[n] ?? 0),
    ]..sort((a, b) {
        final c = b.gap.compareTo(a.gap);
        return c != 0 ? c : a.city.compareTo(b.city);
      });
    final typeNames = {...demandType.keys, ...supplyType.keys}.toList()..sort();
    return SupplyDemand(
      cities: rows,
      types: {for (final t in typeNames) t: SupplyDemandRow(city: t, demand: demandType[t] ?? 0, supply: supplyType[t] ?? 0)},
      totalDemand: demand,
      totalSupply: supply,
      unlocatedSupply: unlocated,
    );
  }
}
