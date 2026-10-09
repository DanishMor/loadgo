import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/services/user_service.dart';
import 'banned_screen.dart';
import 'driver_consent_screen.dart';
import 'driver_kyc_screen.dart';
import 'driver_pending_screen.dart';
import 'customer_profile_setup_screen.dart';
import 'driver_profile_setup_screen.dart';
import 'role_selection_screen.dart';
import 'invite_gate_screen.dart';
import '../customer/customer_home_screen.dart';
import '../driver/driver_home_screen.dart';
import '../fleet/fleet_home_screen.dart';
import 'fleet_profile_setup_screen.dart';


// ============================================================
// ROLE RESOLVERS
// ============================================================

Future<Widget> resolveCustomerStart() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return const RoleSelectionScreen();

  final doc =
      await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

  if (!doc.exists) {
    return withInviteGate('customer', () => CustomerProfileSetupScreen(phoneNumber: user.phoneNumber ?? ''));
  }

  final data = doc.data() ?? {};
  if (data['riskTier'] == 'banned') return const BannedScreen();

  if (data['profileComplete'] != true) {
    return CustomerProfileSetupScreen(
      phoneNumber: user.phoneNumber ?? '',
      existingName: data['name']?.toString() ?? '',
    );
  }

  return const CustomerHomeScreen();
}

Future<Widget> resolveDriverStart() async {
  final data = await UserService.getUser();
  if (data?['riskTier'] == 'banned') return const BannedScreen();

  final roles = ((data?['roles'] as List?) ?? const [])
      .map((e) => e.toString())
      .toList();
  final profileComplete = data?['driverProfileComplete'] == true;
  final kycComplete = data?['kycComplete'] == true;
  final verified = data?['verified'] == true ||
      data?['verificationStatus'] == 'approved';

  if (!roles.contains('driver') || !profileComplete) {
    if (data == null) return withInviteGate('driver', () => const DriverProfileSetupScreen());
    return const DriverProfileSetupScreen();
  }
  // Router guard: Home and Loads stay closed until every document is in
  // (kycComplete) and an admin has approved the driver.
  if (data?['locationConsentAsked'] != true) {
    return const DriverConsentScreen();
  }
  if (!kycComplete) {
    return const DriverKycScreen();
  }
  if (!verified) {
    return const DriverPendingScreen();
  }
  return const DriverHomeScreen();
}



/// Transporters: profile (name, company, PAN) first, then the fleet home.
Future<Widget> resolveFleetStart() async {
  final data = await UserService.getUser();
  if (data == null) return withInviteGate('fleet', () => const FleetProfileSetupScreen());
  if (data['fleetProfileComplete'] != true) return const FleetProfileSetupScreen();
  return const FleetHomeScreen();
}
