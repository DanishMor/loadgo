import 'models/booking.dart';
import 'models/load.dart';
import 'widgets/common.dart';

/// Plain-text summaries to paste into chats. Kept in English on purpose: the
/// receiver may not use the same app language, and there is no deep link yet.
String loadShareText(Load load) => [
      'LoadGo load: ${load.pickup} -> ${load.drop}',
      '${load.cargoType}, ${formatNum(load.weight)} T, ${load.vehicleType}',
      'Pickup: ${formatDate(load.pickupDate)}',
      'Budget: ${load.budget == null ? 'Negotiable' : formatRupees(load.budget!)}',
      'ID: ${load.id}',
    ].join('\n');

String bookingShareText(Booking b) => [
      'LoadGo booking: ${b.pickup} -> ${b.drop}',
      'Status: ${b.status.replaceAll('_', ' ')}',
      '${b.cargoType}, ${formatNum(b.weight)} T',
      'Vehicle: ${b.vehicleNumber} (${b.vehicleType})',
      if (b.driverName.isNotEmpty) 'Driver: ${b.driverName}${b.driverPhone.isEmpty ? '' : ', ${b.driverPhone}'}',
      'Pickup: ${formatDate(b.pickupDate)}',
      'Booking ID: ${b.id}',
    ].join('\n');
