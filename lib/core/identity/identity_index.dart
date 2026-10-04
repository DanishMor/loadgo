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

  /// Registers [newNumbers] for [uid] and drops the entries of [oldNumbers]
  /// that they replace, all inside [batch]. A null or empty new number clears
  /// the claim (only GST may be cleared; the rules refuse the rest). Throws
  /// [DuplicateIdentityException] if another account already holds a new
  /// number. Returns the `identityHashes` patch to merge into the user
  /// document in the same batch (the rules read it).
  static Future<Map<String, Object?>> applyChanges(
    WriteBatch batch, {
    required String uid,
    required String role,
    required Map<IdentityType, String?> oldNumbers,
    required Map<IdentityType, String?> newNumbers,
  }) async {
    final db = Backend.db;
    String? clean(String? n) {
      final v = n == null ? '' : normaliseDocNumber(n);
      return v.isEmpty ? null : v;
    }

    final patch = <String, Object?>{};
    for (final e in newNumbers.entries) {
      final type = e.key;
      final next = clean(e.value);
      final prev = clean(oldNumbers[type]);

      if (next != null) {
        final ref = db.collection(collection).doc(docId(type, next));
        final snap = await ref.get();
        if (snap.exists && snap.data()?['uid'] != uid) throw DuplicateIdentityException(type);
        if (!snap.exists) {
          batch.set(ref, {'uid': uid, 'role': role, 'type': type.name, 'createdAt': FieldValue.serverTimestamp()});
        }
        patch[type.name] = docId(type, next);
      } else {
        patch[type.name] = FieldValue.delete();
      }

      if (prev != null && prev != next) {
        final oldRef = db.collection(collection).doc(docId(type, prev));
        final oldSnap = await oldRef.get();
        if (oldSnap.exists && oldSnap.data()?['uid'] == uid) batch.delete(oldRef);
      }
    }
    return patch;
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
