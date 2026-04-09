import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';
import '../models/customer.dart';
import '../models/transaction.dart';

class DbService {
  static const String _customersBox   = 'customers';
  static const String _transactionsBox = 'transactions';
  static const String _settingsBox    = 'settings';
  static const String _syncQueueBoxStr = 'sync_queue';

  // ── Fix 4: instance fields (was static) ────────────────────────────────────
  Box<Customer>?       _customers;
  Box<TransactionModel>? _transactions;
  Box?                 _settings;
  Box?                 _syncQueue;

  Box get syncQueue => _syncQueue!;

  // ── isRestoring: injected callback so DbService never imports Riverpod ──
  // The AutoSyncNotifier injects a getter here at startup.
  bool Function() _isRestoringCallback = () => false;

  /// Returns true while a restore operation is actively writing to Hive.
  /// Prevents the box watchers from triggering backup during a restore.
  bool get isRestoring => _isRestoringCallback();

  /// Called by AutoSyncNotifier to wire up the isRestoring check.
  void setRestoringCallback(bool value) {
    // The callback is replaced by a simple flag for cases where we set it directly
    // (e.g., from FirestoreBackupService before AutoSyncNotifier is ready).
    _directRestoringFlag = value;
    _isRestoringCallback = () => _directRestoringFlag;
  }

  /// Internal flag for cases where the callback hasn't been injected yet.
  bool _directRestoringFlag = false;

  /// Injects the Riverpod-aware isRestoring getter (called from AutoSyncNotifier)
  void injectRestoringCallback(bool Function() callback) {
    _isRestoringCallback = callback;
  }

  // ── Fix 3: in-memory customer→[txnId] index ───────────────────────────────
  // Built once during init(), updated on every write/delete.
  // Turns deleteCustomer's O(n) full-box scan into O(1).
  final Map<String, List<String>> _txnIndex = {};

  void _indexAddTxn(String customerId, String txnId) {
    _txnIndex.putIfAbsent(customerId, () => []).add(txnId);
  }

  void _indexRemoveTxn(String customerId, String txnId) {
    _txnIndex[customerId]?.remove(txnId);
  }

  void _indexRemoveCustomer(String customerId) {
    _txnIndex.remove(customerId);
  }

  /// Returns transaction IDs for a customer from the index (O(1)).
  List<String> _txnIdsForCustomer(String customerId) =>
      List<String>.from(_txnIndex[customerId] ?? const []);

  // ── Fix 5: sorted-customer cache ──────────────────────────────────────────
  List<Customer>? _sortedCustomersCache;

  void _invalidateSortedCache() => _sortedCustomersCache = null;

  Future<void> init() async {
    await Hive.initFlutter();

    // Generate or fetch encryption key — with recovery on key loss
    final encryptionCipher = await _getEncryptionCipher();

    // Register Adapters
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(CustomerAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TransactionModelAdapter());

    // Open boxes
    if (encryptionCipher != null) {
      _customers = await Hive.openBox<Customer>(
        _customersBox,
        encryptionCipher: encryptionCipher,
      );
      _transactions = await Hive.openBox<TransactionModel>(
        _transactionsBox,
        encryptionCipher: encryptionCipher,
      );
    } else {
      // ── Fix 6: Fallback — open unencrypted after key loss ──
      // Data from this session will be unreadable from old encrypted files,
      // so we delete the corrupted boxes and open fresh ones.
      debugPrint('[DbService] Encryption key lost — opening fresh unencrypted boxes');
      try {
        await Hive.deleteBoxFromDisk(_customersBox);
        await Hive.deleteBoxFromDisk(_transactionsBox);
      } catch (_) {}
      _customers     = await Hive.openBox<Customer>(_customersBox);
      _transactions  = await Hive.openBox<TransactionModel>(_transactionsBox);
    }

    // Settings & sync queue (unencrypted — stores simple flags)
    _settings  = await Hive.openBox(_settingsBox);
    _syncQueue = await Hive.openBox(_syncQueueBoxStr);

    // ── Fix 3: build the transaction index from the loaded box ──────────────
    for (final txn in _transactions!.values) {
      _indexAddTxn(txn.customerId, txn.id);
    }
  }

  /// Returns a [HiveCipher] or null if the key was lost (encrypted storage wiped).
  ///
  /// Fix 6: Instead of throwing a hard [StateError], we log the key-loss event
  /// and return null so the app can open unencrypted boxes and then trigger
  /// a cloud restore to re-populate data.
  Future<HiveCipher?> _getEncryptionCipher() async {
    const secureStorage = FlutterSecureStorage();
    try {
      final containsEncryptionKey = await secureStorage.containsKey(key: 'hive_key');
      if (!containsEncryptionKey) {
        // First install — generate and store a new key
        final key = Hive.generateSecureKey();
        await secureStorage.write(
          key: 'hive_key',
          value: base64UrlEncode(key),
        );
      }

      final keyString = await secureStorage.read(key: 'hive_key');
      if (keyString != null) {
        final encryptionKeyUint8List = base64Url.decode(keyString);
        return HiveAesCipher(encryptionKeyUint8List);
      }

      // Key was written but can't be read back (very unusual)
      debugPrint('[DbService] WARNING: Hive encryption key written but unreadable.');
      return null;
    } catch (e, stack) {
      // Key loss can happen if the device is factory reset with app still installed,
      // or on some Android devices that wipe Keystore on account changes.
      debugPrint('[DbService] Encryption key retrieval failed: $e\n$stack');
      // Signal that we need a cloud restore
      _encryptionKeyLost = true;
      return null;
    }
  }

  /// True if the Hive encryption key was lost on this startup.
  /// AutoSyncNotifier reads this to trigger an immediate restoreAll().
  bool _encryptionKeyLost = false;
  bool get encryptionKeyLost => _encryptionKeyLost;

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  bool get hasCompletedOnboarding =>
      _settings?.get('hasCompletedOnboarding', defaultValue: false) ?? false;

  Future<void> setOnboardingCompleted(bool value) async {
    await _settings?.put('hasCompletedOnboarding', value);
  }

  bool get isLoggedIn =>
      _settings?.get('isLoggedIn', defaultValue: false) ?? false;

  Future<void> setLoggedIn(bool value) async {
    await _settings?.put('isLoggedIn', value);
  }

  String? getBusinessName() => _settings?.get('businessName') as String?;

  Future<void> setBusinessName(String name) async {
    await _settings?.put('businessName', name);
  }

  /// The device-local modification timestamp (milliseconds since epoch).
  /// Used as a coarse "is local newer?" signal.
  int get lastLocalModifiedAt =>
      _settings?.get('lastLocalModifiedAt', defaultValue: 0) as int;

  Future<void> setLastLocalModifiedAt(int timestamp) async {
    await _settings?.put('lastLocalModifiedAt', timestamp);
  }

  /// The last Firestore-server-issued timestamp we stored after a successful backup.
  /// Used for clock-safe conflict resolution instead of device clock.
  int get lastAcknowledgedServerTime =>
      _settings?.get('lastAcknowledgedServerTime', defaultValue: 0) as int;

  Future<void> setLastAcknowledgedServerTime(int serverTimestampMs) async {
    await _settings?.put('lastAcknowledgedServerTime', serverTimestampMs);
  }

  // ---------------------------------------------------------------------------
  // TOCTOU crash-safety flag
  // ---------------------------------------------------------------------------

  /// True if a restoreAll() was started but not yet completed.
  /// main() reads this on startup and re-runs restoreAll() if true.
  bool get pendingRestore =>
      _settings?.get('pendingRestore', defaultValue: false) ?? false;

  Future<void> setPendingRestore(bool value) async {
    await _settings?.put('pendingRestore', value);
  }

  // ---------------------------------------------------------------------------
  // Customers
  // ---------------------------------------------------------------------------

  Box<Customer> get customersBox => _customers!;

  /// Returns all active (non-deleted) customers sorted newest-first.
  /// Fix 5: Result is cached and only re-sorted when the box is mutated.
  List<Customer> getAllCustomers() {
    _sortedCustomersCache ??= _customers!.values
        .where((c) => !c.isDeleted)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return _sortedCustomersCache!;
  }

  /// Returns all soft-deleted customers for the Recycle Bin.
  List<Customer> getDeletedCustomers() {
    return _customers!.values
        .where((c) => c.isDeleted)
        .toList()
      ..sort((a, b) => (b.updatedAt ?? b.createdAt).compareTo(a.updatedAt ?? a.createdAt));
  }

  /// Returns all soft-deleted transactions for the Recycle Bin.
  List<TransactionModel> getDeletedTransactions() {
    return _transactions!.values
        .where((t) => t.isDeleted)
        .toList()
      ..sort((a, b) => (b.updatedAt ?? b.date).compareTo(a.updatedAt ?? a.date));
  }

  /// Restores a soft-deleted customer (sets isDeleted=false).
  Future<void> restoreCustomer(String id) async {
    final customer = _customers!.get(id);
    if (customer == null) return;
    final restored = customer.copyWith(isDeleted: false, updatedAt: DateTime.now());
    await _customers!.put(id, restored);
    _invalidateSortedCache();
    if (!isRestoring) {
      await _syncQueue!.put(
        'customer_$id',
        {'type': 'customer', 'id': id, 'action': 'set'},
      );
    }
  }

  /// Restores a soft-deleted transaction (sets isDeleted=false).
  Future<void> restoreTransaction(String transactionId) async {
    final txn = _transactions!.get(transactionId);
    if (txn == null) return;
    final restored = txn.copyWith(isDeleted: false, updatedAt: DateTime.now());
    await _transactions!.put(transactionId, restored);
    if (!isRestoring) {
      await _syncQueue!.put(
        'transaction_$transactionId',
        {'type': 'transaction', 'id': transactionId, 'action': 'set'},
      );
    }
  }

  Future<void> saveCustomer(Customer customer) async {
    await _customers!.put(customer.id, customer);
    _invalidateSortedCache(); // Fix 5
    if (!isRestoring) {
      await _syncQueue!.put(
        'customer_${customer.id}',
        {'type': 'customer', 'id': customer.id, 'action': 'set'},
      );
    }
  }

  Future<void> saveAllCustomers(List<Customer> customers) async {
    final map = {for (var c in customers) c.id: c};
    await _customers!.putAll(map);
    _invalidateSortedCache(); // Fix 5
    // Note: saveAll is primarily used during restore, sync queue is intentionally skipped.
  }

  Future<void> deleteCustomer(String id) async {
    // ── Phase 4: Soft Delete — mark as isDeleted instead of destroying the record ──
    final customer = _customers!.get(id);
    if (customer == null) return;

    final softDeleted = customer.copyWith(
      isDeleted: true,
      updatedAt: DateTime.now(),
    );
    await _customers!.put(id, softDeleted);
    _invalidateSortedCache(); // Fix 5

    // Soft-delete all child transactions too
    final txnIds = _txnIdsForCustomer(id);
    for (final txnId in txnIds) {
      final txn = _transactions!.get(txnId);
      if (txn != null && !txn.isDeleted) {
        final softDeletedTxn = txn.copyWith(
          isDeleted: true,
          updatedAt: DateTime.now(),
        );
        await _transactions!.put(txnId, softDeletedTxn);
      }
    }

    // Push 'set' (not 'delete') so Firestore receives the isDeleted=true record
    if (!isRestoring) {
      final queueEntries = <String, dynamic>{
        'customer_$id': {'type': 'customer', 'id': id, 'action': 'set'},
        for (final txnId in txnIds)
          'transaction_$txnId': {'type': 'transaction', 'id': txnId, 'action': 'set'},
      };
      await _syncQueue!.putAll(queueEntries);
    }
  }

  /// Permanently removes a customer and their transactions from Hive + queues hard-delete.
  /// Only called from the Recycle Bin screen.
  Future<void> permanentlyDeleteCustomer(String id) async {
    final txnIds = _txnIdsForCustomer(id);

    // Best-effort image cleanup
    for (final txnId in txnIds) {
      final txn = _transactions!.get(txnId);
      if (txn?.imagePath != null) {
        try {
          final file = File(txn!.imagePath!);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
    await _transactions!.deleteAll(txnIds);
    _indexRemoveCustomer(id); // Fix 3
    _invalidateSortedCache(); // Fix 5
    await _customers!.delete(id);

    // Hard-delete sync
    if (!isRestoring) {
      final queueEntries = <String, dynamic>{
        'customer_$id': {'type': 'customer', 'id': id, 'action': 'delete'},
        for (final txnId in txnIds)
          'transaction_$txnId': {'type': 'transaction', 'id': txnId, 'action': 'delete'},
      };
      await _syncQueue!.putAll(queueEntries);
    }
  }

  // ---------------------------------------------------------------------------
  // Transactions
  // ---------------------------------------------------------------------------

  Box<TransactionModel> get transactionsBox => _transactions!;

  /// Returns all active (non-deleted) transactions for [customerId], newest-first.
  /// Fix 3: Uses the index for O(1) ID lookup, then fetches by key.
  List<TransactionModel> getTransactionsForCustomer(String customerId) {
    final ids = _txnIdsForCustomer(customerId);
    final result = <TransactionModel>[];
    for (final id in ids) {
      final txn = _transactions!.get(id);
      // Phase 4: filter out soft-deleted transactions from the active view
      if (txn != null && !txn.isDeleted) result.add(txn);
    }
    result.sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  Future<void> saveTransaction(TransactionModel transaction) async {
    final isNew = !_transactions!.containsKey(transaction.id);
    await _transactions!.put(transaction.id, transaction);
    // Fix 3: only add to index if this is a new transaction
    if (isNew) _indexAddTxn(transaction.customerId, transaction.id);
    if (!isRestoring) {
      await _syncQueue!.put(
        'transaction_${transaction.id}',
        {'type': 'transaction', 'id': transaction.id, 'action': 'set'},
      );
    }
  }

  Future<void> saveAllTransactions(List<TransactionModel> transactions) async {
    final map = {for (var t in transactions) t.id: t};
    await _transactions!.putAll(map);
    // Fix 3: update index for all restored transactions
    for (final t in transactions) {
      if (!(_txnIndex[t.customerId]?.contains(t.id) ?? false)) {
        _indexAddTxn(t.customerId, t.id);
      }
    }
  }

  /// Soft-deletes a single transaction (marks isDeleted=true).
  Future<void> deleteTransaction(String transactionId) async {
    final txn = _transactions!.get(transactionId);
    if (txn == null) return;
    // Phase 4: Soft delete — keep in Hive but hide from active views
    final softDeleted = txn.copyWith(isDeleted: true, updatedAt: DateTime.now());
    await _transactions!.put(transactionId, softDeleted);
    // NOTE: intentionally NOT removing from _txnIndex — the record still exists
    // and may be restored. The active query filters it out via isDeleted check.
    if (!isRestoring) {
      await _syncQueue!.put(
        'transaction_$transactionId',
        {'type': 'transaction', 'id': transactionId, 'action': 'set'},
      );
    }
  }

  /// Permanently removes a single transaction from Hive. Only for the Recycle Bin.
  Future<void> permanentlyDeleteTransaction(String transactionId) async {
    final txn = _transactions!.get(transactionId);
    if (txn?.imagePath != null) {
      try {
        final file = File(txn!.imagePath!);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    if (txn != null) _indexRemoveTxn(txn.customerId, transactionId); // Fix 3
    await _transactions!.delete(transactionId);
    if (!isRestoring) {
      await _syncQueue!.put(
        'transaction_$transactionId',
        {'type': 'transaction', 'id': transactionId, 'action': 'delete'},
      );
    }
  }

  /// Clears ALL local data from both boxes. Called before a full restore.
  Future<void> clearAll() async {
    final txns = _transactions?.values.toList() ?? const [];
    for (final t in txns) {
      final imagePath = t.imagePath;
      if (imagePath == null || imagePath.isEmpty) continue;
      try {
        final file = File(imagePath);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    await _customers!.clear();
    await _transactions!.clear();
    await _syncQueue!.clear();
    _txnIndex.clear();          // Fix 3: reset index
    _invalidateSortedCache();   // Fix 5: invalidate cache
  }

  // ---------------------------------------------------------------------------
  // P2: Auto-purge items that have been in the Recycle Bin for > 30 days.
  // Called once on startup (after init) to keep Hive and Firestore clean.
  // ---------------------------------------------------------------------------

  /// Permanently removes soft-deleted records older than [retentionDays] days.
  /// Queues hard-delete sync actions so Firestore is cleaned up too.
  Future<int> autopurgeDeletedItems({int retentionDays = 30}) async {
    final cutoff = DateTime.now().subtract(Duration(days: retentionDays));
    int purgedCount = 0;

    // --- Customers ---
    final expiredCustomers = _customers!.values
        .where((c) => c.isDeleted && (c.updatedAt?.isBefore(cutoff) ?? false))
        .toList();

    for (final c in expiredCustomers) {
      final txnIds = _txnIdsForCustomer(c.id);
      // Hard-delete child transactions
      for (final txnId in txnIds) {
        final txn = _transactions!.get(txnId);
        if (txn?.imagePath != null) {
          try {
            final file = File(txn!.imagePath!);
            if (await file.exists()) await file.delete();
          } catch (_) {}
        }
      }
      await _transactions!.deleteAll(txnIds);
      _indexRemoveCustomer(c.id);
      await _customers!.delete(c.id);

      // Queue hard-delete sync for each purged record
      if (!isRestoring) {
        final queueEntries = <String, dynamic>{
          'customer_${c.id}': {'type': 'customer', 'id': c.id, 'action': 'delete'},
          for (final txnId in txnIds)
            'transaction_$txnId': {'type': 'transaction', 'id': txnId, 'action': 'delete'},
        };
        await _syncQueue!.putAll(queueEntries);
      }
      purgedCount++;
    }

    // --- Orphan transactions (soft-deleted but customer still active / no parent) ---
    final expiredTxns = _transactions!.values
        .where((t) => t.isDeleted && (t.updatedAt?.isBefore(cutoff) ?? false))
        .toList();

    for (final t in expiredTxns) {
      if (t.imagePath != null) {
        try {
          final file = File(t.imagePath!);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      _indexRemoveTxn(t.customerId, t.id);
      await _transactions!.delete(t.id);
      if (!isRestoring) {
        await _syncQueue!.put(
          'transaction_${t.id}',
          {'type': 'transaction', 'id': t.id, 'action': 'delete'},
        );
      }
      purgedCount++;
    }

    if (purgedCount > 0) {
      _invalidateSortedCache();
      debugPrint('[DbService] autopurge: permanently removed $purgedCount items older than $retentionDays days.');
    }
    return purgedCount;
  }
}
