# Feature flags (E3)

All switches live in `config/features` (`{pilotMode, flags}`) and are read through `Features.isOn` (`lib/core/features/features.dart`). Admin > Features shows them by group with Default / On / Off. Kill-switch groups (one tap, explicit OFF) are in `lib/core/features/kill_switches.dart` and `docs/INCIDENT_RESPONSE.md`.

Rules for every flag:
- A new flag defaults OFF in pilot and normal mode. The one exception is `designV3` (the visual upgrade); the Classic theme stays selectable.
- A flag is added to `Features.registry` only when its feature is finished. Until then it is `planned` below, and `test/flag_registry_test.dart` fails if a planned flag is registered. This way nothing half-built can be reached.
- A `live` Elite flag lists its entry points; the guard test checks that each file reads `FeatureKey.<flag>`.
- Regulated parts use `legalGate*` keys (camelCase, because a dot would split the Firestore field path). They sit in the Legal group, are OFF in every mode, and need an explicit owner action.

## Existing flags (before the Elite plan)

| Flag | Group | Default (pilot / normal) | Depends on | Risk | Switch-on order |
|---|---|---|---|---|---|
| `driverNetwork` | core | off / on | - | low | any |
| `emptyTrucks` | core | off / on | - | low | any |
| `businessTools` | core | off / on | - | low | any |
| `rentalMovers` | core | off / on | - | low | any |
| `driverRewards` | core | off / on | - | low | any |
| `tripShare` | core | on / on | - | low | on |
| `problemReport` | core | on / on | - | low | on |
| `transporter` | core | on / on | - | medium | on |
| `bilty` | core | on / on | - | low | on |
| `bizCard` | core | off / off | businessTools | low | after businessTools |
| `khata` | core | off / off | - | low | any |
| `rateRange` | core | off / off | - | low | any |
| `tripTrustCard` | core | off / off | - | low | any |
| `uiV2` | design | on / on | - | low | on |
| `secureScreens` | security | off / off | phone test | medium | after a phone test |
| `appLock` | security | off / off | phone test | medium | after a phone test |
| `safetyCheckin` | security | off / off | - | low | any |
| `appCheckEnforce` | security | off / off | App Check set up (APP_CHECK.md) | high | last, after metrics are clean |
| `walletHub` | money | off / off | - | medium | 1 |
| `walletStepUp` | money | off / off | walletHub | medium | 2 |
| `walletLimits` | money | off / off | walletHub | medium | 3 |
| `walletMakerChecker` | money | off / off | walletHub, two finance admins | medium | 4 |
| `payHold` | money | off / off | owner legal check | high | owner decision |
| `paymentGateway` | money | off / off | Blaze, gateway keys, serverWallet | high | after serverWallet |
| `serverLimits` | server | off / off | Blaze, functions deployed | medium | 1 |
| `serverChatScan` | server | off / off | functions deployed | low | 2 |
| `serverCredits` | server | off / off | functions deployed | medium | 3 |
| `serverTrust` | server | off / off | functions deployed | medium | 4 |
| `serverJobs` | server | off / off | functions deployed | low | 5 |
| `serverAdminActions` | server | off / off | functions deployed | medium | 6 |
| `serverDeletion` | server | off / off | functions deployed | high | 7 |
| `serverWallet` | server | off / off | functions deployed | high | 8 |
| `adminBroadcast` | server | off / off | pushNotifications | medium | after push |
| `dispatchV2` | server | off / off | functions deployed | high | after serverLimits |
| `pushNotifications` | connect | off / off | FCM, functions | medium | any after Blaze |
| `photoUploads` | connect | off / off | Storage rules published | medium | after storage rules |
| `kycVerify` | connect | off / off | KYC partner key | high | owner decision |
| `smsGateway` | connect | off / off | SMS partner key | high | owner decision |
| `liveLocation` | connect | off / off | functions deployed | medium | any after Blaze |
| `maps` | connect | off / off | Maps key as a secret | medium | any after Blaze |

## Elite flags

Status `planned` = not registered and not reachable. `live` = registered, entry points guarded.

| Flag | Phase | Status | Group | Default | Depends on | Risk | Entry points |
|---|---|---|---|---|---|---|---|
| `designV3` | E7 | live | design | ON | - | low | `lib/main.dart`, `lib/core/settings/settings_screen.dart` |
| `vehicleCatalog` | E17 | live | core | off | - | low | `lib/customer/v2/booking_wizard_screen.dart`, `lib/customer/v2/bid_room_screen.dart`, `lib/customer/truck_board_screen.dart` |
| `vehiclePhotos` | E18 | live | connect | off | photoUploads, storage rules | medium | `lib/driver/my_vehicles_screen.dart`, `lib/admin/admin_dashboard_screen.dart`, `lib/customer/v2/bid_room_screen.dart` |
| `cargoPhotos` | E19 | planned | connect | off | vehiclePhotos | medium | - |
| `homeV3` | E21 | planned | design | off | designV3 | low | - |
| `onboardingV3` | E26 | planned | design | off | designV3 | low | - |
| `priceCard` | E27 | planned | core | off | - | low | - |
| `partLoad` | E28 | planned | core | off | rules published | medium | - |
| `bulkUpload` | E29 | planned | core | off | businessTools | medium | - |
| `laneRfq` | E30 | planned | core | off | businessTools | medium | - |
| `quoteShare` | E31 | planned | core | off | - | low | - |
| `legalGateInsurance` | E32 | planned | legal | off | owner legal check, insurer partner | high | - |
| `tollEstimate` | E33 | planned | connect | off | maps | low | - |
| `reliabilityBadges` | E34 | planned | core | off | - | low | - |
| `goingTo` | E35 | planned | core | off | - | low | - |
| `priorityDispatch` | E36 | planned | server | off | dispatchV2, blackTier | medium | - |
| `tripAlerts` | E37 | planned | core | off | liveLocation | medium | - |
| `trustPassport` | E39 | planned | security | off | - | low | - |
| `safetySuite` | E40 | planned | security | off | safetyCheckin | medium | - |
| `cargoCondition` | E41 | planned | core | off | cargoPhotos | low | - |
| `kycLiveness` | E42 | planned | connect | off | kycVerify | high | - |
| `milestonePay` | E43 | planned | money | off | walletHub | high | - |
| `legalGateEscrow` | E43 | planned | legal | off | owner legal check, milestonePay | high | - |
| `financeDocs` | E44 | planned | money | off | - | low | - |
| `legalGatePayout` | E45 | planned | legal | off | owner legal check, payout partner | high | - |
| `legalGateCredit` | E45 | planned | legal | off | owner legal check, credit partner | high | - |
| `driverTools` | E47 | planned | core | off | - | low | - |
| `voiceAnnounce` | E48 | planned | core | off | - | low | - |
| `nearbyServices` | E49 | planned | connect | off | - | low | - |
| `safetyLessons` | E50 | planned | security | off | - | low | - |
| `fleetAnalytics` | E52 | planned | core | off | transporter | low | - |
| `fleetMap` | E53 | planned | connect | off | maps, liveLocation | medium | - |
| `erpApi` | E54 | planned | server | off | functions deployed | high | - |
| `esgReport` | E55 | planned | core | off | - | low | - |
| `chatV2` | E57 | planned | core | off | - | medium | - |
| `autoTranslate` | E57 | planned | connect | off | chatV2 | medium | - |
| `whatsappGateway` | E58 | planned | connect | off | - | high | - |
| `trackingV2` | E59 | planned | connect | off | liveLocation, maps | medium | - |
| `deviceIngest` | E60 | planned | server | off | functions deployed | medium | - |
| `loyaltyTiers` | E61 | planned | core | off | - | medium | - |
| `referralV2` | E62 | planned | core | off | serverCredits | medium | - |
| `blackTier` | E63 | planned | core | off | trustPassport, loyaltyTiers | medium | - |
| `ocrAutofill` | E65 | planned | connect | off | - | medium | - |
| `sahayakV2` | E66 | planned | core | off | - | low | - |
| `fraudHeuristics` | E67 | planned | server | off | serverTrust | medium | - |
| `routeOrder` | E68 | planned | core | off | - | low | - |
| `cityPricing` | E69 | planned | money | off | - | high | - |
| `funnels` | E70 | planned | server | off | - | low | - |
| `supportCrm` | E71 | planned | core | off | - | low | - |
| `experiments` | E72 | planned | server | off | - | medium | - |
| `axleCalc` | E73 | planned | core | off | - | low | - |
| `privacyCentre` | E74 | planned | security | off | serverDeletion | medium | - |
| `lowDataMode` | E76 | planned | core | off | - | low | - |

Switch-on order for the Elite flags is filled in at E83, when each one is live.
