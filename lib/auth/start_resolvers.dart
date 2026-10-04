import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/services/user_service.dart';
import 'driver_pending_screen.dart';
import 'customer_profile_setup_screen.dart';
import 'driver_profile_setup_screen.dart';
import 'role_selection_screen.dart';
import '../customer/customer_home_screen.dart';
import '../driver/driver_home_screen.dart';


// ============================================================
// ROLE RESOLVERS
// ============================================================

Future<Widget> resolveCustomerStart() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return const RoleSelectionScreen();

  final doc =
      await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

  if (!doc.exists) {
    return CustomerProfileSetupScreen(phoneNumber: user.phoneNumber ?? '');
  }

  final data = doc.data() ?? {};

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

  final roles = ((data?['roles'] as List?) ?? const [])
      .map((e) => e.toString())
      .toList();
  final profileComplete = data?['driverProfileComplete'] == true;
  final verified = data?['verified'] == true ||
      data?['verificationStatus'] == 'approved';

  if (!roles.contains('driver') || !profileComplete) {
    return const DriverProfileSetupScreen();
  }
  if (!verified) {
    return const DriverPendingScreen();
  }
  return const DriverHomeScreen();
}

