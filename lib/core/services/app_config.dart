import '../announcement/announcement.dart';
import '../risk/risk_config.dart';
import 'features_service.dart';
import 'offers_switch_service.dart';
import 'pricing_service.dart';
import 'settings_service.dart';
import 'ttl_cache.dart';
import 'vehicle_type_service.dart';

final TtlCache _configCache = TtlCache(const Duration(minutes: 15));

/// Reloads every admin-managed config document (call after sign-in). Inside
/// 15 minutes of the last load it does nothing, to save Firestore reads;
/// [force] (e.g. after an admin saved a change) always reloads.
Future<void> refreshAppConfig({bool force = false}) => _configCache.run(
      () => Future.wait([
        VehicleTypeService.refresh(),
        PricingService.refresh(),
        SettingsService.refresh(),
        RiskConfigStore.refresh(),
        OffersSwitchService.refresh(force: true),
        FeaturesService.refresh(force: true),
        AnnouncementService.refresh(force: true),
      ]),
      force: force,
    );
