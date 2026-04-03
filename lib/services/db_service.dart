import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';
import '../models/customer.dart';
import '../models/transaction.dart';
class DbService {
  static const String _customersBox = 'customers';
  static const String _transactionsBox = 'transactions';
  static const String _settingsBox = 'settings';
  static const String _syncQueueBoxStr = 'sync_queue';
  
  static Box<Customer>? _customers;
  static Box<TransactionModel>? _transactions;
  static Box? _settings;
  static Box? _syncQueue;

  Box get syncQueue => _syncQueue!;

  /// Flag to indicate when a restore operation is actively modifying Hive,
  /// so that we can ignore these changes in our auto-sync watcher.
  bool isRestoring = false;

  Future<void> init() async {
    await Hive.initFlutter();
    
    // Generate or fetch encryption key
    final encryptionCipher = await _getEncryptionCipher();

    // Register Adapters
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(CustomerAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TransactionModelAdapter());

    // Open boxes
    _customers = await Hive.openBox<Customer>(
      _customersBox, 
      encryptionCipher: encryptionCipher
    );
    _transactions = await Hive.openBox<TransactionModel>(
      _transactionsBox, 
      encryptionCipher: encryptionCipher
    );

    // Settings box (unencrypted — stores simple flags)
    _settings = await Hive.openBox(_settingsBox);
    _syncQueue = await Hive.openBox(_syncQueueBoxStr);
  }

  Future<HiveCipher?> _getEncryptionCipher() async {
    const secureStorage = FlutterSecureStorage();
    final containsEncryptionKey = await secureStorage.containsKey(key: 'hive_key');
    if (!containsEncryptionKey) {
      final key = Hive.generateSecureKey();
      await secureStorage.write(
        key: 'hive_key', 
        value: base64UrlEncode(key)
      );
    }
    
    final keyString = await secureStorage.read(key: 'hive_key');
    if (keyString != null) {
      final encryptionKeyUint8List = base64Url.decode(keyString);
      return HiveAesCipher(encryptionKeyUint8List);
    }
    // If we reach here, secure storage didn't contain the expected key.
    // Failing closed prevents unencrypted local data from being stored.
    throw StateError('Missing Hive encryption key in secure storage.');
  }

  // --- Settings ---
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

  int get lastLocalModifiedAt =>
      _settings?.get('lastLocalModifiedAt', defaultValue: 0) as int;

  Future<void> setLastLocalModifiedAt(int timestamp) async {
    await _settings?.put('lastLocalModifiedAt', timestamp);
  }

  // --- Customers ---
  Box<Customer> get customersBox => _customers!;
  
  List<Customer> getAllCustomers() {
    return _customers!.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> saveCustomer(Customer customer) async {
    await _customers!.put(customer.id, customer);
    if (!isRestoring) {
      await _syncQueue!.put('customer_${customer.id}', {'type': 'customer', 'id': customer.id, 'action': 'set'});
    }
  }

  Future<void> deleteCustomer(String id) async {
    await _customers!.delete(id);
    if (!isRestoring) {
      await _syncQueue!.put('customer_$id', {'type': 'customer', 'id': id, 'action': 'delete'});
    }
    // Also delete associated transactions
    final transactionsToDelete = _transactions!.values.where((t) => t.customerId == id).toList();
    for (var t in transactionsToDelete) {
      await _transactions!.delete(t.id);
      if (!isRestoring) {
        await _syncQueue!.put('transaction_${t.id}', {'type': 'transaction', 'id': t.id, 'action': 'delete'});
      }
    }
  }

  // --- Transactions ---
  Box<TransactionModel> get transactionsBox => _transactions!;

  List<TransactionModel> getTransactionsForCustomer(String customerId) {
    return _transactions!.values
      .where((t) => t.customerId == customerId)
      .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<void> saveTransaction(TransactionModel transaction) async {
    await _transactions!.put(transaction.id, transaction);
    if (!isRestoring) {
      await _syncQueue!.put('transaction_${transaction.id}', {'type': 'transaction', 'id': transaction.id, 'action': 'set'});
    }
  }

  Future<void> deleteTransaction(String transactionId) async {
    final txn = _transactions!.get(transactionId);
    if (txn?.imagePath != null) {
      final file = File(txn!.imagePath!);
      if (await file.exists()) await file.delete();
    }
    await _transactions!.delete(transactionId);
    if (!isRestoring) {
      await _syncQueue!.put('transaction_$transactionId', {'type': 'transaction', 'id': transactionId, 'action': 'delete'});
    }
  }

  /// Clears ALL local data from both boxes. Called before a full restore.
  Future<void> clearAll() async {
    // Delete any locally stored transaction images referenced by Hive.
    final txns = _transactions?.values.toList() ?? const [];
    for (final t in txns) {
      final imagePath = t.imagePath;
      if (imagePath == null || imagePath.isEmpty) continue;
      try {
        final file = File(imagePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Best-effort cleanup: ignore failures.
      }
    }
    await _customers!.clear();
    await _transactions!.clear();
    await _syncQueue!.clear();
  }
}
