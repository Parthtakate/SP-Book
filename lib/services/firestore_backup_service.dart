import 'dart:io';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

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

  String get _ts => DateTime.now().toIso8601String();

  Future<String> _getUidWithSessionCheck() async {
    debugPrint('[AUTH][$_ts] _getUidWithSessionCheck() called');
    User? user = FirebaseAuth.instance.currentUser;
    debugPrint('[AUTH][$_ts] Initial currentUser: uid=${user?.uid}');

    // ── FIX: Wait for Firebase Auth to actually restore its session ──
    // On cold starts, FirebaseAuth.instance.currentUser can be null for
    // up to ~1-2 seconds while the SDK restores the persisted session.
    if (user == null) {
      if (kDebugMode) debugPrint('[AUTH][$_ts] currentUser is null — waiting for authStateChanges (up to 5s)...');
      try {
        user = await FirebaseAuth.instance
            .authStateChanges()
            .firstWhere((u) => u != null)
            .timeout(const Duration(seconds: 5));
        if (kDebugMode) debugPrint('[AUTH][$_ts] authStateChanges emitted user: uid=${user?.uid}');
      } on TimeoutException {
        if (kDebugMode) debugPrint('[AUTH][$_ts] authStateChanges timed out after 5s — user still null');
      }
    }

    // Last resort: try to forcefully restore Google session
    if (user == null) {
      if (kDebugMode) debugPrint('[AUTH][$_ts] Still null — attempting tryRestoreSessionSilently()...');
      try {
        await AuthService().tryRestoreSessionSilently();
        user = FirebaseAuth.instance.currentUser;
        if (kDebugMode) debugPrint('[AUTH][$_ts] After silent restore: uid=${user?.uid}');
      } catch (e) {
        if (kDebugMode) debugPrint('[AUTH][$_ts] tryRestoreSessionSilently() failed: $e');
      }
    }

    if (user == null) {
      if (kDebugMode) debugPrint('[ERROR][$_ts] _getUidWithSessionCheck: user is STILL null — throwing NotSignedInException');
      throw NotSignedInException();
    }

    try {
      if (kDebugMode) debugPrint('[AUTH][$_ts] Validating ID token for uid=${user.uid}...');
      await user.getIdToken();
      if (kDebugMode) debugPrint('[AUTH][$_ts] ID token valid');
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) debugPrint('[AUTH][$_ts] ID token invalid ($e) — refreshing...');
      await _refreshAuthToken();
      user = FirebaseAuth.instance.currentUser;
      if (user == null) throw NotSignedInException();
      if (kDebugMode) debugPrint('[AUTH][$_ts] Token refreshed, uid=${user.uid}');
    }
    if (kDebugMode) debugPrint('[AUTH][$_ts] _getUidWithSessionCheck() returning uid=${user.uid}');
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
    try {
      final results = await Connectivity().checkConnectivity().timeout(
        const Duration(seconds: 2),
      );
      if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
        throw NoInternetException();
      }
    } catch (_) {
      // Ignore adapter timeout, fall through to real socket check
    }

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
  /// Splits into chunks of [_batchLimit] to respect Firestore's 500-op limit.
  Future<void> backupAll(DbService db) async {
    await _assertConnected();
    final uid = await _getUidWithSessionCheck();

    // Include ALL customers (active + soft-deleted) so the Recycle Bin
    // survives a device swap or reinstall. getAllCustomers() was incorrect
    // here because it filters isDeleted==true (Phase 4 audit fix — P0).
    final customers = db.customersBox.values.toList();
    final transactions = db.transactionsBox.values.toList();

    // SAFETY GUARD: Never upload empty data to cloud.
    if (customers.isEmpty && transactions.isEmpty) {
      if (kDebugMode) debugPrint('[FirestoreBackup] Skipping backup — local data is empty. Cloud data preserved.');
      return;
    }

    final List<_WriteOp> ops = [];

    for (final c in customers) {
      final ref = _firestore
          .collection('users').doc(uid)
          .collection('customers').doc(c.id);
      ops.add(_WriteOp(ref: ref, data: c.toFirestore()));
    }

    for (final t in transactions) {
      final ref = _firestore
          .collection('users').doc(uid)
          .collection('transactions').doc(t.id);
      ops.add(_WriteOp(ref: ref, data: t.toFirestore()));
    }

    await _commitInChunks(ops);

    // Write backup metadata and retrieve server timestamp for clock-safe comparisons
    await _writeBackupInfoAndStoreServerTime(uid, db, customers.length, transactions.length);
  }

  /// Incrementally backs up changes using the local sync_queue.
  Future<void> backupIncremental(DbService db) async {
    await _assertConnected();
    final uid = await _getUidWithSessionCheck();

    final queue = db.syncQueue;
    if (queue.isEmpty) return;

    final keys = queue.keys.toList();
    final List<_WriteOp> ops = [];
    final List<dynamic> skippedKeys = [];

    for (final key in keys) {
      final entry = queue.get(key);
      if (entry is! Map) {
        skippedKeys.add(key);
        continue;
      }
      final String type = entry['type'];
      final String id = entry['id'];
      final String action = entry['action'];

      DocumentReference ref;
      if (type == 'customer') {
        ref = _firestore.collection('users').doc(uid).collection('customers').doc(id);
      } else {
        ref = _firestore.collection('users').doc(uid).collection('transactions').doc(id);
      }

      if (action == 'delete') {
        ops.add(_WriteOp(ref: ref, data: null, isDelete: true, queueKey: key));
      } else {
        if (type == 'customer') {
          final customer = db.customersBox.get(id);
          if (customer != null) {
            ops.add(_WriteOp(ref: ref, data: customer.toFirestore(), isDelete: false, queueKey: key));
          } else {
            skippedKeys.add(key);
          }
        } else {
          final txn = db.transactionsBox.get(id);
          if (txn != null) {
            ops.add(_WriteOp(ref: ref, data: txn.toFirestore(), isDelete: false, queueKey: key));
          } else {
            skippedKeys.add(key);
          }
        }
      }
    }

    if (ops.isEmpty) {
      if (skippedKeys.isNotEmpty) await queue.deleteAll(skippedKeys);
      return;
    }

    await _commitIncrementalChunks(ops, queue, skippedKeys);

    // Update metadata and store server timestamp locally for clock-safe comparisons
    await _writeBackupInfoAndStoreServerTime(
      uid, db, db.customersBox.length, db.transactionsBox.length);
  }

  /// Writes backup_info to Firestore, then reads back the server-issued
  /// timestamp and stores it in Hive. This timestamp is used for conflict
  /// resolution so we never depend on the device clock.
  Future<void> _writeBackupInfoAndStoreServerTime(
    String uid, DbService db, int customerCount, int txnCount) async {
    try {
      await _withAuthRetry(() async {
        final docRef = _firestore
            .collection('users').doc(uid)
            .collection('meta').doc('backup_info');

        await docRef.set({
          'lastBackupAt': FieldValue.serverTimestamp(),
          'device': Platform.operatingSystem,
          'totalCustomers': customerCount,
          'totalTransactions': txnCount,
        }).timeout(const Duration(seconds: 30), onTimeout: () => throw FirestoreTimeoutException());

        // --- FIX: Read back the server-issued timestamp (immune to device clock drift) ---
        // We wait a moment for Firestore to settle the serverTimestamp, then read it back.
        final snapshot = await docRef.get().timeout(const Duration(seconds: 10));
        if (snapshot.exists) {
          final data = snapshot.data();
          final lastBackupAt = data?['lastBackupAt'];
          if (lastBackupAt is Timestamp) {
            await db.setLastAcknowledgedServerTime(lastBackupAt.millisecondsSinceEpoch);
            if (kDebugMode) debugPrint('[SYNC][$_ts] Stored server timestamp: ${lastBackupAt.millisecondsSinceEpoch}');
          }
        }
      });
    } on TimeoutException {
      throw FirestoreTimeoutException();
    }
  }

  // -------------------------------------------------------------------------
  // RESTORE — with TOCTOU crash safety + multi-device merge
  // -------------------------------------------------------------------------

  /// Restores data from Firestore into Hive using per-document last-write-wins.
  ///
  /// **Crash safety (TOCTOU fix):** A `pendingRestore` flag is written to Hive
  /// BEFORE any local data is modified. If the app crashes mid-restore, the
  /// next startup detects the flag and re-runs `restoreAll()` automatically.
  ///
  /// **Multi-device merge:** Instead of wiping all local data first, we only
  /// overwrite local documents where the remote version is strictly newer.
  /// Records that exist locally but not in the remote snapshot are preserved.
  Future<void> restoreAll(DbService db) async {
    debugPrint('[SYNC][$_ts] restoreAll() STARTED');
    await _assertConnected();
    final uid = await _getUidWithSessionCheck();

    // ── TOCTOU SAFETY: Mark restore as in-progress BEFORE touching local data ──
    await db.setPendingRestore(true);
    db.setRestoringCallback(true);

    try {
      // Fetch both collections concurrently
      if (kDebugMode) debugPrint('[SYNC][$_ts] restoreAll() fetching customers & transactions from Firestore...');
      final results = await Future.wait([
        _withAuthRetry(() => _firestore
            .collection('users').doc(uid).collection('customers')
            .get().timeout(const Duration(seconds: 15),
                onTimeout: () => throw FirestoreTimeoutException())),
        _withAuthRetry(() => _firestore
            .collection('users').doc(uid).collection('transactions')
            .get().timeout(const Duration(seconds: 15),
                onTimeout: () => throw FirestoreTimeoutException())),
      ]);

      final customerDocs = results[0];
      final transactionDocs = results[1];

      final remoteCustomers = customerDocs.docs
          .map((d) => Customer.fromFirestore(d.data()))
          .toList();
      final remoteTransactions = transactionDocs.docs
          .map((d) => TransactionModel.fromFirestore(d.data()))
          .toList();

      if (kDebugMode) {
        debugPrint('[SYNC][$_ts] restoreAll() fetched ${remoteCustomers.length} customers, '
            '${remoteTransactions.length} transactions');
      }

      // SAFETY GUARD: Never overwrite with empty remote data
      if (remoteCustomers.isEmpty && remoteTransactions.isEmpty) {
        if (kDebugMode) debugPrint('[SYNC][$_ts] restoreAll() — remote is empty, keeping local data intact');
        return;
      }

      // ── MULTI-DEVICE MERGE: Per-document last-write-wins ──
      // We do NOT call clearAll(). Instead, we only overwrite local records
      // if the remote version is newer (or the record doesn't exist locally).
      // This preserves locally-created records that haven't synced yet.
      final customersToSave = <Customer>[];
      for (final remote in remoteCustomers) {
        final local = db.customersBox.get(remote.id);
        if (local == null) {
          // New record from cloud — always accept
          customersToSave.add(remote);
        } else {
          // Both exist — compare updatedAt (server-issued timestamps)
          final remoteTime = remote.updatedAt?.millisecondsSinceEpoch ?? 0;
          final localTime = local.updatedAt?.millisecondsSinceEpoch ?? 0;
          if (remoteTime > localTime) {
            customersToSave.add(remote); // Cloud is newer
          }
          // else: local is newer or equal — keep local, skip
        }
      }

      final transactionsToSave = <TransactionModel>[];
      for (final remote in remoteTransactions) {
        final local = db.transactionsBox.get(remote.id);
        if (local == null) {
          transactionsToSave.add(remote);
        } else {
          final remoteTime = remote.updatedAt?.millisecondsSinceEpoch ?? 0;
          final localTime = local.updatedAt?.millisecondsSinceEpoch ?? 0;
          if (remoteTime > localTime) {
            transactionsToSave.add(remote);
          }
        }
      }

      if (kDebugMode) {
        debugPrint('[SYNC][$_ts] Merge result: '
            '${customersToSave.length}/${remoteCustomers.length} customers to update, '
            '${transactionsToSave.length}/${remoteTransactions.length} transactions to update');
      }

      if (customersToSave.isNotEmpty) await db.saveAllCustomers(customersToSave);
      if (transactionsToSave.isNotEmpty) await db.saveAllTransactions(transactionsToSave);

      await db.setLastLocalModifiedAt(DateTime.now().millisecondsSinceEpoch);
      if (kDebugMode) debugPrint('[SYNC][$_ts] restoreAll() COMPLETED successfully');

    } on FirebaseException catch (e, stackTrace) {
      if (kDebugMode) debugPrint('[ERROR][$_ts] restoreAll() FirebaseException: $e');
      if (kDebugMode) debugPrint('[ERROR][$_ts] Stack trace:\n$stackTrace');
      if (_isAuthOrPermissionError(e)) throw FirestorePermissionException();
      rethrow;
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('[ERROR][$_ts] restoreAll() unexpected error: $e');
      if (kDebugMode) debugPrint('[ERROR][$_ts] Stack trace:\n$stackTrace');
      rethrow;
    } finally {
      // ── TOCTOU SAFETY: Clear the flag only after ALL writes are done ──
      await db.setPendingRestore(false);
      db.setRestoringCallback(false);
    }
  }

  // -------------------------------------------------------------------------
  // BACKUP METADATA
  // -------------------------------------------------------------------------

  /// Fetches the backup metadata document (may return null if never backed up).
  Future<Map<String, dynamic>?> getBackupInfo() async {
    debugPrint('[SYNC][$_ts] getBackupInfo() STARTED');
    await _assertConnected();
    final uid = await _getUidWithSessionCheck();
    try {
      final doc = await _withAuthRetry(() => _firestore
          .collection('users').doc(uid)
          .collection('meta').doc('backup_info')
          .get()
          .timeout(const Duration(seconds: 10),
              onTimeout: () => throw FirestoreTimeoutException()));
      final result = doc.exists ? doc.data() : null;
      if (kDebugMode) debugPrint('[SYNC][$_ts] getBackupInfo() ENDED — exists=${doc.exists}, data=$result');
      return result;
    } on TimeoutException {
      if (kDebugMode) debugPrint('[ERROR][$_ts] getBackupInfo() TIMED OUT');
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
        if (op.isDelete) {
          batch.delete(op.ref);
        } else {
          batch.set(op.ref, op.data!);
        }
      }
      await _safeCommit(batch);
    }
  }

  Future<void> _commitIncrementalChunks(
      List<_WriteOp> ops, Box queue, List<dynamic> skippedKeys) async {
    if (skippedKeys.isNotEmpty) {
      await queue.deleteAll(skippedKeys);
    }

    for (int i = 0; i < ops.length; i += _batchLimit) {
      final chunk = ops.sublist(i, (i + _batchLimit).clamp(0, ops.length));
      final batch = _firestore.batch();
      final List<dynamic> successfulQueueKeys = [];

      for (final op in chunk) {
        if (op.isDelete) {
          batch.delete(op.ref);
        } else {
          batch.set(op.ref, op.data!);
        }
        if (op.queueKey != null) {
          successfulQueueKeys.add(op.queueKey);
        }
      }
      await _safeCommit(batch);
      await queue.deleteAll(successfulQueueKeys);
    }
  }

  Future<void> _safeCommit(WriteBatch batch) async {
    const int retries = 3;
    for (int i = 0; i < retries; i++) {
      try {
        await _withAuthRetry(() async {
          await batch.commit().timeout(const Duration(seconds: 60));
        });
        return;
      } on FirebaseException catch (e) {
        if (_isAuthOrPermissionError(e)) throw FirestorePermissionException();
        if (e.code == 'not-found') rethrow;
      } on TimeoutException {
        if (i == retries - 1) throw FirestoreTimeoutException();
        await Future.delayed(const Duration(seconds: 2));
      } catch (e) {
        if (i == retries - 1) rethrow;
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
  final Map<String, dynamic>? data;
  final bool isDelete;
  final dynamic queueKey;
  const _WriteOp({required this.ref, this.data, this.isDelete = false, this.queueKey});
}
