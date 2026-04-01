import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/transaction.dart';
import 'db_provider.dart';
import 'reports_provider.dart';
import 'customer_last_transaction_provider.dart';

// Transaction Service
class TransactionService {
  final Ref ref;

  TransactionService(this.ref);

  Future<void> addTransaction({
    required String customerId,
    required int amountInPaise,
    required bool isGot,
    String? note,
    String? imagePath,
  }) async {
    final transaction = TransactionModel(
      id: const Uuid().v4(),
      customerId: customerId,
      amountInPaise: amountInPaise,
      isGot: isGot,
      note: note ?? '',
      date: DateTime.now(),
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
  }
}

final transactionServiceProvider = Provider<TransactionService>((ref) {
  return TransactionService(ref);
});

final customerTransactionsProvider = Provider.family<List<TransactionModel>, String>((ref, customerId) {
  final db = ref.watch(dbServiceProvider);
  return db.getTransactionsForCustomer(customerId);
});

final customerBalanceProvider = Provider.family<double, String>((ref, customerId) {
  final transactions = ref.watch(customerTransactionsProvider(customerId));
  double balance = 0;
  for (var t in transactions) {
    if (t.isGot) {
      balance -= (t.amountInPaise / 100.0);
    } else {
      balance += (t.amountInPaise / 100.0);
    }
  }
  return balance;
});

final dashboardBalancesProvider = Provider<Map<String, double>>((ref) {
  final db = ref.watch(dbServiceProvider);
  
  double totalToReceive = 0;
  double totalToPay = 0;

  final Map<String, double> balanceByCustomer = {};
  for (final t in db.transactionsBox.values) {
    final delta = t.isGot ? -(t.amountInPaise / 100.0) : (t.amountInPaise / 100.0);
    balanceByCustomer[t.customerId] =
        (balanceByCustomer[t.customerId] ?? 0) + delta;
  }

  for (final customerBalance in balanceByCustomer.values) {
    if (customerBalance > 0) {
      totalToReceive += customerBalance;
    } else if (customerBalance < 0) {
      totalToPay += customerBalance.abs();
    }
  }
  
  return {
    'toReceive': totalToReceive,
    'toPay': totalToPay,
  };
});
