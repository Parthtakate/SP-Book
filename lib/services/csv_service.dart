import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../providers/reports_provider.dart';

/// Converts a list of rows into RFC 4180-compliant CSV text without
/// any external csv package dependency.
String _toCsv(List<List<dynamic>> rows) {
  final buf = StringBuffer();
  for (final row in rows) {
    final cells = row.map((cell) {
      final s = cell.toString();
      // Wrap in quotes if the cell contains a comma, newline, or double-quote
      if (s.contains(',') || s.contains('\n') || s.contains('"')) {
        return '"${s.replaceAll('"', '""')}"';
      }
      return s;
    });
    buf.writeln(cells.join(','));
  }
  return buf.toString();
}

class CsvService {
  static final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  static Future<String?> generateAccountStatementCsv({
    required String userName,
    required AccountStatement statement,
    DateTimeRange? dateRange,
  }) async {
    try {
      final List<List<dynamic>> rows = [];

      // Metadata header block
      rows.add(['SPBOOKS Account Statement']);
      rows.add(['User', userName]);
      rows.add(['Generated At', _dateFormat.format(DateTime.now())]);

      if (dateRange != null) {
        rows.add([
          'Date Range',
          '${DateFormat('dd MMM yy').format(dateRange.start)} to ${DateFormat('dd MMM yy').format(dateRange.end)}'
        ]);
      }
      rows.add([]);

      // Summary block
      rows.add(['SUMMARY']);
      rows.add(['Total Debit (-)', statement.grandTotalDebit.toStringAsFixed(2)]);
      rows.add(['Total Credit (+)', statement.grandTotalCredit.toStringAsFixed(2)]);
      rows.add([
        'Net Balance',
        '${statement.netBalance.abs().toStringAsFixed(2)} ${statement.balanceType}'
      ]);
      rows.add([]);

      // Data table headers
      rows.add(['Date', 'Name', 'Details', 'Debit(-)', 'Credit(+)']);

      // Per-month data groups
      for (final group in statement.monthGroups) {
        // Month label row
        rows.add(['--- ${group.label} ---', '', '', '', '']);

        for (final entry in group.entries) {
          rows.add([
            _dateFormat.format(entry.date),
            entry.customerName,
            entry.details,
            entry.debitAmount > 0 ? entry.debitAmount.toStringAsFixed(2) : '',
            entry.creditAmount > 0 ? entry.creditAmount.toStringAsFixed(2) : '',
          ]);
        }

        // Monthly total row
        rows.add([
          '${group.label} Total',
          '',
          '',
          group.monthTotalDebit.toStringAsFixed(2),
          group.monthTotalCredit.toStringAsFixed(2),
        ]);
        rows.add([]);
      }

      final csvData = _toCsv(rows);

      final dir = await getApplicationDocumentsDirectory();
      final path =
          '${dir.path}/Statement_${DateTime.now().millisecondsSinceEpoch}.csv';
      await File(path).writeAsString(csvData);

      return path;
    } catch (e) {
      debugPrint('CSV generation error: $e');
      return null;
    }
  }
}
