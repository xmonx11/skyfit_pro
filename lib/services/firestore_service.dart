import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_model.dart';

/// Low-level Firestore data access layer.
/// This service performs raw Firestore operations and returns/accepts domain
/// models.  All collection paths and retry logic live here so repositories
/// stay clean.
class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  // ── Collection references ─────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  // ── User CRUD ─────────────────────────────────────────────────────────────

  /// Creates or overwrites a user document in Firestore.
  Future<void> createUser(UserModel user) async {
    try {
      await _users.doc(user.uid).set(user.toMap(), SetOptions(merge: false));
    } on FirebaseException catch (e) {
      throw FirestoreException._fromFirebase(e, 'createUser');
    }
  }

  /// Reads a [UserModel] document.  Returns null if the document does not
  /// exist.
  Future<UserModel?> getUser(String uid) async {
    try {
      final doc = await _users.doc(uid).get();
      if (!doc.exists || doc.data() == null) return null;
      return UserModel.fromFirestore(
          doc as DocumentSnapshot<Map<String, dynamic>>);
    } on FirebaseException catch (e) {
      throw FirestoreException._fromFirebase(e, 'getUser');
    }
  }

  /// Updates specific fields of an existing user document.
  /// Use [fields] to provide only the keys that need updating.
  Future<void> updateUser(String uid, Map<String, dynamic> fields) async {
    try {
      await _users.doc(uid).update({
        ...fields,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw FirestoreException._fromFirebase(e, 'updateUser');
    }
  }

  /// Deletes a user document permanently.
  Future<void> deleteUser(String uid) async {
    try {
      await _users.doc(uid).delete();
    } on FirebaseException catch (e) {
      throw FirestoreException._fromFirebase(e, 'deleteUser');
    }
  }

  /// Returns a real-time stream of a user document.
  /// The ViewModel can listen to this for live profile updates.
  Stream<UserModel?> userStream(String uid) {
    return _users.doc(uid).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return UserModel.fromFirestore(
          doc as DocumentSnapshot<Map<String, dynamic>>);
    });
  }

  // ── Activity log sub-collection ───────────────────────────────────────────

  /// Logs a completed activity under `/users/{uid}/activityLog`.
  Future<void> logActivity(
      String uid, Map<String, dynamic> activityData) async {
    try {
      await _users
          .doc(uid)
          .collection('activityLog')
          .add({
        ...activityData,
        'loggedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw FirestoreException._fromFirebase(e, 'logActivity');
    }
  }

  /// Retrieves the last [limit] activity log entries for a user.
  Future<List<Map<String, dynamic>>> getActivityLog(
      String uid, {int limit = 20}) async {
    try {
      final snapshot = await _users
          .doc(uid)
          .collection('activityLog')
          .orderBy('loggedAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((d) => {'id': d.id, ...d.data()})
          .toList();
    } on FirebaseException catch (e) {
      throw FirestoreException._fromFirebase(e, 'getActivityLog');
    }
  }

  // ── Batch / transaction helpers ───────────────────────────────────────────

  /// Atomically creates or updates a user profile.  Safe to call on both
  /// first sign-up and subsequent Google Sign-In logins.
  Future<void> upsertUser(UserModel user) async {
    try {
      await _users.doc(user.uid).set(
        user.toMap(),
        SetOptions(merge: true), // merge keeps existing fields on login
      );
    } on FirebaseException catch (e) {
      throw FirestoreException._fromFirebase(e, 'upsertUser');
    }
  }

  // ── Generic helpers ───────────────────────────────────────────────────────

  /// Runs a series of operations inside a Firestore transaction.
  Future<T> runTransaction<T>(
      Future<T> Function(Transaction tx) handler) async {
    try {
      return await _db.runTransaction(handler);
    } on FirebaseException catch (e) {
      throw FirestoreException._fromFirebase(e, 'runTransaction');
    }
  }
}

// ── Exception ─────────────────────────────────────────────────────────────────

class FirestoreException implements Exception {
  final String message;
  final String? code;
  final String operation;

  const FirestoreException({
    required this.message,
    required this.operation,
    this.code,
  });

  factory FirestoreException._fromFirebase(
      FirebaseException e, String operation) {
    return FirestoreException(
      message: e.message ?? 'Firestore error during $operation.',
      code: e.code,
      operation: operation,
    );
  }

  @override
  String toString() =>
      'FirestoreException[$operation](${code ?? ""}): $message';
}