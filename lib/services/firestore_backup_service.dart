import 'dart:io';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/db_service.dart';
import '../models/customer.dart';
import '../models/transaction.dart';

// ---------------------------------------------------------------------------
// Custom error types for granular UI feedback
// ---------------------------------------------------------------------------
class NoInternetException implements Exception {
  @override
  String toString() => 'No internet connection.';
}

class NotSignedInException implements Exception {
  @override
  String toString() => 'User is not signed in.';
}

class FirestorePermissionException implements Exception {
  @override
  String toString() => 'Permission denied. Please sign in again.';
}

class FirestoreTimeoutException implements Exception {
  @override
  String toString() => 'Operation timed out. Please check your connection.';
}

// ---------------------------------------------------------------------------
// FirestoreBackupService
// ---------------------------------------------------------------------------
class FirestoreBackupService {
  static const int _batchLimit = 499; // Firestore hard limit is 500

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String get _uid {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw NotSignedInException();
    return user.uid;
  }

  /// Checks internet connectivity before any Firestore operation.
  Future<void> _assertConnected() async {
    // Stage 1: Fast fail if WiFi/mobile adapter is completely off
    try {
      final results = await Connectivity().checkConnectivity().timeout(
        const Duration(seconds: 2),
      );
      if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
        throw NoInternetException();
      }
    } catch (_) {
      // Ignore adapter timeout or false negatives, fail-safe to Stage 2
    }

    // Stage 2: Real internet reachability check
    try {
      final socket = await RawSocket.connect('8.8.8.8', 53, timeout: const Duration(seconds: 3));
      socket.close();
    } catch (_) {
      throw NoInternetException();
    }
  }

  // -------------------------------------------------------------------------
  // BACKUP
  // -------------------------------------------------------------------------

  /// Backs up all customers and transactions to Firestore using batch writes.
  /// Splits into chunks of [_batchLimit] to respect the Firestore 500-op limit.
  Future<void> backupAll(DbService db) async {
    await _assertConnected();
    final uid = _uid;

    final customers = db.getAllCustomers();
    final transactions = customers
        .expand((c) => db.getTransactionsForCustomer(c.id))
        .toList();

    // Build a flat list of Firestore write operations
    final List<_WriteOp> ops = [];

    for (final c in customers) {
      final ref = _firestore
          .collection('users')
          .doc(uid)
          .collection('customers')
          .doc(c.id);
      ops.add(_WriteOp(ref: ref, data: c.toFirestore()));
    }

    for (final t in transactions) {
      final ref = _firestore
          .collection('users')
          .doc(uid)
          .collection('transactions')
          .doc(t.id);
      ops.add(_WriteOp(ref: ref, data: t.toFirestore()));
    }

    // Commit in chunks using robust retry logic
    await _commitInChunks(ops);

    // Write backup metadata document with timeout
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('meta')
          .doc('backup_info')
          .set({
        'lastBackupAt': FieldValue.serverTimestamp(),
        'device': Platform.operatingSystem,
        'totalCustomers': customers.length,
        'totalTransactions': transactions.length,
      }).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw FirestoreTimeoutException(),
      );
    } on TimeoutException {
      throw FirestoreTimeoutException();
    }
  }

  // -------------------------------------------------------------------------
  // RESTORE
  // -------------------------------------------------------------------------

  /// Restores all data from Firestore into Hive.
  /// - If Hive is empty → full restore (no conflict check needed).
  /// - Otherwise → last-write-wins: only overwrites local if Firestore is newer.
  Future<void> restoreAll(DbService db) async {
    await _assertConnected();
    final uid = _uid;

    try {
      // Fetch from Firestore with timeout
      final customerDocs = await _firestore
          .collection('users')
          .doc(uid)
          .collection('customers')
          .get()
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw FirestoreTimeoutException(),
          );
          
      final transactionDocs = await _firestore
          .collection('users')
          .doc(uid)
          .collection('transactions')
          .get()
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw FirestoreTimeoutException(),
          );

      final remoteCustomers = customerDocs.docs
          .map((d) => Customer.fromFirestore(d.data()))
          .toList();
      final remoteTransactions = transactionDocs.docs
          .map((d) => TransactionModel.fromFirestore(d.data()))
          .toList();

      // ---- Clear local Hive before restoring to prevent stale/duplicate data
      await db.clearAll();

      // ---- Write all remote data to Hive (no conflict check needed after clear)
      for (final c in remoteCustomers) {
        await db.saveCustomer(c);
      }

      for (final t in remoteTransactions) {
        await db.saveTransaction(t);
      }
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') throw FirestorePermissionException();
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // BACKUP METADATA
  // -------------------------------------------------------------------------

  /// Fetches the backup metadata document (may return null if never backed up).
  Future<Map<String, dynamic>?> getBackupInfo() async {
    await _assertConnected();
    final uid = _uid;
    try {
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('meta')
          .doc('backup_info')
          .get()
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw FirestoreTimeoutException(),
          );
      return doc.exists ? doc.data() : null;
    } on TimeoutException {
      throw FirestoreTimeoutException();
    }
  }

  // -------------------------------------------------------------------------
  // HELPERS
  // -------------------------------------------------------------------------

  Future<void> _commitInChunks(List<_WriteOp> ops) async {
    for (int i = 0; i < ops.length; i += _batchLimit) {
      final chunk = ops.sublist(
        i,
        (i + _batchLimit).clamp(0, ops.length),
      );
      final batch = _firestore.batch();
      for (final op in chunk) {
        batch.set(op.ref, op.data);
      }
      await _safeCommit(batch);
    }
  }

  /// Retries a batch commit up to 3 times to survive intermittent drops
  Future<void> _safeCommit(WriteBatch batch) async {
    const int retries = 3;
    for (int i = 0; i < retries; i++) {
      try {
        await batch.commit().timeout(
          const Duration(seconds: 30),
        );
        return; // Success, exit the loop
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') throw FirestorePermissionException();
        // If it's a structural error that won't resolve, throw immediately
        if (e.code == 'not-found' || e.code == 'unauthenticated') rethrow;
      } catch (e) {
        if (i == retries - 1) {
          throw FirestoreTimeoutException();
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }
}

class _WriteOp {
  final DocumentReference ref;
  final Map<String, dynamic> data;
  const _WriteOp({required this.ref, required this.data});
}
