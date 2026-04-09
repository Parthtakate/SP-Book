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

  /// Returns all customers sorted newest-first.
  /// Fix 5: Result is cached and only re-sorted when the box is mutated.
  List<Customer> getAllCustomers() {
    _sortedCustomersCache ??= _customers!.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return _sortedCustomersCache!;
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
    // ── Fix 3: O(1) lookup via index instead of O(n) full-box scan ──────────
    final txnIds = _txnIdsForCustomer(id);

    // Step 2: Write ALL sync queue entries atomically BEFORE Hive deletions.
    // If crash occurs after this write, next sync will still push correct deletes.
    if (!isRestoring) {
      final queueEntries = <String, dynamic>{
        'customer_$id': {'type': 'customer', 'id': id, 'action': 'delete'},
        for (final txnId in txnIds)
          'transaction_$txnId': {'type': 'transaction', 'id': txnId, 'action': 'delete'},
      };
      await _syncQueue!.putAll(queueEntries);
    }

    // Step 3: Delete transactions with best-effort image cleanup
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

    // Step 4: Remove from index and delete customer record
    _indexRemoveCustomer(id); // Fix 3
    _invalidateSortedCache(); // Fix 5
    await _customers!.delete(id);
  }

  // ---------------------------------------------------------------------------
  // Transactions
  // ---------------------------------------------------------------------------

  Box<TransactionModel> get transactionsBox => _transactions!;

  /// Returns all transactions for [customerId], newest-first.
  /// Fix 3: Uses the index for O(1) ID lookup, then fetches by key.
  List<TransactionModel> getTransactionsForCustomer(String customerId) {
    final ids = _txnIdsForCustomer(customerId);
    final result = <TransactionModel>[];
    for (final id in ids) {
      final txn = _transactions!.get(id);
      if (txn != null) result.add(txn);
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

  Future<void> deleteTransaction(String transactionId) async {
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
}
