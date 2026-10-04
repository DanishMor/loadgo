import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../l10n/l10n.dart';
import '../services/backend.dart';
import 'kyc_validators.dart';

/// Document kinds that must be unique across accounts. Aadhaar is not here:
/// only its last four digits are kept, which many people share.
enum IdentityType { dl, pan, rc, gst }

/// The same document is already registered by another account.
class DuplicateIdentityException implements Exception {
  final IdentityType type;
  const DuplicateIdentityException(this.type);

  @override
  String toString() => 'DuplicateIdentityException($type)';
}

/// identity_index/{sha256(type + number)} = {uid, role}. The number itself is
/// never stored in the index. LATER(paid): Cloud Function that hashes with an
/// HMAC secret, so the id cannot be brute-forced from a known number.
class IdentityIndex {
  IdentityIndex._();

  static const collection = 'identity_index';

  static String docId(IdentityType type, String number) =>
      sha256.convert(utf8.encode(type.name + normaliseDocNumber(number))).toString();

  /// Throws [DuplicateIdentityException] when any of [claims] (type -> number)
  /// belongs to another uid. Claims this account already holds are skipped.
  static Future<void> assertAvailable(Map<IdentityType, String> claims, {required String uid}) async {
    final db = Backend.db;
    for (final e in claims.entries) {
      final snap = await db.collection(collection).doc(docId(e.key, e.value)).get();
      if (snap.exists && snap.data()?['uid'] != uid) throw DuplicateIdentityException(e.key);
    }
  }

  /// Adds create-only index writes for [claims] to [batch]. Call
  /// [assertAvailable] first; the rules also refuse a second create, so a
  /// race still fails the whole batch.
  static Future<void> addClaims(
    WriteBatch batch,
    Map<IdentityType, String> claims, {
    required String uid,
    required String role,
  }) async {
    final db = Backend.db;
    for (final e in claims.entries) {
      final ref = db.collection(collection).doc(docId(e.key, e.value));
      final snap = await ref.get();
      if (snap.exists) continue; // already ours (assertAvailable checked)
      batch.set(ref, {'uid': uid, 'role': role, 'createdAt': FieldValue.serverTimestamp()});
    }
  }
}

/// Translated "already registered" message for a [DuplicateIdentityException].
void showDuplicateIdentity(BuildContext context, DuplicateIdentityException e) {
  final doc = tr(context, switch (e.type) {
    IdentityType.dl => 'docNameDl',
    IdentityType.pan => 'docNamePan',
    IdentityType.rc => 'docNameRc',
    IdentityType.gst => 'docNameGst',
  });
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(trf(context, 'identityDuplicate', {'doc': doc})), behavior: SnackBarBehavior.floating),
  );
}
