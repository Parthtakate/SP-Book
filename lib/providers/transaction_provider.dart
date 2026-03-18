import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/transaction.dart';
import 'db_provider.dart';

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
    ref.read(anyTransactionChangeProvider.notifier).notifyChanged();
  }

  Future<void> deleteTransaction(String transactionId) async {
    await ref.read(dbServiceProvider).deleteTransaction(transactionId);
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
  
  final customers = db.customersBox.values;
  for (var customer in customers) {
    final transactions = db.getTransactionsForCustomer(customer.id);
    double customerBalance = 0;
    for (var t in transactions) {
      if (t.isGot) {
        customerBalance -= t.amount;
      } else {
        customerBalance += t.amount;
      }
    }
    
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
