import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/transaction.dart';
import 'db_provider.dart';
import 'reports_provider.dart';
import 'customer_last_transaction_provider.dart';

// ---------------------------------------------------------------------------
// Transaction Service
// ---------------------------------------------------------------------------

class TransactionService {
  final Ref ref;

  TransactionService(this.ref);

  Future<void> addTransaction({
    required String customerId,
    required int amountInPaise,
    required bool isGot,
    String? note,
    String? imagePath,
    DateTime? date, // Phase 4: allow back-dating
  }) async {
    final transaction = TransactionModel(
      id: const Uuid().v4(),
      customerId: customerId,
      amountInPaise: amountInPaise,
      isGot: isGot,
      note: note ?? '',
      date: date ?? DateTime.now(), // use provided date or default to now
      imagePath: imagePath,
    );
    await ref.read(dbServiceProvider).saveTransaction(transaction);
    _refresh(customerId);
  }

  Future<void> deleteTransaction(String transactionId, String customerId) async {
    await ref.read(dbServiceProvider).deleteTransaction(transactionId);
    _refresh(customerId);
  }

  Future<void> updateTransaction(TransactionModel updatedTransaction) async {
    await ref.read(dbServiceProvider).saveTransaction(updatedTransaction);
    _refresh(updatedTransaction.customerId);
  }

  void _refresh(String customerId) {
    ref.invalidate(customerTransactionsProvider(customerId));
    ref.invalidate(customerBalanceProvider(customerId));
    ref.invalidate(customerLastTransactionProvider(customerId));
    ref.invalidate(dashboardBalancesProvider);
    ref.invalidate(accountStatementProvider);
    ref.invalidate(customerBalanceMapProvider);
  }
}

final transactionServiceProvider = Provider<TransactionService>((ref) {
  return TransactionService(ref);
});

// ---------------------------------------------------------------------------
// Per-customer transactions
// ---------------------------------------------------------------------------

final customerTransactionsProvider =
    Provider.autoDispose.family<List<TransactionModel>, String>((ref, customerId) {
  final db = ref.watch(dbServiceProvider);
  return db.getTransactionsForCustomer(customerId);
});

// ---------------------------------------------------------------------------
// Per-customer balance in PAISE (int) — avoids floating-point drift on money.
// Positive = customer owes you. Negative = you owe them.
// IMPORTANT: Divide by 100.0 only at display layer (format/PDF calls).
// ---------------------------------------------------------------------------

final customerBalanceProvider =
    Provider.autoDispose.family<int, String>((ref, customerId) {
  final transactions = ref.watch(customerTransactionsProvider(customerId));
  int balance = 0;
  for (final t in transactions) {
    // isGot == true  → customer gave you money → reduces what they owe → negative
    // isGot == false → you gave customer money → increases what they owe → positive
    balance += t.isGot ? -t.amountInPaise : t.amountInPaise;
  }
  return balance;
});

// ---------------------------------------------------------------------------
// Global balance map in PAISE (int) — used for filtering & settlement guard
// ---------------------------------------------------------------------------

/// Returns `Map<customerId, netBalanceInPaise>`.
/// Positive = customer owes you. Negative = you owe them.
/// Kept as [int] to avoid floating-point rounding on financial data.
/// Invalidated explicitly in TransactionService._refresh().
final customerBalanceMapProvider = Provider<Map<String, int>>((ref) {
  final db = ref.watch(dbServiceProvider);
  final Map<String, int> map = {};
  for (final t in db.transactionsBox.values) {
    final delta = t.isGot ? -t.amountInPaise : t.amountInPaise;
    map[t.customerId] = (map[t.customerId] ?? 0) + delta;
  }
  return map;
});

// ---------------------------------------------------------------------------
// Dashboard totals
// ---------------------------------------------------------------------------

final dashboardBalancesProvider = Provider<Map<String, double>>((ref) {
  final balanceMap = ref.watch(customerBalanceMapProvider);

  int totalToReceivePaise = 0;
  int totalToPayPaise = 0;

  for (final balancePaise in balanceMap.values) {
    if (balancePaise > 0) {
      totalToReceivePaise += balancePaise;
    } else if (balancePaise < 0) {
      totalToPayPaise += balancePaise.abs();
    }
  }

  return {
    'toReceive': totalToReceivePaise / 100.0,
    'toPay': totalToPayPaise / 100.0,
  };
});
