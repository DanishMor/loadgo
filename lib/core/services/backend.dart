import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Single access point for Firestore and the signed-in uid, so services can be
/// unit-tested against a fake Firestore without initializing Firebase.
class Backend {
  Backend._();

  static FirebaseFirestore? _db;
  static String? Function()? _uid;
  static FileUploader? _uploader;
  static FirebaseAuth Function()? _auth;

  static FirebaseFirestore get db => _db ??= FirebaseFirestore.instance;

  /// The Firebase Auth instance (a mock in tests).
  static FirebaseAuth get auth => _auth != null ? _auth!() : FirebaseAuth.instance;

  /// The signed-in user, or null.
  static User? get currentUser => auth.currentUser;

  static String? get uid =>
      _uid != null ? _uid!() : auth.currentUser?.uid;

  /// Throws when nobody is signed in; use for write paths.
  static String requireUid() {
    final id = uid;
    if (id == null) throw StateError('Not signed in');
    return id;
  }

  /// Uploads bytes to Firebase Storage at [path] and returns the download URL.
  static FileUploader get upload => _uploader ??= _storageUpload;

  static Future<String> _storageUpload(String path, Uint8List bytes, String contentType) async {
    final ref = FirebaseStorage.instance.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
  }

  @visibleForTesting
  static void useFakes({required FirebaseFirestore db, required String? Function() uid, FileUploader? uploader, FirebaseAuth Function()? auth}) {
    _db = db;
    _uid = uid;
    _uploader = uploader;
    _auth = auth;
  }
}

typedef FileUploader = Future<String> Function(String path, Uint8List bytes, String contentType);

/// Firestore lists are sorted client-side to avoid needing composite indexes.
int newestFirst(Timestamp? a, Timestamp? b) {
  // Pending server timestamps are null locally; treat them as newest.
  if (a == null && b == null) return 0;
  if (a == null) return -1;
  if (b == null) return 1;
  return b.compareTo(a);
}

/// Newest-first live page of [base] holding at most [limit] documents.
///
/// Ordering by `createdAt` next to an equality filter needs a composite index
/// (firestore.indexes.json). Until that is deployed the query fails with
/// failed-precondition, so we fall back to an unordered limited query and let
/// the caller's client-side sort order the page.
Stream<QuerySnapshot<Map<String, dynamic>>> newestPage(Query<Map<String, dynamic>> base, int limit) async* {
  try {
    yield* base.orderBy('createdAt', descending: true).limit(limit).snapshots();
  } on FirebaseException catch (e) {
    if (e.code != 'failed-precondition') rethrow;
    yield* base.limit(limit).snapshots();
  }
}
