import 'pricing_service.dart';
import 'vehicle_type_service.dart';

/// Reloads every admin-managed config document (call after sign-in).
Future<void> refreshAppConfig() => Future.wait([VehicleTypeService.refresh(), PricingService.refresh()]);
