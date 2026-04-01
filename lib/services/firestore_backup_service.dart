import 'dart:io';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/db_service.dart';
import '../services/auth_service.dart';
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

  Future<String> _getUidWithSessionCheck() async {
    // Auth state can briefly lag on cold starts; wait a moment before failing.
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await Future.delayed(const Duration(milliseconds: 400));
      user = FirebaseAuth.instance.currentUser;
    }
    
    // If still null, try to forcefully restore Google session (handles offline-to-online transitions)
    if (user == null) {
      try {
        await AuthService().tryRestoreSessionSilently();
        user = FirebaseAuth.instance.currentUser;
      } catch (_) {}
    }

    if (user == null) throw NotSignedInException();

    try {
      await user.getIdToken();
    } on FirebaseAuthException {
      await _refreshAuthToken();
      user = FirebaseAuth.instance.currentUser;
      if (user == null) throw NotSignedInException();
    }
    return user.uid;
  }

  Future<void> _refreshAuthToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw NotSignedInException();
    await user.reload();
    final refreshedUser = FirebaseAuth.instance.currentUser;
    if (refreshedUser == null) throw NotSignedInException();
    await refreshedUser.getIdToken(true);
  }

  bool _isAuthOrPermissionError(FirebaseException e) {
    return e.code == 'permission-denied' ||
        e.code == 'unauthenticated' ||
        e.code == 'user-token-expired';
  }

  /// Checks internet connectivity before any Firestore operation.
  Future<void> _assertConnected() async {
    // Stage 1: Fast fail if WiFi/mobile adapter is completely off
    try {
      final results = await Connectivity().checkConnectivity().timeout(
        const Duration(seconds: 2),
      );
      if (results.isEmpty ||
          results.every((r) => r == ConnectivityResult.none)) {
        throw NoInternetException();
      }
    } catch (_) {
      // Ignore adapter timeout or false negatives, fail-safe to Stage 2
    }

    // Stage 2: Real internet reachability check
    try {
      final socket = await RawSocket.connect(
        '8.8.8.8',
        53,
        timeout: const Duration(seconds: 3),
      );
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
    final uid = await _getUidWithSessionCheck();

    final customers = db.getAllCustomers();
    final transactions = db.transactionsBox.values.toList();

    // SAFETY GUARD: Never upload an empty dataset to the cloud.
    // This prevents accidentally overwriting a valid cloud backup with nothing,
    // which can happen if the local DB was just cleared or sign-out was called.
    if (customers.isEmpty && transactions.isEmpty) {
      if (const bool.fromEnvironment('dart.vm.product') == false) {
        // ignore: avoid_print
        print('[FirestoreBackup] Skipping backup — local data is empty. Cloud data preserved.');
      }
      return;
    }

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
      await _withAuthRetry(() async {
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
            })
            .timeout(
              const Duration(seconds: 30),
              onTimeout: () => throw FirestoreTimeoutException(),
            );
      });
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
    final uid = await _getUidWithSessionCheck();

    db.isRestoring = true; // Signal watchers to ignore these ops
    try {
      // Fetch from Firestore with timeout
      final customerDocs = await _withAuthRetry(() async {
        return _firestore
            .collection('users')
            .doc(uid)
            .collection('customers')
            .get()
            .timeout(
              const Duration(seconds: 15),
              onTimeout: () => throw FirestoreTimeoutException(),
            );
      });

      final transactionDocs = await _withAuthRetry(() async {
        return _firestore
            .collection('users')
            .doc(uid)
            .collection('transactions')
            .get()
            .timeout(
              const Duration(seconds: 15),
              onTimeout: () => throw FirestoreTimeoutException(),
            );
      });

      final remoteCustomers = customerDocs.docs
          .map((d) => Customer.fromFirestore(d.data()))
          .toList();
      final remoteTransactions = transactionDocs.docs
          .map((d) => TransactionModel.fromFirestore(d.data()))
          .toList();

      // SAFETY GUARD: Only clear local data if the remote backup actually has
      // content. If Firestore returns empty (e.g., first-time user or network
      // returned partial data), we preserve local data unconditionally.
      if (remoteCustomers.isEmpty && remoteTransactions.isEmpty) {
        // Nothing to restore — keep local data intact.
        return;
      }

      // ---- Clear local Hive AFTER confirming remote data is non-empty
      await db.clearAll();

      // ---- Write all remote data to Hive
      for (final c in remoteCustomers) {
        await db.saveCustomer(c);
      }

      for (final t in remoteTransactions) {
        await db.saveTransaction(t);
      }

      // Update local modification time to match the backup completion roughly
      await db.setLastLocalModifiedAt(DateTime.now().millisecondsSinceEpoch);

    } on FirebaseException catch (e) {
      if (_isAuthOrPermissionError(e)) throw FirestorePermissionException();
      rethrow;
    } finally {
      db.isRestoring = false;
    }
  }

  // -------------------------------------------------------------------------
  // BACKUP METADATA
  // -------------------------------------------------------------------------

  /// Fetches the backup metadata document (may return null if never backed up).
  Future<Map<String, dynamic>?> getBackupInfo() async {
    await _assertConnected();
    final uid = await _getUidWithSessionCheck();
    try {
      final doc = await _withAuthRetry(() async {
        return _firestore
            .collection('users')
            .doc(uid)
            .collection('meta')
            .doc('backup_info')
            .get()
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => throw FirestoreTimeoutException(),
            );
      });
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
      final chunk = ops.sublist(i, (i + _batchLimit).clamp(0, ops.length));
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
        await _withAuthRetry(() async {
          await batch.commit().timeout(const Duration(seconds: 60));
        });
        return; // Success, exit the loop
      } on FirebaseException catch (e) {
        if (_isAuthOrPermissionError(e)) throw FirestorePermissionException();
        // If it's a structural error that won't resolve, throw immediately
        if (e.code == 'not-found') rethrow;
      } on TimeoutException {
        if (i == retries - 1) throw FirestoreTimeoutException();
        await Future.delayed(const Duration(seconds: 2));
      } catch (e) {
        if (i == retries - 1) rethrow; // Let unknown errors bubble up
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  Future<T> _withAuthRetry<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseException catch (e) {
      if (!_isAuthOrPermissionError(e)) rethrow;
      await _refreshAuthToken();
      try {
        return await action();
      } on FirebaseException catch (retryError) {
        if (_isAuthOrPermissionError(retryError)) {
          throw FirestorePermissionException();
        }
        rethrow;
      }
    }
  }
}

class _WriteOp {
  final DocumentReference ref;
  final Map<String, dynamic> data;
  const _WriteOp({required this.ref, required this.data});
}
