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
import '../models/khatabook.dart';
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

  // ───────────────────────────────────────────────────────────────────────────
  // Firestore path helpers (nested sub-collection structure)
  // ───────────────────────────────────────────────────────────────────────────

  DocumentReference _bookRef(String uid, String bookId) =>
      _firestore.collection('users').doc(uid)
          .collection('khatabooks').doc(bookId);

  CollectionReference _customersRef(String uid, String bookId) =>
      _bookRef(uid, bookId).collection('customers');

  CollectionReference _transactionsRef(String uid, String bookId) =>
      _bookRef(uid, bookId).collection('transactions');

  DocumentReference _backupInfoRef(String uid, String bookId) =>
      _bookRef(uid, bookId).collection('meta').doc('backup_info');

  // Legacy flat paths — read-only during migration window
  CollectionReference _legacyCustomersRef(String uid) =>
      _firestore.collection('users').doc(uid).collection('customers');

  CollectionReference _legacyTransactionsRef(String uid) =>
      _firestore.collection('users').doc(uid).collection('transactions');

  CollectionReference _legacyMetaRef(String uid) =>
      _firestore.collection('users').doc(uid).collection('meta');

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

  /// Backs up all Khatabooks, customers, and transactions using nested Firestore
  /// sub-collections. Also performs the one-time cleanup of old flat-path docs.
  Future<void> backupAll(DbService db) async {
    await _assertConnected();
    final uid = await _getUidWithSessionCheck();

    final books = db.khatabooksBox.values.toList();
    final allCustomers = db.customersBox.values.toList();    // ALL books
    final allTransactions = db.transactionsBox.values.toList();

    // SAFETY GUARD: Never upload empty data to cloud.
    if (books.isEmpty && allCustomers.isEmpty && allTransactions.isEmpty) {
      if (kDebugMode) debugPrint('[FirestoreBackup] Skipping backup — local data is empty.');
      return;
    }

    final List<_WriteOp> ops = [];

    // 1. Khatabook metadata documents
    for (final book in books) {
      ops.add(_WriteOp(ref: _bookRef(uid, book.id), data: book.toFirestore()));
    }

    // 2. Customers + transactions — grouped under their book's sub-collection
    for (final c in allCustomers) {
      ops.add(_WriteOp(
        ref: _customersRef(uid, c.khatabookId).doc(c.id),
        data: c.toFirestore(),
      ));
    }
    for (final t in allTransactions) {
      ops.add(_WriteOp(
        ref: _transactionsRef(uid, t.khatabookId).doc(t.id),
        data: t.toFirestore(),
      ));
    }

    await _commitInChunks(ops);

    // 3. Write backup_info under each book
    for (final book in books) {
      final bookCustomers =
          allCustomers.where((c) => c.khatabookId == book.id).length;
      final bookTxns =
          allTransactions.where((t) => t.khatabookId == book.id).length;
      await _writeBackupInfoAndStoreServerTime(
          uid, book.id, db, bookCustomers, bookTxns);
    }

    // 4. One-time: clean up old flat-path documents
    if (!db.cloudMigrationDone) {
      await _cleanupOldFlatPaths(uid);
      await db.setCloudMigrationDone(true);
      if (kDebugMode) debugPrint('[FirestoreBackup] Old flat-path cleanup done.');
    }
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
      if (type == 'khatabook') {
        // Khatabook metadata document
        ref = _bookRef(uid, id);
        if (action == 'delete') {
          ops.add(_WriteOp(ref: ref, data: null, isDelete: true, queueKey: key));
        } else {
          final book = db.khatabooksBox.get(id);
          if (book != null) {
            ops.add(_WriteOp(ref: ref, data: book.toFirestore(), queueKey: key));
          } else {
            skippedKeys.add(key);
          }
        }
        continue;
      }

      if (type == 'customer') {
        final customer = db.customersBox.get(id);
        final bookId = customer?.khatabookId ?? 'default';
        ref = _customersRef(uid, bookId).doc(id) as DocumentReference;
        if (action == 'delete') {
          ops.add(_WriteOp(ref: ref, data: null, isDelete: true, queueKey: key));
        } else if (customer != null) {
          ops.add(_WriteOp(ref: ref, data: customer.toFirestore(), queueKey: key));
        } else {
          skippedKeys.add(key);
        }
      } else {
        // transaction
        final txn = db.transactionsBox.get(id);
        final bookId = txn?.khatabookId ?? 'default';
        ref = _transactionsRef(uid, bookId).doc(id) as DocumentReference;
        if (action == 'delete') {
          ops.add(_WriteOp(ref: ref, data: null, isDelete: true, queueKey: key));
        } else if (txn != null) {
          ops.add(_WriteOp(ref: ref, data: txn.toFirestore(), queueKey: key));
        } else {
          skippedKeys.add(key);
        }
      }
    }

    if (ops.isEmpty) {
      if (skippedKeys.isNotEmpty) await queue.deleteAll(skippedKeys);
      return;
    }

    await _commitIncrementalChunks(ops, queue, skippedKeys);

    // Update metadata for the active book
    final activeBookId = db.activeKhatabookId;
    await _writeBackupInfoAndStoreServerTime(
      uid,
      activeBookId,
      db,
      db.customersBox.values.where((c) => c.khatabookId == activeBookId).length,
      db.transactionsBox.values.where((t) => t.khatabookId == activeBookId).length,
    );
  }

  /// Writes backup_info to the nested Firestore path for a specific book,
  /// then reads back the server-issued timestamp and stores it in Hive.
  Future<void> _writeBackupInfoAndStoreServerTime(
    String uid, String bookId, DbService db, int customerCount, int txnCount) async {
    try {
      await _withAuthRetry(() async {
        final docRef = _backupInfoRef(uid, bookId);

        await docRef.set({
          'lastBackupAt': FieldValue.serverTimestamp(),
          'device': Platform.operatingSystem,
          'totalCustomers': customerCount,
          'totalTransactions': txnCount,
        }).timeout(const Duration(seconds: 30),
            onTimeout: () => throw FirestoreTimeoutException());

        // Read back the server-issued timestamp (immune to device clock drift)
        final snapshot = await docRef.get().timeout(const Duration(seconds: 10));
        if (snapshot.exists) {
          final data = snapshot.data() as Map<String, dynamic>?;
          final lastBackupAt = data?['lastBackupAt'];
          if (lastBackupAt is Timestamp) {
            await db.setLastAcknowledgedServerTime(lastBackupAt.millisecondsSinceEpoch);
            if (kDebugMode) {
              debugPrint('[SYNC][$_ts] Stored server timestamp: ${lastBackupAt.millisecondsSinceEpoch}');
            }
          }
        }
      });
    } on TimeoutException {
      throw FirestoreTimeoutException();
    }
  }

  // -------------------------------------------------------------------------
  // RESTORE — with TOCTOU crash safety + multi-device merge + cloud migration
  // -------------------------------------------------------------------------

  /// Restores data from Firestore into Hive.
  ///
  /// **Migration path**: On first run after feature update, checks new nested
  /// paths first. If empty, falls back to old flat-path collections for backward
  /// compatibility and silently migrates all old data to the 'default' book.
  Future<void> restoreAll(DbService db) async {
    debugPrint('[SYNC][$_ts] restoreAll() STARTED');
    await _assertConnected();
    final uid = await _getUidWithSessionCheck();

    await db.setPendingRestore(true);
    db.setRestoringCallback(true);

    try {
      // Fetch Khatabooks metadata (new nested structure)
      if (kDebugMode) debugPrint('[SYNC][$_ts] restoreAll() fetching khatabooks...');
      final booksSnap = await _withAuthRetry(() =>
          _firestore.collection('users').doc(uid).collection('khatabooks')
              .get().timeout(const Duration(seconds: 15),
                  onTimeout: () => throw FirestoreTimeoutException()));

      List<Khatabook> remoteBooks = [];
      List<Customer> remoteCustomers = [];
      List<TransactionModel> remoteTransactions = [];

      final hasNewStructure = booksSnap.docs.isNotEmpty;

      if (!hasNewStructure || !db.cloudMigrationDone) {
        // ── MIGRATION PATH: new paths empty → read from old flat paths ─────────
        if (kDebugMode) debugPrint('[SYNC][$_ts] restoreAll() MIGRATION PATH — reading legacy flat paths...');

        final results = await Future.wait([
          _withAuthRetry(() => _legacyCustomersRef(uid)
              .get().timeout(const Duration(seconds: 15),
                  onTimeout: () => throw FirestoreTimeoutException())),
          _withAuthRetry(() => _legacyTransactionsRef(uid)
              .get().timeout(const Duration(seconds: 15),
                  onTimeout: () => throw FirestoreTimeoutException())),
        ]);

        remoteCustomers = (results[0] as QuerySnapshot).docs
            .map((d) => Customer.fromFirestore(d.data() as Map<String, dynamic>))
            .map((c) => c.copyWith(khatabookId: 'default')) // stamp all as default
            .toList();
        remoteTransactions = (results[1] as QuerySnapshot).docs
            .map((d) => TransactionModel.fromFirestore(d.data() as Map<String, dynamic>))
            .map((t) => t.copyWith(khatabookId: 'default'))
            .toList();

        // Create a default book if there are no books at all
        if (booksSnap.docs.isEmpty) {
          remoteBooks = [
            Khatabook(
              id: 'default',
              name: db.getBusinessName() ?? 'My Business',
              createdAt: DateTime.now(),
            )
          ];
        } else {
          remoteBooks = booksSnap.docs
              .map((d) => Khatabook.fromFirestore(d.data() as Map<String, dynamic>))
              .toList();
        }
      } else {
        // ── NORMAL PATH: read from new nested sub-collections ──────────────────
        if (kDebugMode) debugPrint('[SYNC][$_ts] restoreAll() NORMAL PATH — reading nested sub-collections...');
        remoteBooks = booksSnap.docs
            .map((d) => Khatabook.fromFirestore(d.data() as Map<String, dynamic>))
            .toList();

        // Fetch customers + transactions for all books concurrently
        final futures = remoteBooks.map((book) => Future.wait([
          _withAuthRetry(() => _customersRef(uid, book.id)
              .get().timeout(const Duration(seconds: 15),
                  onTimeout: () => throw FirestoreTimeoutException())),
          _withAuthRetry(() => _transactionsRef(uid, book.id)
              .get().timeout(const Duration(seconds: 15),
                  onTimeout: () => throw FirestoreTimeoutException())),
        ]));
        final allResults = await Future.wait(futures);
        for (final result in allResults) {
          remoteCustomers.addAll((result[0] as QuerySnapshot).docs
              .map((d) => Customer.fromFirestore(d.data() as Map<String, dynamic>)));
          remoteTransactions.addAll((result[1] as QuerySnapshot).docs
              .map((d) => TransactionModel.fromFirestore(d.data() as Map<String, dynamic>)));
        }
      }

      if (kDebugMode) {
        debugPrint('[SYNC][$_ts] restoreAll() fetched '
            '${remoteBooks.length} books, '
            '${remoteCustomers.length} customers, '
            '${remoteTransactions.length} transactions');
      }

      // SAFETY GUARD: Never overwrite with empty remote data
      if (remoteCustomers.isEmpty && remoteTransactions.isEmpty && remoteBooks.isEmpty) {
        if (kDebugMode) debugPrint('[SYNC][$_ts] restoreAll() — remote is empty, keeping local data intact');
        return;
      }

      // ── MULTI-DEVICE MERGE: Per-document last-write-wins ──────────────────

      // Books
      final booksToSave = <Khatabook>[];
      for (final remote in remoteBooks) {
        final local = db.khatabooksBox.get(remote.id);
        if (local == null) {
          booksToSave.add(remote);
        } else {
          final remoteTime = remote.updatedAt?.millisecondsSinceEpoch ?? 0;
          final localTime = local.updatedAt?.millisecondsSinceEpoch ?? 0;
          if (remoteTime > localTime) booksToSave.add(remote);
        }
      }

      // Customers
      final customersToSave = <Customer>[];
      for (final remote in remoteCustomers) {
        final local = db.customersBox.get(remote.id);
        if (local == null) {
          customersToSave.add(remote);
        } else {
          final remoteTime = remote.updatedAt?.millisecondsSinceEpoch ?? 0;
          final localTime = local.updatedAt?.millisecondsSinceEpoch ?? 0;
          if (remoteTime > localTime) customersToSave.add(remote);
        }
      }

      // Transactions
      final transactionsToSave = <TransactionModel>[];
      for (final remote in remoteTransactions) {
        final local = db.transactionsBox.get(remote.id);
        if (local == null) {
          transactionsToSave.add(remote);
        } else {
          final remoteTime = remote.updatedAt?.millisecondsSinceEpoch ?? 0;
          final localTime = local.updatedAt?.millisecondsSinceEpoch ?? 0;
          if (remoteTime > localTime) transactionsToSave.add(remote);
        }
      }

      if (kDebugMode) {
        debugPrint('[SYNC][$_ts] Merge result: '
            '${booksToSave.length}/${remoteBooks.length} books, '
            '${customersToSave.length}/${remoteCustomers.length} customers, '
            '${transactionsToSave.length}/${remoteTransactions.length} transactions to update');
      }

      if (booksToSave.isNotEmpty) {
        await db.khatabooksBox.putAll(
          {for (final b in booksToSave) b.id: b},
        );
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
      await db.setPendingRestore(false);
      db.setRestoringCallback(false);
    }
  }

  /// Permanently removes old flat-path Firestore documents (customers, transactions, meta).
  /// Called once after the first successful backupAll() to complete the cloud migration.
  Future<void> _cleanupOldFlatPaths(String uid) async {
    if (kDebugMode) debugPrint('[FirestoreBackup] Cleaning up legacy flat-path documents...');
    try {
      final results = await Future.wait([
        _legacyCustomersRef(uid).get(),
        _legacyTransactionsRef(uid).get(),
        _legacyMetaRef(uid).get(),
      ]);
      final ops = <_WriteOp>[
        for (final snap in results)
          for (final d in (snap as QuerySnapshot).docs)
            _WriteOp(ref: d.reference, data: null, isDelete: true),
      ];
      if (ops.isNotEmpty) await _commitInChunks(ops);
      if (kDebugMode) {
        debugPrint('[FirestoreBackup] Removed ${ops.length} legacy flat-path documents.');
      }
    } catch (e) {
      // Non-fatal: cleanup failure should not block backup
      if (kDebugMode) debugPrint('[FirestoreBackup] _cleanupOldFlatPaths() failed (non-fatal): $e');
    }
  }

  // -------------------------------------------------------------------------
  // BACKUP METADATA
  // -------------------------------------------------------------------------

  /// Fetches the backup metadata doc. Tries new nested path first, falls back
  /// to legacy flat path during the migration window.
  Future<Map<String, dynamic>?> getBackupInfo({String bookId = 'default'}) async {
    debugPrint('[SYNC][$_ts] getBackupInfo() STARTED');
    await _assertConnected();
    final uid = await _getUidWithSessionCheck();
    try {
      // Try new nested path
      final newDoc = await _withAuthRetry(() =>
          _backupInfoRef(uid, bookId)
              .get()
              .timeout(const Duration(seconds: 10),
                  onTimeout: () => throw FirestoreTimeoutException()));
      if (newDoc.exists) {
        final result = newDoc.data() as Map<String, dynamic>?;
        if (kDebugMode) debugPrint('[SYNC][$_ts] getBackupInfo() ENDED — new path, data=$result');
        return result;
      }

      // Fall back to legacy flat path
      final oldDoc = await _withAuthRetry(() =>
          _legacyMetaRef(uid).doc('backup_info')
              .get()
              .timeout(const Duration(seconds: 10),
                  onTimeout: () => throw FirestoreTimeoutException()));
      final result = oldDoc.exists ? oldDoc.data() as Map<String, dynamic>? : null;
      if (kDebugMode) debugPrint('[SYNC][$_ts] getBackupInfo() ENDED — legacy path, data=$result');
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
