import '../constants/logistics.dart';
import 'booking.dart';
import 'load.dart';

/// `users/{uid}/load_templates/{id}`: a load the customer posts again and
/// again (route, goods, vehicle, notes). Dates are never stored.
class LoadTemplate {
  static const maxTemplates = 20;

  final String id;
  final String name;
  final String pickup;
  final String drop;
  final String cargoType;
  final num weight;
  final String vehicleType;
  final num? budget;
  final String notes;
  final String pickupSlot;
  final bool fragile;
  final bool highValue;
  final String? costCenter;

  const LoadTemplate({
    required this.id,
    required this.name,
    required this.pickup,
    required this.drop,
    required this.cargoType,
    required this.weight,
    required this.vehicleType,
    this.budget,
    this.notes = '',
    this.pickupSlot = PickupSlot.any,
    this.fragile = false,
    this.highValue = false,
    this.costCenter,
  });

  factory LoadTemplate.fromDoc(String id, Map<String, dynamic> d) => LoadTemplate(
        id: id,
        name: d['name'] as String? ?? '',
        pickup: d['pickup'] as String? ?? '',
        drop: d['drop'] as String? ?? '',
        cargoType: d['cargoType'] as String? ?? '',
        weight: d['weight'] as num? ?? 0,
        vehicleType: d['vehicleType'] as String? ?? '',
        budget: d['budget'] as num?,
        notes: d['notes'] as String? ?? '',
        pickupSlot: d['pickupSlot'] as String? ?? PickupSlot.any,
        fragile: d['fragile'] == true,
        highValue: d['highValue'] == true,
        costCenter: d['costCenter'] as String?,
      );

  Map<String, Object?> toMap() => {
        'name': name,
        'pickup': pickup,
        'drop': drop,
        'cargoType': cargoType,
        'weight': weight,
        'vehicleType': vehicleType,
        'budget': budget,
        'notes': notes,
        'pickupSlot': pickupSlot,
        'fragile': fragile,
        'highValue': highValue,
        if (costCenter != null && costCenter!.isNotEmpty) 'costCenter': costCenter,
      };

  /// What the Post Load screen pre-fills from.
  Load toLoadDraft() => Load(
        id: '',
        shipperId: '',
        pickup: pickup,
        drop: drop,
        cargoType: cargoType,
        weight: weight,
        vehicleType: vehicleType,
        budget: budget,
        pickupDate: null,
        notes: notes,
        status: LoadStatus.open,
        pickupSlot: pickupSlot,
        fragile: fragile,
        highValue: highValue,
        costCenter: costCenter,
      );
}

/// `users/{uid}/favourite_drivers/{driverId}`.
class FavouriteDriver {
  final String driverId;
  final String name;
  final String vehicleNumber;

  const FavouriteDriver({required this.driverId, this.name = '', this.vehicleNumber = ''});

  factory FavouriteDriver.fromDoc(String id, Map<String, dynamic> d) =>
      FavouriteDriver(driverId: id, name: d['name'] as String? ?? '', vehicleNumber: d['vehicleNumber'] as String? ?? '');
}

/// `users/{uid}/blocked_drivers/{driverId}`: a driver this customer never
/// wants. New loads carry the ids in `blockedDriverIds`; that driver does not
/// see them and cannot accept them.
class BlockedDriver {
  static const maxBlocked = 50;

  final String driverId;
  final String name;

  const BlockedDriver({required this.driverId, this.name = ''});

  factory BlockedDriver.fromDoc(String id, Map<String, dynamic> d) => BlockedDriver(driverId: id, name: d['name'] as String? ?? '');
}

/// "Book again": the earlier booking's route, goods and vehicle as a draft
/// for the Post Load screen. Dates, price and driver are not carried over.
Load loadDraftFromBooking(Booking b, {String? invitedDriverId}) => Load(
      id: '',
      shipperId: b.customerId,
      pickup: b.pickup,
      drop: b.drop,
      cargoType: b.cargoType,
      weight: b.weight,
      vehicleType: b.vehicleType,
      budget: b.budget,
      pickupDate: null,
      notes: b.notes,
      status: LoadStatus.open,
      extraPickups: b.extraPickups,
      extraDrops: b.extraDrops,
      paymentMode: b.paymentMode,
      bookingType: b.bookingType,
      helpers: b.helpers,
      rentalHours: b.rentalHours,
      containerNumber: b.containerNumber,
      invitedDriverId: invitedDriverId,
      costCenter: b.costCenter,
    );

