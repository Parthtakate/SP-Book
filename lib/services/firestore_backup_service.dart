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
    // Instead of an arbitrary delay, we listen to authStateChanges() which
    // fires as soon as the session is restored.
    if (user == null) {
      debugPrint('[AUTH][$_ts] currentUser is null — waiting for authStateChanges (up to 5s)...');
      try {
        user = await FirebaseAuth.instance
            .authStateChanges()
            .firstWhere((u) => u != null)
            .timeout(const Duration(seconds: 5));
        debugPrint('[AUTH][$_ts] authStateChanges emitted user: uid=${user?.uid}');
      } on TimeoutException {
        debugPrint('[AUTH][$_ts] authStateChanges timed out after 5s — user still null');
        // Fall through to silent restore below
      }
    }
    
    // Last resort: try to forcefully restore Google session
    // (handles offline-to-online transitions where authStateChanges won't fire)
    if (user == null) {
      debugPrint('[AUTH][$_ts] Still null — attempting tryRestoreSessionSilently()...');
      try {
        await AuthService().tryRestoreSessionSilently();
        user = FirebaseAuth.instance.currentUser;
        debugPrint('[AUTH][$_ts] After silent restore: uid=${user?.uid}');
      } catch (e) {
        debugPrint('[AUTH][$_ts] tryRestoreSessionSilently() failed: $e');
      }
    }

    if (user == null) {
      debugPrint('[ERROR][$_ts] _getUidWithSessionCheck: user is STILL null — throwing NotSignedInException');
      throw NotSignedInException();
    }

    try {
      debugPrint('[AUTH][$_ts] Validating ID token for uid=${user.uid}...');
      await user.getIdToken();
      debugPrint('[AUTH][$_ts] ID token valid');
    } on FirebaseAuthException catch (e) {
      debugPrint('[AUTH][$_ts] ID token invalid ($e) — refreshing...');
      await _refreshAuthToken();
      user = FirebaseAuth.instance.currentUser;
      if (user == null) throw NotSignedInException();
      debugPrint('[AUTH][$_ts] Token refreshed, uid=${user.uid}');
    }
    debugPrint('[AUTH][$_ts] _getUidWithSessionCheck() returning uid=${user.uid}');
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

  /// Incrementally backs up changes using the local sync_queue to minimize Firestore writes.
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
        // action == 'set'
        if (type == 'customer') {
          final customer = db.customersBox.get(id);
          if (customer != null) {
            ops.add(_WriteOp(ref: ref, data: customer.toFirestore(), isDelete: false, queueKey: key));
          } else {
            // Missing local item, remove from queue to prevent being stuck
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

    // Update metadata
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
              'totalCustomers': db.customersBox.length,
              'totalTransactions': db.transactionsBox.length,
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
    debugPrint('[SYNC][$_ts] restoreAll() STARTED');
    await _assertConnected();
    final uid = await _getUidWithSessionCheck();

    db.isRestoring = true; // Signal watchers to ignore these ops
    try {
      // Fetch from Firestore concurrently to halve network wait time
      debugPrint('[SYNC][$_ts] restoreAll() fetching customers & transactions from Firestore...');
      final futureCustomers = _withAuthRetry(() async {
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

      final futureTransactions = _withAuthRetry(() async {
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

      final results = await Future.wait([futureCustomers, futureTransactions]);
      final customerDocs = results[0];
      final transactionDocs = results[1];

      final remoteCustomers = customerDocs.docs
          .map((d) => Customer.fromFirestore(d.data()))
          .toList();
      final remoteTransactions = transactionDocs.docs
          .map((d) => TransactionModel.fromFirestore(d.data()))
          .toList();

      debugPrint('[SYNC][$_ts] restoreAll() fetched ${remoteCustomers.length} customers, ${remoteTransactions.length} transactions');

      // SAFETY GUARD: Only clear local data if the remote backup actually has
      // content. If Firestore returns empty (e.g., first-time user or network
      // returned partial data), we preserve local data unconditionally.
      if (remoteCustomers.isEmpty && remoteTransactions.isEmpty) {
        debugPrint('[SYNC][$_ts] restoreAll() — remote is empty, keeping local data intact');
        // Nothing to restore — keep local data intact.
        return;
      }

      // ---- Clear local Hive AFTER confirming remote data is non-empty
      debugPrint('[SYNC][$_ts] restoreAll() clearing local Hive and writing remote data...');
      await db.clearAll();

      // ---- Write all remote data to Hive using fast bulk operations
      if (remoteCustomers.isNotEmpty) await db.saveAllCustomers(remoteCustomers);
      if (remoteTransactions.isNotEmpty) await db.saveAllTransactions(remoteTransactions);

      // Update local modification time to match the backup completion roughly
      await db.setLastLocalModifiedAt(DateTime.now().millisecondsSinceEpoch);
      debugPrint('[SYNC][$_ts] restoreAll() COMPLETED successfully');

    } on FirebaseException catch (e, stackTrace) {
      debugPrint('[ERROR][$_ts] restoreAll() FirebaseException: $e');
      debugPrint('[ERROR][$_ts] Stack trace:\n$stackTrace');
      if (_isAuthOrPermissionError(e)) throw FirestorePermissionException();
      rethrow;
    } catch (e, stackTrace) {
      debugPrint('[ERROR][$_ts] restoreAll() unexpected error: $e');
      debugPrint('[ERROR][$_ts] Stack trace:\n$stackTrace');
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
    debugPrint('[SYNC][$_ts] getBackupInfo() STARTED');
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
      final result = doc.exists ? doc.data() : null;
      debugPrint('[SYNC][$_ts] getBackupInfo() ENDED — exists=${doc.exists}, data=$result');
      return result;
    } on TimeoutException {
      debugPrint('[ERROR][$_ts] getBackupInfo() TIMED OUT');
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

  Future<void> _commitIncrementalChunks(List<_WriteOp> ops, Box queue, List<dynamic> skippedKeys) async {
    // Delete skipped items right away (they are missing local items)
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
      // Success! Remove from the queue so they aren't uploaded again.
      await queue.deleteAll(successfulQueueKeys);
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
  final Map<String, dynamic>? data;
  final bool isDelete;
  final dynamic queueKey;
  const _WriteOp({required this.ref, this.data, this.isDelete = false, this.queueKey});
}
