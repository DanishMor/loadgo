import 'package:flutter/widgets.dart';

import '../core/features/features.dart';
import '../core/services/features_service.dart';
import '../core/wallet/hub/hub_screens.dart';
import 'wallet_screen.dart';

/// The page the driver's earnings button opens: the new earnings and accounts
/// hub when the `walletHub` flag is on, otherwise the Wallet screen as before.
Widget driverWalletPage() => FeaturesService.isOn(FeatureKey.walletHub) ? const DriverHubScreen() : const WalletScreen();
