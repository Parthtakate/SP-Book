import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/customer.dart';
import '../models/transaction.dart';

class PdfService {
  static final _currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
  static final _dateFormat = DateFormat('d MMMM yyyy');
  static final _dateRangeFormat = DateFormat('dd MMM yyyy');
  static final _dateTimeFormat = DateFormat('dd MMM yyyy, hh:mm a');
  static final _timeOnlyFormat = DateFormat('hh:mm a');
  static final _dateOnlyFormat = DateFormat('dd MMM yyyy');

  // Cache a rupee-capable TTF so PDFs render `₹` correctly.
  static Future<pw.Font>? _pdfBaseFontFuture;
  static Future<pw.Font> _getPdfFont() {
    _pdfBaseFontFuture ??= () async {
      final data = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
      return pw.Font.ttf(data);
    }();
    return _pdfBaseFontFuture!;
  }

  // ---- Colors ----
  static const _brandBlue = PdfColor.fromInt(0xFF1565C0);
  static const _darkBlue = PdfColor.fromInt(0xFF0D47A1);
  static const _lightRedBg = PdfColor.fromInt(0xFFFFF0F0);
  static const _lightGreenBg = PdfColor.fromInt(0xFFF0FFF0);
  static const _redText = PdfColor.fromInt(0xFFC62828);
  static const _greenText = PdfColor.fromInt(0xFF2E7D32);
  static const _headerGrey = PdfColor.fromInt(0xFFF0F0F0);

  // =========================================================================
  // Individual Customer Statement (unchanged logic, same as before)
  // =========================================================================

  static Future<void> generateAndShareCustomerStatement({
    required Customer customer,
    required List<TransactionModel> transactions,
    required double balance,
    DateTimeRange? dateRange,
  }) async {
    final font = await _getPdfFont();
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: font),
    );

    // For running balance we need chronological order (oldest -> newest).
    final sortedTxsAsc = List<TransactionModel>.from(transactions)
      ..sort((a, b) => a.date.compareTo(b.date));

    final bool hasRange = dateRange != null;
    final startDay = hasRange ? _day(dateRange.start) : null;
    final endDay = hasRange ? _day(dateRange.end) : null;

    double openingBalance = 0;
    double totalDebitMinus = 0;
    double totalCreditPlus = 0;
    final List<TransactionModel> inRangeTxs = [];

    for (final t in sortedTxsAsc) {
      final d = _day(t.date);
      if (!hasRange) {
        inRangeTxs.add(t);
        if (t.isGot) {
          totalDebitMinus += t.amount;
        } else {
          totalCreditPlus += t.amount;
        }
        continue;
      }

      if (d.isBefore(startDay!)) {
        openingBalance += (!t.isGot ? t.amount : 0) - (t.isGot ? t.amount : 0);
      } else if (!d.isAfter(endDay!)) {
        inRangeTxs.add(t);
        if (t.isGot) {
          totalDebitMinus += t.amount;
        } else {
          totalCreditPlus += t.amount;
        }
      }
    }

    final double endBalance = hasRange
        ? openingBalance + (totalCreditPlus - totalDebitMinus)
        : balance;

    double runningBalance = openingBalance;

    final List<List<String>> tableRows = [
      ['', 'Opening Balance', '', '', _formatBalance(openingBalance)],
    ];

    for (final t in inRangeTxs) {
      final debitMinus = t.isGot ? t.amount : 0.0;
      final creditPlus = t.isGot ? 0.0 : t.amount;
      runningBalance += creditPlus - debitMinus;

      tableRows.add([
        _dateFormat.format(t.date),
        t.note.isEmpty ? '-' : t.note,
        debitMinus > 0 ? _currencyFormat.format(debitMinus) : '',
        creditPlus > 0 ? _currencyFormat.format(creditPlus) : '',
        _formatBalance(runningBalance),
      ]);
    }

    final String rangeLabel = hasRange
        ? '${_dateRangeFormat.format(startDay!)} - ${_dateRangeFormat.format(endDay!)}'
        : 'All';

    final String netLabel = endBalance > 0
        ? '(Part will get)'
        : endBalance < 0
            ? '(Part will give)'
            : '(Settled)';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Top bar
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                color: _brandBlue,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      customer.phone != null && customer.phone!.isNotEmpty
                          ? customer.phone!
                          : customer.name,
                      style: pw.TextStyle(fontSize: 10, color: PdfColors.white),
                    ),
                    pw.Text(
                      'SPBOOKS',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Text(
                  'Party Statement',
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text('Party Name: ${customer.name}', style: pw.TextStyle(fontSize: 12)),
              if (customer.phone != null && customer.phone!.isNotEmpty)
                pw.Text('Phone Number: ${customer.phone}', style: pw.TextStyle(fontSize: 11)),
              pw.SizedBox(height: 4),
              pw.Text('Date: ($rangeLabel)',
                  style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              pw.SizedBox(height: 12),
              _statementSummaryBox(
                openingBalance: openingBalance,
                totalDebitMinus: totalDebitMinus,
                totalCreditPlus: totalCreditPlus,
                endBalance: endBalance,
                netLabel: netLabel,
              ),
              pw.SizedBox(height: 10),
              pw.TableHelper.fromTextArray(
                context: context,
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                  fontSize: 9,
                ),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey600),
                cellStyle: const pw.TextStyle(fontSize: 9),
                cellAlignment: pw.Alignment.centerLeft,
                data: [
                  ['Date', 'Details', 'Debit(-)', 'Credit(+)', 'Balance'],
                  ...tableRows,
                ],
              ),
              pw.Spacer(),
              pw.Text(
                'No. of Entries: ${inRangeTxs.length} (${hasRange ? 'Filtered' : 'All'})',
                style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Report Generated: ${_dateTimeFormat.format(DateTime.now())}',
                style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
            ],
          );
        },
      ),
    );

    final output = await getTemporaryDirectory();
    final suffix = hasRange
        ? '${_shortDay(startDay!)}_to_${_shortDay(endDay!)}'
        : 'all';
    final file = File(
      '${output.path}/spbooks_statement_${customer.name.replaceAll(' ', '_')}_$suffix.pdf',
    );
    await file.writeAsBytes(await pdf.save());

    // ignore: deprecated_member_use
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'SPBOOKS Party Statement for ${customer.name}',
    );
  }

  // =========================================================================
  // Customer List Report (NEW format — global report)
  // =========================================================================

  /// Generates a "Customer List Report" PDF and returns the file path.
  /// The PDF follows a formal document format with header/footer branding,
  /// summary cards, colored data table, and pagination.
  static Future<String?> generateCustomerListReportPdf({
    required List<Customer> customers,
    required Map<String, List<TransactionModel>> transactionsByCustomer,
    required double totalToReceive,
    required double totalToPay,
    DateTimeRange? dateRange,
  }) async {
    final font = await _getPdfFont();
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: font),
    );
    final now = DateTime.now();
    final netBalance = totalToReceive - totalToPay;

    final bool hasRange = dateRange != null;
    final startDay = dateRange != null ? _day(dateRange.start) : null;
    final endDay = dateRange != null ? _day(dateRange.end) : null;

    // Prepare customer data rows
    final List<_CustomerReportRow> rows = [];
    for (final customer in customers) {
      final allTxns = transactionsByCustomer[customer.id] ?? [];
      if (allTxns.isEmpty) continue;

      final txns = hasRange
          ? allTxns.where((t) {
              final d = _day(t.date);
              return !d.isBefore(startDay!) && !d.isAfter(endDay!);
            }).toList()
          : allTxns;
      if (txns.isEmpty) continue;

      double youllGet = 0;
      double youllGive = 0;
      DateTime? lastDate;

      for (final t in txns) {
        if (t.isGot) {
          youllGive += t.amount; // You got money → you'll give (debit)
        } else {
          youllGet += t.amount; // You gave money → you'll get (credit)
        }
      }

      // Calculate net balance per customer
      final customerBalance = youllGet - youllGive;

      // Find last transaction date (for collection date)
      final sortedTxns = List<TransactionModel>.from(txns)
        ..sort((a, b) => b.date.compareTo(a.date));
      lastDate = sortedTxns.first.date;

      rows.add(_CustomerReportRow(
        name: customer.name,
        phone: customer.phone ?? '',
        youllGet: customerBalance > 0 ? customerBalance : 0,
        youllGive: customerBalance < 0 ? customerBalance.abs() : 0,
        collectionDate: lastDate,
      ));
    }

    // Calculate grand totals
    double grandTotalGet = 0;
    double grandTotalGive = 0;
    for (final r in rows) {
      grandTotalGet += r.youllGet;
      grandTotalGive += r.youllGive;
    }

    final String netSuffix = netBalance >= 0 ? 'Dr' : 'Cr';

    // Build the PDF with MultiPage for proper pagination
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(0),
        header: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: _darkBlue,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '',
                  style: pw.TextStyle(fontSize: 10, color: PdfColors.white),
                ),
                pw.Text(
                  'SPBOOKS',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
              ],
            ),
          );
        },
        footer: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Report Generated : ${_timeOnlyFormat.format(now)} | ${_dateOnlyFormat.format(now)}',
                      style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                    ),
                    pw.Text(
                      'Page ${context.pageNumber} of ${context.pagesCount}',
                      style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                    ),
                  ],
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: _darkBlue,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                      'SPBOOKS - Digital Ledger',
                      style: pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
        build: (pw.Context context) {
          return [
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  // Title
                  pw.Center(
                    child: pw.Text(
                      'Customer List Report',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Center(
                    child: pw.Text(
                      '(As of Today - ${_dateFormat.format(now)})',
                      style: pw.TextStyle(
                        fontSize: 11,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 16),

                  // Summary Cards Row
                  pw.Row(
                    children: [
                      _summaryCard(
                        "You'll Get",
                        _currencyFormat.format(totalToReceive),
                        _greenText,
                      ),
                      pw.SizedBox(width: 8),
                      _summaryCard(
                        "You'll Give",
                        _currencyFormat.format(totalToPay),
                        _redText,
                      ),
                      pw.SizedBox(width: 8),
                      _summaryCard(
                        'Net Balance',
                        '${_currencyFormat.format(netBalance.abs())} $netSuffix',
                        netBalance >= 0 ? _greenText : _redText,
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 16),

                  // Data Table
                  _buildCustomerTable(rows, grandTotalGet, grandTotalGive),
                ],
              ),
            ),
          ];
        },
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File('${output.path}/spbooks_customer_list_report.pdf');
    await file.writeAsBytes(await pdf.save());
    return file.path;
  }

  /// Convenience method — generate + share in one call (used from other screens).
  static Future<void> generateAndShareFullReportStatements({
    required List<Customer> customers,
    required Map<String, List<TransactionModel>> transactionsByCustomer,
    required double totalToReceive,
    required double totalToPay,
    DateTimeRange? dateRange,
  }) async {
    final filePath = await generateCustomerListReportPdf(
      customers: customers,
      transactionsByCustomer: transactionsByCustomer,
      totalToReceive: totalToReceive,
      totalToPay: totalToPay,
      dateRange: dateRange,
    );
    if (filePath == null) return;

    // ignore: deprecated_member_use
    await Share.shareXFiles(
      [XFile(filePath)],
      text: 'SPBOOKS Customer List Report',
    );
  }

  /// Legacy full report (kept for backward compat with settings_screen export).
  static Future<void> generateAndShareFullReport({
    required List<dynamic> customers,
    required Map<String, List<dynamic>> transactionsByCustomer,
    required double totalToReceive,
    required double totalToPay,
  }) async {
    // Delegate to the new format
    final castCustomers = customers.cast<Customer>();
    final castTxns = transactionsByCustomer.map(
      (k, v) => MapEntry(k, v.cast<TransactionModel>()),
    );
    await generateAndShareFullReportStatements(
      customers: castCustomers,
      transactionsByCustomer: castTxns,
      totalToReceive: totalToReceive,
      totalToPay: totalToPay,
    );
  }

  // =========================================================================
  // Private Helpers
  // =========================================================================

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _shortDay(DateTime d) => DateFormat('ddMMyyyy').format(d);

  static String _formatBalance(double value) {
    final abs = value.abs();
    if (abs < 0.000001) return _currencyFormat.format(0);
    final drcr = value >= 0 ? 'Cr' : 'Dr';
    return '${_currencyFormat.format(abs)} $drcr';
  }

  static pw.Widget _statementSummaryBox({
    required double openingBalance,
    required double totalDebitMinus,
    required double totalCreditPlus,
    required double endBalance,
    required String netLabel,
  }) {
    pw.Widget col(String header, pw.Widget value, {String? subHeader}) {
      return pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(header, style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            pw.SizedBox(height: 2),
            value,
            if (subHeader != null) ...[
              pw.SizedBox(height: 2),
              pw.Text(subHeader, style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            ]
          ],
        ),
      );
    }

    pw.Widget divider = pw.Container(
      width: 1,
      margin: const pw.EdgeInsets.symmetric(horizontal: 10),
      height: 56,
      color: PdfColors.grey300,
    );

    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          col(
            'Opening Balance',
            pw.Text(
              _formatBalance(openingBalance),
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          ),
          divider,
          col(
            'Total Debit(-)',
            pw.Text(
              _currencyFormat.format(totalDebitMinus),
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          ),
          divider,
          col(
            'Total Credit(+)',
            pw.Text(
              _currencyFormat.format(totalCreditPlus),
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          ),
          divider,
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Net Balance',
                    style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                pw.SizedBox(height: 2),
                pw.Text(
                  _formatBalance(endBalance),
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 2),
                pw.Text(netLabel,
                    style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Summary card for the PDF report header.
  static pw.Widget _summaryCard(String label, String amount, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              amount,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the data table with colored column backgrounds and grand total row.
  static pw.Widget _buildCustomerTable(
    List<_CustomerReportRow> rows,
    double grandTotalGet,
    double grandTotalGive,
  ) {
    const headerStyle = pw.TextStyle(fontSize: 9, color: PdfColors.black);
    final headerBoldStyle = pw.TextStyle(
      fontSize: 9,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.black,
    );

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(2.5), // Name
        1: const pw.FlexColumnWidth(2),   // Details
        2: const pw.FlexColumnWidth(1.8), // You'll Get
        3: const pw.FlexColumnWidth(1.8), // You'll Give
        4: const pw.FlexColumnWidth(1.8), // Collection Date
      },
      children: [
        // Header row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _headerGrey),
          children: [
            _tableCell('Name', headerBoldStyle),
            _tableCell('Details', headerBoldStyle),
            _tableCell("You'll Get", headerBoldStyle),
            _tableCell("You'll Give", headerBoldStyle),
            _tableCell('Collection Date', headerBoldStyle),
          ],
        ),
        // Data rows
        ...rows.map((r) {
          return pw.TableRow(
            children: [
              _tableCell(r.name, headerStyle),
              _tableCell(r.phone, headerStyle),
              _tableCellColored(
                r.youllGet > 0 ? _currencyFormat.format(r.youllGet) : '',
                headerStyle,
                _lightGreenBg,
              ),
              _tableCellColored(
                r.youllGive > 0 ? _currencyFormat.format(r.youllGive) : '',
                headerStyle,
                _lightRedBg,
              ),
              _tableCell(
                r.collectionDate != null
                    ? _dateRangeFormat.format(r.collectionDate!)
                    : '',
                headerStyle,
              ),
            ],
          );
        }),
        // Grand Total row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _headerGrey),
          children: [
            _tableCell('Grand Total', pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            )),
            _tableCell('', headerStyle),
            _tableCellColored(
              _currencyFormat.format(grandTotalGet),
              pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _greenText),
              _lightGreenBg,
            ),
            _tableCellColored(
              _currencyFormat.format(grandTotalGive),
              pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _redText),
              _lightRedBg,
            ),
            _tableCell('', headerStyle),
          ],
        ),
      ],
    );
  }

  /// Plain table cell.
  static pw.Widget _tableCell(String text, pw.TextStyle style) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(text, style: style),
    );
  }

  /// Table cell with a colored background.
  static pw.Widget _tableCellColored(
      String text, pw.TextStyle style, PdfColor bgColor) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      color: bgColor,
      child: pw.Text(text, style: style),
    );
  }
}

/// Internal data class for report rows.
class _CustomerReportRow {
  final String name;
  final String phone;
  final double youllGet;
  final double youllGive;
  final DateTime? collectionDate;

  const _CustomerReportRow({
    required this.name,
    required this.phone,
    required this.youllGet,
    required this.youllGive,
    this.collectionDate,
  });
}
