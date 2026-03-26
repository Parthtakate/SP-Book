import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/transaction.dart';
import 'db_provider.dart';
import '../services/firestore_sync_service.dart';

final anyTransactionChangeProvider = NotifierProvider<AnyTransactionChangeNotifier, int>(() {
  return AnyTransactionChangeNotifier();
});

class AnyTransactionChangeNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void notifyChanged() {
    state++;
  }
}

// Transaction Service
class TransactionService {
  final Ref ref;

  TransactionService(this.ref);

  Future<void> addTransaction({
    required String customerId,
    required double amount,
    required bool isGot,
    String? note,
    String? imagePath,
  }) async {
    final transaction = TransactionModel(
      id: const Uuid().v4(),
      customerId: customerId,
      amount: amount,
      isGot: isGot,
      note: note ?? '',
      date: DateTime.now(),
      imagePath: imagePath,
    );
    await ref.read(dbServiceProvider).saveTransaction(transaction);

    // Incremental cloud sync: keeps transactions up to date.
    await ref
        .read(firestoreSyncServiceProvider)
        .syncTransactionUpsert(transaction);

    ref.read(anyTransactionChangeProvider.notifier).notifyChanged();
  }

  Future<void> deleteTransaction(String transactionId) async {
    await ref.read(dbServiceProvider).deleteTransaction(transactionId);

    await ref
        .read(firestoreSyncServiceProvider)
        .syncTransactionDelete(transactionId);

    ref.read(anyTransactionChangeProvider.notifier).notifyChanged();
  }

  Future<void> updateTransaction(TransactionModel updatedTransaction) async {
    await ref.read(dbServiceProvider).saveTransaction(updatedTransaction);

    await ref
        .read(firestoreSyncServiceProvider)
        .syncTransactionUpsert(updatedTransaction);

    ref.read(anyTransactionChangeProvider.notifier).notifyChanged();
  }
}

final transactionServiceProvider = Provider<TransactionService>((ref) {
  return TransactionService(ref);
});

final customerTransactionsProvider = Provider.family<List<TransactionModel>, String>((ref, customerId) {
  ref.watch(anyTransactionChangeProvider);
  final db = ref.watch(dbServiceProvider);
  return db.getTransactionsForCustomer(customerId);
});

final customerBalanceProvider = Provider.family<double, String>((ref, customerId) {
  final transactions = ref.watch(customerTransactionsProvider(customerId));
  double balance = 0;
  for (var t in transactions) {
    if (t.isGot) {
      balance -= t.amount;
    } else {
      balance += t.amount;
    }
  }
  return balance;
});

final dashboardBalancesProvider = Provider<Map<String, double>>((ref) {
  ref.watch(anyTransactionChangeProvider);
  final db = ref.watch(dbServiceProvider);
  
  double totalToReceive = 0;
  double totalToPay = 0;

  // Avoid N x "getTransactionsForCustomer" scans (slow on large datasets).
  // Instead, compute each customer's balance in one pass over all transactions.
  final Map<String, double> balanceByCustomer = {};
  for (final t in db.transactionsBox.values) {
    // Model convention used across the app:
    // - t.isGot == true  -> decreases balance (debit(-))
    // - t.isGot == false -> increases balance (credit(+))
    final delta = t.isGot ? -t.amount : t.amount;
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
