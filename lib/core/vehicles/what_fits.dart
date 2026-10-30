import 'vehicle_catalog.dart';

/// E17: what the customer knows about the goods. Only the weight is required.
class FitRequest {
  final double tons;

  /// Space the goods take, in cubic feet.
  final double? volumeCft;

  /// The longest single item, in feet.
  final double? longestFt;

  /// One of [VehicleCatalog.goodsKinds].
  final String? goods;

  const FitRequest({required this.tons, this.volumeCft, this.longestFt, this.goods});

  bool get valid => tons.isFinite && tons > 0 && (volumeCft == null || (volumeCft!.isFinite && volumeCft! >= 0)) && (longestFt == null || (longestFt!.isFinite && longestFt! >= 0));
}

/// Goods that need their own kind of body: a tanker for liquids, a reefer for cold goods and so on.
const Set<String> specialGoods = {'liquids', 'coldchain', 'vehicles', 'containers', 'sand'};

/// Goods are never packed without gaps: ask for 15% more space than the goods take (UNVERIFIED rule of thumb).
const double packingMargin = 1.15;

/// How high goods are usually stacked on an open body, in feet (UNVERIFIED, docs/DECISIONS.md).
const double openStackFt = 5;

/// Usable cubic feet: the closed box, or the floor of an open body times [openStackFt]. 0 for a crane.
double usableCft(VehicleSpec v) {
  if (v.lifts) return 0;
  return v.open ? v.lengthFt * v.widthFt * openStackFt : v.volumeCft;
}

/// The vehicles that can take the goods, best first: right kind of body, then the smallest that is enough
/// (payload, then space, then price band). Empty when nothing fits or the request is not valid.
List<VehicleSpec> whatFits(List<VehicleSpec> all, FitRequest r) {
  if (!r.valid) return const [];
  final fits = [
    for (final v in all)
      if (v.carries(r.tons) &&
          (r.longestFt == null || r.longestFt! <= v.lengthFt) &&
          (r.volumeCft == null || r.volumeCft! * packingMargin <= usableCft(v)) &&
          (r.goods == null || !specialGoods.contains(r.goods) || v.goods.contains(r.goods)) &&
          // Special bodies are only offered for the goods they are made for.
          (v.goods.every(specialGoods.contains) ? (r.goods != null && v.goods.contains(r.goods)) : true))
        v,
  ];
  int byGoods(VehicleSpec v) => r.goods != null && v.goods.contains(r.goods) ? 0 : 1;
  fits.sort((a, b) {
    var c = byGoods(a).compareTo(byGoods(b));
    if (c != 0) return c;
    c = a.maxTons.compareTo(b.maxTons);
    if (c != 0) return c;
    c = usableCft(a).compareTo(usableCft(b));
    if (c != 0) return c;
    return a.priceBand.compareTo(b.priceBand);
  });
  return List.unmodifiable(fits);
}
