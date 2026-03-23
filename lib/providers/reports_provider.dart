import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/transaction.dart';
import 'db_provider.dart';
import 'transaction_provider.dart';

// ---------------------------------------------------------------------------
// Reports value objects (pure Dart, no persistence, no Firestore)
// ---------------------------------------------------------------------------

/// Per-customer summary row used in the Reports screen.
class CustomerSummary {
  final String customerId;
  final String customerName;
  final double balance;      // positive = they owe you, negative = you owe them
  final double totalCredit;  // sum of isGot == true  (money received from customer)
  final double totalDebit;   // sum of isGot == false (money given to customer)
  final int transactionCount;
  final DateTime? lastTransactionDate;

  const CustomerSummary({
    required this.customerId,
    required this.customerName,
    required this.balance,
    required this.totalCredit,
    required this.totalDebit,
    required this.transactionCount,
    this.lastTransactionDate,
  });
}

/// Top-level ledger summary.
class ReportsSummary {
  final double totalCredit;      // Sum of all isGot == true amounts
  final double totalDebit;       // Sum of all isGot == false amounts
  final double net;              // totalCredit - totalDebit
  final List<CustomerSummary> perCustomer;

  const ReportsSummary({
    required this.totalCredit,
    required this.totalDebit,
    required this.net,
    required this.perCustomer,
  });
}

// ---------------------------------------------------------------------------
// Provider — read-only aggregation over existing DbService
// ---------------------------------------------------------------------------

/// [reportsProvider] computes a full [ReportsSummary] from the local Hive DB.
/// It is reactive: re-computes whenever any transaction changes.
/// ZERO writes — pure aggregation.
final reportsProvider = Provider<ReportsSummary>((ref) {
  // React to any transaction change (existing CQRS change signal)
  ref.watch(anyTransactionChangeProvider);
  final db = ref.watch(dbServiceProvider);

  double totalCredit = 0;
  double totalDebit = 0;
  final List<CustomerSummary> perCustomer = [];

  for (final customer in db.getAllCustomers()) {
    final txns = db.getTransactionsForCustomer(customer.id);
    double custCredit = 0;
    double custDebit = 0;

    for (final TransactionModel t in txns) {
      if (t.isGot) {
        custCredit += t.amount;
      } else {
        custDebit += t.amount;
      }
    }

    totalCredit += custCredit;
    totalDebit += custDebit;

    final balance = custDebit - custCredit;
    final lastDate = txns.isNotEmpty ? txns.first.date : null; // already sorted desc

    perCustomer.add(CustomerSummary(
      customerId: customer.id,
      customerName: customer.name,
      balance: balance,
      totalCredit: custCredit,
      totalDebit: custDebit,
      transactionCount: txns.length,
      lastTransactionDate: lastDate,
    ));
  }

  // Sort by absolute balance descending so high-value customers appear at top
  perCustomer.sort((a, b) => b.balance.abs().compareTo(a.balance.abs()));

  return ReportsSummary(
    totalCredit: totalCredit,
    totalDebit: totalDebit,
    net: totalCredit - totalDebit,
    perCustomer: perCustomer,
  );
});
