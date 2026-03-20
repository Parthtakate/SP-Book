import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';
import '../models/customer.dart';
import '../models/transaction.dart';

class DbService {
  static const String _customersBox = 'customers_box';
  static const String _transactionsBox = 'transactions_box_v2';
  
  static Box<Customer>? _customers;
  static Box<TransactionModel>? _transactions;

  Future<void> init() async {
    await Hive.initFlutter();
    
    // Register Adapters
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(CustomerAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(TransactionModelAdapter());

    // Generate or fetch encryption key
    final encryptionCipher = await _getEncryptionCipher();

    // Open boxes
    _customers = await Hive.openBox<Customer>(
      _customersBox, 
      encryptionCipher: encryptionCipher
    );
    _transactions = await Hive.openBox<TransactionModel>(
      _transactionsBox, 
      encryptionCipher: encryptionCipher
    );
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
    return null;
  }

  // --- Customers ---
  Box<Customer> get customersBox => _customers!;
  
  List<Customer> getAllCustomers() {
    return _customers!.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> saveCustomer(Customer customer) async {
    await _customers!.put(customer.id, customer);
  }

  Future<void> deleteCustomer(String id) async {
    await _customers!.delete(id);
    // Also delete associated transactions
    final transactionsToDelete = _transactions!.values.where((t) => t.customerId == id).toList();
    for (var t in transactionsToDelete) {
      await _transactions!.delete(t.id);
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
  }

  Future<void> deleteTransaction(String transactionId) async {
    await _transactions!.delete(transactionId);
  }

  /// Clears ALL local data from both boxes. Called before a full restore.
  Future<void> clearAll() async {
    await _customers!.clear();
    await _transactions!.clear();
  }
}
