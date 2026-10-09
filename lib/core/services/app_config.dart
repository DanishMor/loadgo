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
///
/// MASTER-6 Task 38: one config document that cannot be read (offline, slow,
/// rules) never stops the others and never throws; each service keeps its
/// built-in defaults or its last good value. [failed] says how many failed.
Future<void> refreshAppConfig({bool force = false, List<Future<void> Function()>? loaders}) async {
  await _configCache.run(
      () async {
        final all = loaders ??
            <Future<void> Function()>[
              VehicleTypeService.refresh,
              PricingService.refresh,
              SettingsService.refresh,
              RiskConfigStore.refresh,
              () => OffersSwitchService.refresh(force: true),
              () => FeaturesService.refresh(force: true),
              () => AnnouncementService.refresh(force: true),
            ];
        var bad = 0;
        await Future.wait([
          for (final load in all)
            Future<void>.sync(load).timeout(const Duration(seconds: 15)).catchError((Object _) {
              bad++;
            }),
        ]);
        configRefreshFailures = bad;
      },
      force: force,
    );
  // A failure must not count as fresh: the next call tries again.
  if (configRefreshFailures > 0) _configCache.invalidate();
}

/// How many config documents failed to load in the last [refreshAppConfig].
int configRefreshFailures = 0;
