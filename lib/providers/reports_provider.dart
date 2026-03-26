import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
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
  final String? customerPhone;
  // positive = you will get (customer owes you), negative = you will pay (you owe them)
  final double balance;
  // "Credit(+)" column in statement/table semantics within the active date range.
  // Credit(+) increases running balance.
  final double totalCredit;
  // "Debit(-)" column in statement/table semantics within the active date range.
  // Debit(-) decreases running balance.
  final double totalDebit;
  final int transactionCount;
  final DateTime? lastTransactionDate;

  const CustomerSummary({
    required this.customerId,
    required this.customerName,
    this.customerPhone,
    required this.balance,
    required this.totalCredit,
    required this.totalDebit,
    required this.transactionCount,
    this.lastTransactionDate,
  });
}

/// Top-level ledger summary.
class ReportsSummary {
  // Totals within the active date range only.
  final double totalCredit; // Credit(+) increases balance
  final double totalDebit; // Debit(-) decreases balance
  // Net at the end of the active range (includes opening effects).
  final double net;
  final int totalEntries;
  final List<CustomerSummary> perCustomer;

  const ReportsSummary({
    required this.totalCredit,
    required this.totalDebit,
    required this.net,
    required this.totalEntries,
    required this.perCustomer,
  });
}

/// Shared date filter for the Reports page.
/// When `null`, reports are computed for ALL transactions (no opening/running slice).
class ReportDateRangeNotifier extends Notifier<DateTimeRange?> {
  @override
  DateTimeRange? build() => null;

  void setRange(DateTimeRange? range) {
    state = range;
  }

  void clear() {
    state = null;
  }
}

final reportDateRangeProvider = NotifierProvider<ReportDateRangeNotifier, DateTimeRange?>(
  ReportDateRangeNotifier.new,
);

/// Search text filter for the Reports page.
class ReportSearchTextNotifier extends Notifier<String> {
  @override
  String build() => '';

  void update(String text) {
    state = text;
  }
}

final reportSearchTextProvider = NotifierProvider<ReportSearchTextNotifier, String>(
  ReportSearchTextNotifier.new,
);

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

// ---------------------------------------------------------------------------
// Provider — read-only aggregation over existing DbService
// ---------------------------------------------------------------------------

/// [reportsProvider] computes a full [ReportsSummary] from the local Hive DB.
/// It is reactive: re-computes whenever any transaction changes.
/// ZERO writes — pure aggregation.
final reportsProvider = Provider<ReportsSummary>((ref) {
  // React to any transaction change (existing CQRS change signal)
  ref.watch(anyTransactionChangeProvider);
  final dateRange = ref.watch(reportDateRangeProvider);
  final searchText = ref.watch(reportSearchTextProvider).trim().toLowerCase();
  final db = ref.watch(dbServiceProvider);

  final bool hasRange = dateRange != null;
  final startDay = hasRange ? _day(dateRange.start) : null;
  final endDay = hasRange ? _day(dateRange.end) : null;

  double totalCredit = 0; // Credit(+) within range only
  double totalDebit = 0; // Debit(-) within range only
  int totalEntries = 0;
  final List<CustomerSummary> perCustomer = [];

  // Performance: group transactions once instead of calling
  // `db.getTransactionsForCustomer()` for every customer.
  final Map<String, List<TransactionModel>> txnsByCustomer = {};
  for (final t in db.transactionsBox.values) {
    txnsByCustomer.putIfAbsent(t.customerId, () => []).add(t);
  }
  for (final txns in txnsByCustomer.values) {
    // Keep same descending order assumption used elsewhere:
    // newest -> oldest.
    txns.sort((a, b) => b.date.compareTo(a.date));
  }

  for (final customer in db.getAllCustomers()) {
    // Apply search filter
    if (searchText.isNotEmpty &&
        !customer.name.toLowerCase().contains(searchText)) {
      continue;
    }

    final txns = txnsByCustomer[customer.id] ?? const <TransactionModel>[];

    // Opening balances come from transactions strictly BEFORE the selected start day.
    // In-range totals come from transactions inside [startDay..endDay] inclusive.
    double openingCredit = 0; // credit(+) before start
    double openingDebit = 0; // debit(-) before start
    double inCredit = 0; // credit(+) inside range
    double inDebit = 0; // debit(-) inside range

    // Credit(+) increases balance.
    // debit(-) decreases balance.
    // With our current model:
    // - t.isGot == true => balance decreases => debit(-)
    // - t.isGot == false => balance increases => credit(+)
    int inRangeCount = 0;
    DateTime? lastTxnInRange; // txns are already sorted desc in DbService.

    for (final TransactionModel t in txns) {
      final d = _day(t.date);

      if (!hasRange) {
        // All-time mode: treat everything as "inside the range" with opening=0.
        if (t.isGot) {
          inDebit += t.amount;
        } else {
          inCredit += t.amount;
        }
        inRangeCount++;
        lastTxnInRange ??= t.date;
        continue;
      }

      // Range mode: split into opening (< start) and in-range (<= end, >= start).
      if (d.isBefore(startDay!)) {
        if (t.isGot) {
          openingDebit += t.amount;
        } else {
          openingCredit += t.amount;
        }
      } else if (!d.isAfter(endDay!)) {
        // Inclusive in-range check: startDay <= d <= endDay
        if (t.isGot) {
          inDebit += t.amount;
        } else {
          inCredit += t.amount;
        }
        inRangeCount++;
        lastTxnInRange ??= t.date;
      }
    }

    final openingBalance = openingCredit - openingDebit;
    final balanceEnd = openingBalance + (inCredit - inDebit);

    totalCredit += inCredit;
    totalDebit += inDebit;
    totalEntries += inRangeCount;

    perCustomer.add(CustomerSummary(
      customerId: customer.id,
      customerName: customer.name,
      customerPhone: customer.phone,
      balance: balanceEnd,
      totalCredit: inCredit,
      totalDebit: inDebit,
      transactionCount: inRangeCount,
      lastTransactionDate: hasRange ? lastTxnInRange : (txns.isNotEmpty ? txns.first.date : null),
    ));
  }

  // Sort by absolute balance descending so high-value customers appear at top.
  perCustomer.sort((a, b) => b.balance.abs().compareTo(a.balance.abs()));

  // Net at the end of the selected range includes opening effects.
  final net = perCustomer.fold<double>(0, (sum, c) => sum + c.balance);

  return ReportsSummary(
    totalCredit: totalCredit,
    totalDebit: totalDebit,
    net: net,
    totalEntries: totalEntries,
    perCustomer: perCustomer,
  );
});
