import 'models/booking.dart';
import 'models/load.dart';
import 'share/share_links.dart';
import 'widgets/common.dart';

/// Plain-text summaries to paste into chats. Kept in English on purpose: the
/// receiver may not use the same app language, and loads add a deep link when shared (ShareLinks).
String loadShareText(Load load) => [
      'LoadGo load: ${load.route.join(' -> ')}',
      '${load.cargoType}, ${formatNum(load.weight)} T, ${load.vehicleType}',
      'Pickup: ${formatDate(load.pickupDate)}',
      'Budget: ${load.budget == null ? 'Negotiable' : formatRupees(load.budget!)}',
      if (load.estimate != null) 'Estimate: ${formatPaise(load.estimate!.total)}',
      'ID: ${load.id}',
    ].join('\n');

String bookingShareText(Booking b) => [
      'LoadGo booking: ${b.route.join(' -> ')}',
      'Status: ${b.status.replaceAll('_', ' ')}',
      '${b.cargoType}, ${formatNum(b.weight)} T',
      'Vehicle: ${b.vehicleNumber} (${b.vehicleType})',
      if (b.driverName.isNotEmpty)
        'Driver: ${b.driverName}${PhoneVisibility.visiblePhone(b.status, b.driverPhone).isEmpty ? '' : ', ${b.driverPhone}'}',
      'Pickup: ${formatDate(b.pickupDate)}',
      'Booking ID: ${b.id}',
    ].join('\n');
