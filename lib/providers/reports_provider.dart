import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'db_provider.dart';

// ---------------------------------------------------------------------------
// Data Models for the Account Statement
// ---------------------------------------------------------------------------

/// A single row in the Account Statement table.
class AccountStatementEntry {
  final DateTime date;
  final String customerName;
  final String details; // note / description
  final double debitAmount; // You Gave (-)
  final double creditAmount; // You Got (+)

  const AccountStatementEntry({
    required this.date,
    required this.customerName,
    required this.details,
    required this.debitAmount,
    required this.creditAmount,
  });
}

/// A group of entries for one calendar month.
class MonthGroup {
  final String label; // e.g. "October 2023"
  final int year;
  final int month;
  final List<AccountStatementEntry> entries;
  final double monthTotalDebit;
  final double monthTotalCredit;

  const MonthGroup({
    required this.label,
    required this.year,
    required this.month,
    required this.entries,
    required this.monthTotalDebit,
    required this.monthTotalCredit,
  });
}

/// The complete Account Statement.
class AccountStatement {
  final List<MonthGroup> monthGroups;
  final double grandTotalDebit;
  final double grandTotalCredit;
  final double netBalance;
  final String balanceType; // "Dr" or "Cr"
  final int entryCount;

  const AccountStatement({
    required this.monthGroups,
    required this.grandTotalDebit,
    required this.grandTotalCredit,
    required this.netBalance,
    required this.balanceType,
    required this.entryCount,
  });
}

// ---------------------------------------------------------------------------
// Shared date filter
// ---------------------------------------------------------------------------

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

// Search text filter
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

// ---------------------------------------------------------------------------
// Month names helper
// ---------------------------------------------------------------------------
const _monthNames = [
  '', 'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

// ---------------------------------------------------------------------------
// Provider — Account Statement
// ---------------------------------------------------------------------------

/// Computes a complete [AccountStatement] from all transactions in the local DB.
/// Groups by month, sorts by date (oldest first within each month).
final accountStatementProvider = Provider<AccountStatement>((ref) {
  final dateRange = ref.watch(reportDateRangeProvider);
  final searchText = ref.watch(reportSearchTextProvider).trim().toLowerCase();
  final db = ref.watch(dbServiceProvider);

  final bool hasRange = dateRange != null;
  final startDay = hasRange ? DateTime(dateRange.start.year, dateRange.start.month, dateRange.start.day) : null;
  final endDay = hasRange ? DateTime(dateRange.end.year, dateRange.end.month, dateRange.end.day) : null;

  // Build customer name lookup
  final Map<String, String> customerNames = {};
  for (final c in db.getAllCustomers()) {
    customerNames[c.id] = c.name;
  }

  // Collect all transactions with customer names
  final List<AccountStatementEntry> allEntries = [];

  for (final t in db.transactionsBox.values) {
    if (t.isDeleted) continue;

    final customerName = customerNames[t.customerId] ?? 'Unknown';

    // Apply search filter
    if (searchText.isNotEmpty &&
        !customerName.toLowerCase().contains(searchText) &&
        !t.note.toLowerCase().contains(searchText)) {
      continue;
    }

    // Apply date filter
    if (hasRange) {
      final d = DateTime(t.date.year, t.date.month, t.date.day);
      if (d.isBefore(startDay!) || d.isAfter(endDay!)) continue;
    }

    // isGot == true → Credit(+) (You Got money)
    // isGot == false → Debit(-) (You Gave money)
    allEntries.add(AccountStatementEntry(
      date: t.date,
      customerName: customerName,
      details: t.note,
      debitAmount: t.isGot ? 0 : (t.amountInPaise / 100.0),
      creditAmount: t.isGot ? (t.amountInPaise / 100.0) : 0,
    ));
  }

  // Sort all entries by date (oldest first for statement format)
  allEntries.sort((a, b) => a.date.compareTo(b.date));

  // Group by month
  final Map<String, List<AccountStatementEntry>> grouped = {};
  final Map<String, (int year, int month)> groupMeta = {};

  for (final entry in allEntries) {
    final key = '${entry.date.year}-${entry.date.month.toString().padLeft(2, '0')}';
    grouped.putIfAbsent(key, () => []).add(entry);
    groupMeta.putIfAbsent(key, () => (entry.date.year, entry.date.month));
  }

  // Build month groups (sorted chronologically)
  final sortedKeys = grouped.keys.toList()..sort();
  double grandTotalDebit = 0;
  double grandTotalCredit = 0;

  final List<MonthGroup> monthGroups = [];
  for (final key in sortedKeys) {
    final entries = grouped[key]!;
    final meta = groupMeta[key]!;

    double monthDebit = 0;
    double monthCredit = 0;
    for (final e in entries) {
      monthDebit += e.debitAmount;
      monthCredit += e.creditAmount;
    }

    grandTotalDebit += monthDebit;
    grandTotalCredit += monthCredit;

    monthGroups.add(MonthGroup(
      label: '${_monthNames[meta.$2]} ${meta.$1}',
      year: meta.$1,
      month: meta.$2,
      entries: entries,
      monthTotalDebit: monthDebit,
      monthTotalCredit: monthCredit,
    ));
  }

  final netBalance = grandTotalCredit - grandTotalDebit;
  final balanceType = netBalance >= 0 ? 'Cr' : 'Dr';

  return AccountStatement(
    monthGroups: monthGroups,
    grandTotalDebit: grandTotalDebit,
    grandTotalCredit: grandTotalCredit,
    netBalance: netBalance,
    balanceType: balanceType,
    entryCount: allEntries.length,
  );
});
