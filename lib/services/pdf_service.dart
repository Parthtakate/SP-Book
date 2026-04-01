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
import '../providers/reports_provider.dart';

class PdfService {
  static final _currencyFormat = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
  );
  static final _inrFormat = NumberFormat('#,##,##0.00', 'en_IN');
  static final _dateFormat = DateFormat('dd MMM yyyy');
  static final _shortDateFormat = DateFormat('dd MMM');
  static final _timestampFormat = DateFormat("h:mm a | dd MMM''yy");

  static Future<pw.Font>? _pdfBaseFontFuture;
  static Future<pw.Font> _getPdfFont() {
    _pdfBaseFontFuture ??= () async {
      final data = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
      return pw.Font.ttf(data);
    }();
    return _pdfBaseFontFuture!;
  }

  // ---- Professional, Print-Friendly Colors ----
  static const _textBlack = PdfColors.black;
  static const _textGrey = PdfColor.fromInt(0xFF616161);
  static const _borderGrey = PdfColor.fromInt(0xFFE0E0E0);
  static const _bgLightGrey = PdfColor.fromInt(0xFFF5F5F5);
  static const _bgHeaderGrey = PdfColor.fromInt(0xFFE8E8E8); // Slightly darker for table header
  
  static const _greenColor = PdfColor.fromInt(0xFF2E7D32); // You will get / You Got / Received
  static const _redColor = PdfColor.fromInt(0xFFC62828); // You will give / You Gave / Given

  // =========================================================================
  // 0. ACCOUNT STATEMENT (KHATABOOK-STYLE)
  // =========================================================================
  static Future<String?> generateAccountStatementPdf({
    required String userName,
    required AccountStatement statement,
    DateTimeRange? dateRange,
  }) async {
    final font = await _getPdfFont();
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: font),
    );

    final String rangeLabel = dateRange != null
        ? '${_dateFormat.format(dateRange.start)} - ${_dateFormat.format(dateRange.end)}'
        : 'All';

    // Colors
    const headerBg = PdfColor.fromInt(0xFF1A237E);
    const debitBg = PdfColor.fromInt(0xFFFFF0F0);
    const creditBg = PdfColor.fromInt(0xFFF0FFF0);
    const debitColor = PdfColor.fromInt(0xFFC62828);
    const creditColor = PdfColor.fromInt(0xFF2E7D32);
    const grey = PdfColor.fromInt(0xFF757575);
    const lightGrey = PdfColor.fromInt(0xFFF5F5F5);
    const borderColor = PdfColor.fromInt(0xFFE0E0E0);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Powered by SPBOOKS',
                style: pw.TextStyle(fontSize: 8, color: grey, fontWeight: pw.FontWeight.bold)),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8, color: grey)),
          ],
        ),
        build: (pw.Context context) {
          final List<pw.Widget> widgets = [];

          // ── Dark blue header bar ──
          widgets.add(
            pw.Container(
              color: headerBg,
              padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    userName,
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'SPBOOKS',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          );

          // ── Title section ──
          widgets.add(pw.SizedBox(height: 20));
          widgets.add(
            pw.Center(
              child: pw.Column(
                children: [
                  pw.Text(
                    'Account Statement',
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text('($rangeLabel)', style: const pw.TextStyle(fontSize: 11, color: grey)),
                ],
              ),
            ),
          );

          // ── Summary cards ──
          widgets.add(pw.SizedBox(height: 16));
          widgets.add(
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: borderColor),
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.all(10),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Total Debit(-)', style: const pw.TextStyle(fontSize: 9, color: grey)),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            '\u20B9${_inrFormat.format(statement.grandTotalDebit)}',
                            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                  pw.Container(width: 1, height: 40, color: borderColor),
                  pw.Expanded(
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.all(10),
                      child: pw.Column(
                        children: [
                          pw.Text('Total Credit(+)', style: const pw.TextStyle(fontSize: 9, color: grey)),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            '\u20B9${_inrFormat.format(statement.grandTotalCredit)}',
                            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                  pw.Container(width: 1, height: 40, color: borderColor),
                  pw.Expanded(
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.all(10),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('Net Balance', style: const pw.TextStyle(fontSize: 9, color: grey)),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            '\u20B9${_inrFormat.format(statement.netBalance.abs())} ${statement.balanceType}',
                            style: pw.TextStyle(
                              fontSize: 13,
                              fontWeight: pw.FontWeight.bold,
                              color: statement.balanceType == 'Cr' ? creditColor : debitColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );

          // ── Entry count ──
          widgets.add(pw.SizedBox(height: 14));
          widgets.add(
            pw.Text(
              'No. of Entries:  ${statement.entryCount} (${dateRange != null ? "Filtered" : "All"})',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          );
          widgets.add(pw.SizedBox(height: 8));

          // ── Table header ──
          widgets.add(
            pw.Container(
              color: const PdfColor.fromInt(0xFFE8E8E8),
              padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: pw.Row(
                children: [
                  pw.SizedBox(width: 50, child: pw.Text('Date', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                  pw.Expanded(flex: 3, child: pw.Text('Name', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                  pw.Expanded(flex: 3, child: pw.Text('Details', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                  pw.SizedBox(
                    width: 80,
                    child: pw.Text('Debit(-)', textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.SizedBox(
                    width: 80,
                    child: pw.Text('Credit(+)', textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  ),
                ],
              ),
            ),
          );

          // ── Month groups with entries ──
          for (final group in statement.monthGroups) {
            // Month header
            widgets.add(
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 10, bottom: 4, left: 4),
                child: pw.Text(
                  group.label,
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                ),
              ),
            );

            // Transaction entries
            for (final entry in group.entries) {
              widgets.add(
                pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border(bottom: pw.BorderSide(color: borderColor, width: 0.5)),
                  ),
                  padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  child: pw.Row(
                    children: [
                      pw.SizedBox(
                        width: 50,
                        child: pw.Text(_shortDateFormat.format(entry.date),
                            style: const pw.TextStyle(fontSize: 9)),
                      ),
                      pw.Expanded(
                        flex: 3,
                        child: pw.Text(entry.customerName,
                            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Expanded(
                        flex: 3,
                        child: pw.Text(entry.details,
                            style: const pw.TextStyle(fontSize: 9)),
                      ),
                      pw.Container(
                        width: 80,
                        color: entry.debitAmount > 0 ? debitBg : null,
                        padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                        child: pw.Text(
                          entry.debitAmount > 0 ? _inrFormat.format(entry.debitAmount) : '',
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: debitColor),
                        ),
                      ),
                      pw.Container(
                        width: 80,
                        color: entry.creditAmount > 0 ? creditBg : null,
                        padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                        child: pw.Text(
                          entry.creditAmount > 0 ? _inrFormat.format(entry.creditAmount) : '',
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: creditColor),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            // Monthly total row
            final monthName = group.label.split(' ').first;
            widgets.add(
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                    top: pw.BorderSide(color: borderColor),
                    bottom: pw.BorderSide(color: borderColor),
                  ),
                  color: lightGrey,
                ),
                padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: pw.Row(
                  children: [
                    pw.SizedBox(width: 50),
                    pw.Expanded(
                      flex: 3,
                      child: pw.Text('$monthName Total',
                          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.Expanded(flex: 3, child: pw.SizedBox()),
                    pw.SizedBox(
                      width: 80,
                      child: pw.Text(_inrFormat.format(group.monthTotalDebit),
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: debitColor)),
                    ),
                    pw.SizedBox(
                      width: 80,
                      child: pw.Text(_inrFormat.format(group.monthTotalCredit),
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: creditColor)),
                    ),
                  ],
                ),
              ),
            );
          }

          // ── Grand total row ──
          widgets.add(
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: borderColor, width: 1.5),
                color: lightGrey,
              ),
              padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: pw.Row(
                children: [
                  pw.SizedBox(width: 50),
                  pw.Expanded(
                    flex: 3,
                    child: pw.Text('Grand Total',
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Expanded(flex: 3, child: pw.SizedBox()),
                  pw.SizedBox(
                    width: 80,
                    child: pw.Text(_inrFormat.format(statement.grandTotalDebit),
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: debitColor)),
                  ),
                  pw.SizedBox(
                    width: 80,
                    child: pw.Text(_inrFormat.format(statement.grandTotalCredit),
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: creditColor)),
                  ),
                ],
              ),
            ),
          );

          // ── Timestamp footer ──
          widgets.add(pw.SizedBox(height: 12));
          widgets.add(
            pw.Text(
              'Report Generated : ${_timestampFormat.format(DateTime.now())}',
              style: pw.TextStyle(fontSize: 8, color: grey, fontStyle: pw.FontStyle.italic),
            ),
          );

          return widgets;
        },
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File('${output.path}/account_statement.pdf');
    await file.writeAsBytes(await pdf.save());
    return file.path;
  }

  // =========================================================================
  // 1. INDIVIDUAL CUSTOMER STATEMENT (LEDGER REPORT)
  // =========================================================================
  static Future<void> generateAndShareCustomerStatement({
    required Customer customer,
    required List<TransactionModel> transactions,
    required double balance,
    DateTimeRange? dateRange,
    String businessName = 'SPBOOKS', // Can be parameterized later
    String? businessPhone,
  }) async {
    final font = await _getPdfFont();
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: font),
    );

    // Sort oldest to newest for accurate running balance
    final sortedTxsAsc = List<TransactionModel>.from(transactions)
      ..sort((a, b) => a.date.compareTo(b.date));

    final bool hasRange = dateRange != null;
    final startDay = hasRange ? _day(dateRange.start) : null;
    final endDay = hasRange ? _day(dateRange.end) : null;

    double openingBalance = 0;
    double totalYouGave = 0; // Money given out
    double totalYouGot = 0;  // Money received
    final List<TransactionModel> inRangeTxs = [];

    for (final t in sortedTxsAsc) {
      final d = _day(t.date);
      if (!hasRange) {
        inRangeTxs.add(t);
        if (t.isGot) {
          totalYouGot += (t.amountInPaise / 100.0);
        } else {
          totalYouGave += (t.amountInPaise / 100.0);
        }
        continue;
      }

      if (d.isBefore(startDay!)) {
        openingBalance += (!t.isGot ? (t.amountInPaise / 100.0) : 0) - (t.isGot ? (t.amountInPaise / 100.0) : 0);
      } else if (!d.isAfter(endDay!)) {
        inRangeTxs.add(t);
        if (t.isGot) {
          totalYouGot += (t.amountInPaise / 100.0);
        } else {
          totalYouGave += (t.amountInPaise / 100.0);
        }
      }
    }

    final double finalBalance = hasRange
        ? openingBalance + (totalYouGave - totalYouGot)
        : balance;

    final String rangeLabel = hasRange
        ? '${_dateFormat.format(startDay!)} to ${_dateFormat.format(endDay!)}'
        : 'All Time';

    // Build PDF Document
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        footer: (context) => _buildFooter(context),
        build: (pw.Context context) {
          return [
            // 1. HEADER (Business Details)
            _buildBusinessHeader(businessName, businessPhone, 'Customer Statement', rangeLabel, entriesCount: inRangeTxs.length),
            pw.SizedBox(height: 20),

            // 2. CUSTOMER DETAILS
            _buildCustomerDetails(customer),
            pw.SizedBox(height: 16),

            // 3. SUMMARY CARD
            _buildStatementSummary(openingBalance, totalYouGave, totalYouGot, finalBalance),
            pw.SizedBox(height: 24),

            // 4. TRANSACTION TABLE
            _buildTransactionsTable(inRangeTxs, openingBalance),
            pw.SizedBox(height: 40),

            // 5. SIGNATURE SECTION
            _buildSignatureSection(customer.name),
          ];
        },
      ),
    );

    final output = await getTemporaryDirectory();
    final suffix = hasRange
        ? '${_shortDay(startDay!)}_to_${_shortDay(endDay!)}'
        : 'all';
    final file = File(
      '${output.path}/statement_${customer.name.replaceAll(' ', '_')}_$suffix.pdf',
    );
    await file.writeAsBytes(await pdf.save());

    // ignore: deprecated_member_use
    await Share.shareXFiles([
      XFile(file.path),
    ], text: 'Ledger Statement for ${customer.name}');
  }

  // =========================================================================
  // 2. CUSTOMER LIST REPORT (GLOBAL REPORT)
  // =========================================================================
  static Future<String?> generateCustomerListReportPdf({
    required List<Customer> customers,
    required Map<String, List<TransactionModel>> transactionsByCustomer,
    required double totalToReceive,
    required double totalToPay,
    DateTimeRange? dateRange,
    String businessName = 'SPBOOKS',
  }) async {
    final font = await _getPdfFont();
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: font),
    );
    
    final bool hasRange = dateRange != null;
    final startDay = hasRange ? _day(dateRange.start) : null;
    final endDay = hasRange ? _day(dateRange.end) : null;

    final List<_CustomerReportRow> rows = [];
    double grandTotalGet = 0;
    double grandTotalGive = 0;

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

      double youGave = 0;
      double youGot = 0;

      for (final t in txns) {
        if (t.isGot) {
          youGot += (t.amountInPaise / 100.0);
        } else {
          youGave += (t.amountInPaise / 100.0);
        }
      }

      final customerBalance = youGave - youGot;
      final willGet = customerBalance > 0 ? customerBalance : 0.0;
      final willGive = customerBalance < 0 ? customerBalance.abs() : 0.0;

      grandTotalGet += willGet;
      grandTotalGive += willGive;

      rows.add(
        _CustomerReportRow(
          name: customer.name,
          phone: customer.phone ?? '-',
          willGet: willGet,
          willGive: willGive,
        ),
      );
    }

    final double netBalance = grandTotalGet - grandTotalGive;
    final String rangeLabel = hasRange
        ? '${_dateFormat.format(startDay!)} to ${_dateFormat.format(endDay!)}'
        : 'All Time';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        footer: (context) => _buildFooter(context),
        build: (pw.Context context) {
          return [
            _buildBusinessHeader(businessName, null, 'Customer Ledger Summary', rangeLabel, entriesCount: rows.length),
            pw.SizedBox(height: 20),
            
            // Global Summary Card
            _buildGlobalSummary(grandTotalGet, grandTotalGive, netBalance),
            pw.SizedBox(height: 24),

            // Customer List Table
            _buildCustomerListTable(rows, grandTotalGet, grandTotalGive),
          ];
        },
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File('${output.path}/customer_ledger_summary.pdf');
    await file.writeAsBytes(await pdf.save());
    return file.path;
  }

  // =========================================================================
  // 3. LEGACY WRAPPERS
  // =========================================================================
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
    await Share.shareXFiles([XFile(filePath)], text: 'Customer Ledger Summary');
  }

  static Future<void> generateAndShareFullReport({
    required List<dynamic> customers,
    required Map<String, List<dynamic>> transactionsByCustomer,
    required double totalToReceive,
    required double totalToPay,
  }) async {
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
  // COMPONENT BUILDERS (UI)
  // =========================================================================

  static pw.Widget _buildBusinessHeader(String name, String? phone, String title, String rangeLabel, {int? entriesCount}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  name.toUpperCase(),
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: _textBlack),
                ),
                if (phone != null && phone.isNotEmpty)
                  pw.Text('Phone: $phone', style: pw.TextStyle(fontSize: 12, color: _textGrey)),
              ]
            ),
             pw.Column(
               crossAxisAlignment: pw.CrossAxisAlignment.end,
               children: [
                 pw.Text('Generated on: ${_dateFormat.format(DateTime.now())}', style: pw.TextStyle(fontSize: 10, color: _textGrey)),
               ]
            )
          ]
        ),
        pw.SizedBox(height: 12),
        pw.Divider(color: _borderGrey, thickness: 1),
        pw.SizedBox(height: 12),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _textBlack),
            ),
            pw.Column(
               crossAxisAlignment: pw.CrossAxisAlignment.end,
               children: [
                 if (entriesCount != null)
                    pw.Text('No. of entries: $entriesCount', style: pw.TextStyle(fontSize: 10, color: _textBlack, fontWeight: pw.FontWeight.bold)),
                 pw.SizedBox(height: 2),
                 pw.Text(
                   'Date: $rangeLabel',
                   style: pw.TextStyle(fontSize: 10, color: _textGrey),
                 ),
               ]
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildCustomerDetails(Customer customer) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _bgLightGrey,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Customer Details', style: pw.TextStyle(fontSize: 10, color: _textGrey)),
              pw.SizedBox(height: 4),
              pw.Text(customer.name, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _textBlack)),
              if (customer.phone != null && customer.phone!.isNotEmpty)
                pw.Text('Phone: ${customer.phone}', style: pw.TextStyle(fontSize: 11, color: _textGrey)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildStatementSummary(double opening, double gave, double got, double finalBalance) {
    final String balanceLabel = finalBalance > 0
        ? 'You will get'
        : finalBalance < 0
            ? 'You will give'
            : 'Settled';
    
    final PdfColor balanceColor = finalBalance > 0
        ? _greenColor
        : finalBalance < 0
            ? _redColor
            : _textBlack;

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _borderGrey),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Row(
        children: [
          // Left side: Breakdown
          pw.Expanded(
            flex: 6,
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(12),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _summaryValue(
                    'Opening Balance', 
                    _currencyFormat.format(opening.abs()), 
                    opening > 0 ? _greenColor : opening < 0 ? _redColor : _textBlack,
                    subValue: opening > 0 ? 'You will get' : opening < 0 ? 'You will give' : 'Settled',
                  ),
                  _summaryValue('Total Given', _currencyFormat.format(gave), _textBlack),
                  _summaryValue('Total Received', _currencyFormat.format(got), _textBlack),
                ],
              ),
            ),
          ),
          // Right side: Final Balance Highlight
          pw.Expanded(
            flex: 4,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: finalBalance > 0 ? PdfColor.fromInt(0xFFE8F5E9) : finalBalance < 0 ? PdfColor.fromInt(0xFFFFEBEE) : _bgLightGrey,
                borderRadius: const pw.BorderRadius.horizontal(right: pw.Radius.circular(7)),
                border: pw.Border(left: pw.BorderSide(color: _borderGrey)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(
                    'Net Balance',
                    style: pw.TextStyle(fontSize: 10, color: _textGrey),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    balanceLabel == 'Settled' ? 'Settled' : '$balanceLabel ${_currencyFormat.format(finalBalance.abs())}',
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: balanceColor),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildGlobalSummary(double totalGet, double totalGive, double netBalance) {
    final String balanceLabel = netBalance > 0
        ? 'You will get in total'
        : netBalance < 0
            ? 'You will give in total'
            : 'Settled';
    
    final PdfColor balanceColor = netBalance > 0 ? _greenColor : netBalance < 0 ? _redColor : _textBlack;

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _borderGrey),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(16),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _summaryValue('Total You Will Get', _currencyFormat.format(totalGet), _greenColor),
                  _summaryValue('Total You Will Give', _currencyFormat.format(totalGive), _redColor),
                ],
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: _bgLightGrey,
                border: pw.Border(left: pw.BorderSide(color: _borderGrey)),
              ),
              child: pw.Column(
                children: [
                  pw.Text('Net Market Balance', style: pw.TextStyle(fontSize: 10, color: _textGrey)),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    balanceLabel == 'Settled' ? 'Settled' : '$balanceLabel ${_currencyFormat.format(netBalance.abs())}',
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: balanceColor),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _summaryValue(String label, String value, PdfColor valueColor, {String? subValue}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 9, color: _textGrey)),
        pw.SizedBox(height: 4),
        pw.Text(value, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: valueColor)),
        if (subValue != null)
           pw.Text(subValue, style: pw.TextStyle(fontSize: 8, color: valueColor)),
      ],
    );
  }

  static pw.Widget _buildTransactionsTable(List<TransactionModel> txns, double openingBalance) {
    if (txns.isEmpty && openingBalance == 0) {
       return pw.Padding(
         padding: const pw.EdgeInsets.symmetric(vertical: 32),
         child: pw.Center(
           child: pw.Text('No transactions in this period', style: pw.TextStyle(color: _textGrey, fontSize: 12))
         )
       );
    }

    double runningBalance = openingBalance;

    return pw.Table(
      columnWidths: {
        0: const pw.FlexColumnWidth(2.0), // Date
        1: const pw.FlexColumnWidth(3.0), // Details
        2: const pw.FlexColumnWidth(2.0), // You Gave
        3: const pw.FlexColumnWidth(2.0), // You Got
        4: const pw.FlexColumnWidth(2.5), // Balance
      },
      children: [
        // Table Header
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: _bgHeaderGrey,
            border: pw.Border(bottom: pw.BorderSide(color: _borderGrey, width: 1.5)),
          ),
          children: [
            _th('Date', align: pw.TextAlign.left),
            _th('Details', align: pw.TextAlign.left),
            _th('You Gave', align: pw.TextAlign.right),
            _th('You Got', align: pw.TextAlign.right),
            _th('Balance', align: pw.TextAlign.right),
          ],
        ),
        // Opening Balance Row (if exactly 0, can omit but good for clarity)
        if (openingBalance != 0)
          pw.TableRow(
            decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _borderGrey, width: 0.5))),
            children: [
              _td('Opening Balance', color: _textGrey),
              _td('-', color: _textGrey),
              _td('', align: pw.TextAlign.right),
              _td('', align: pw.TextAlign.right),
              _tdBalance(runningBalance),
            ],
          ),
        // Transactions
        ...txns.map((t) {
          if (t.isGot) {
             runningBalance -= (t.amountInPaise / 100.0); // You got money, balance (owe you) goes down
          } else {
             runningBalance += (t.amountInPaise / 100.0); // You gave money, balance (owe you) goes up
          }

          final gaveText = !t.isGot ? _currencyFormat.format(t.amountInPaise / 100.0) : '';
          final gotText = t.isGot ? _currencyFormat.format(t.amountInPaise / 100.0) : '';

          return pw.TableRow(
            decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _borderGrey, width: 0.5))),
            children: [
              _td(_dateFormat.format(t.date)),
              _td(t.note.isEmpty ? '-' : t.note),
              _td(gaveText, align: pw.TextAlign.right, color: _redColor),
              _td(gotText, align: pw.TextAlign.right, color: _greenColor),
              _tdBalance(runningBalance),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildCustomerListTable(List<_CustomerReportRow> rows, double totalGet, double totalGive) {
    return pw.Table(
      columnWidths: {
        0: const pw.FlexColumnWidth(3.5), // Customer Name
        1: const pw.FlexColumnWidth(2.5), // Phone
        2: const pw.FlexColumnWidth(2.0), // You Will Get
        3: const pw.FlexColumnWidth(2.0), // You Will Give
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: _bgHeaderGrey,
            border: pw.Border(bottom: pw.BorderSide(color: _borderGrey, width: 1.5)),
          ),
          children: [
            _th('Customer Name', align: pw.TextAlign.left),
            _th('Phone', align: pw.TextAlign.left),
            _th('You Will Get', align: pw.TextAlign.right),
            _th('You Will Give', align: pw.TextAlign.right),
          ],
        ),
        ...rows.map((r) {
          return pw.TableRow(
            decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _borderGrey, width: 0.5))),
            children: [
              _td(r.name, isBold: true),
              _td(r.phone, color: _textGrey),
              _td(r.willGet > 0 ? _currencyFormat.format(r.willGet) : '-', align: pw.TextAlign.right, color: _greenColor),
              _td(r.willGive > 0 ? _currencyFormat.format(r.willGive) : '-', align: pw.TextAlign.right, color: _redColor),
            ],
          );
        }),
        // Grand Totals Foot
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: _bgHeaderGrey,
            border: pw.Border(top: pw.BorderSide(color: _borderGrey, width: 1.5)),
          ),
          children: [
             _th('Grand Total', align: pw.TextAlign.left),
             _th('', align: pw.TextAlign.left),
             _th(_currencyFormat.format(totalGet), align: pw.TextAlign.right, color: _greenColor),
             _th(_currencyFormat.format(totalGive), align: pw.TextAlign.right, color: _redColor),
          ],
        )
      ],
    );
  }

  // ---- Table Cell Helpers ----
  static pw.Widget _th(String text, {pw.TextAlign align = pw.TextAlign.left, PdfColor color = _textBlack}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: pw.Text(text, textAlign: align, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: color)),
    );
  }

  static pw.Widget _td(String text, {pw.TextAlign align = pw.TextAlign.left, PdfColor color = _textBlack, bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: pw.Text(text, textAlign: align, style: pw.TextStyle(fontSize: 10, color: color, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );
  }

  static pw.Widget _tdBalance(double balance) {
    if (balance == 0) return _td('Settled', align: pw.TextAlign.right, color: _textGrey);
    
    final label = balance > 0 ? 'Get ' : 'Give ';
    final color = balance > 0 ? _greenColor : _redColor;
    
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: pw.RichText(
        textAlign: pw.TextAlign.right,
        text: pw.TextSpan(
          children: [
            pw.TextSpan(text: label, style: pw.TextStyle(fontSize: 8, color: color)),
            pw.TextSpan(text: _currencyFormat.format(balance.abs()), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildSignatureSection(String customerName) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
             pw.SizedBox(height: 40),
             pw.Container(width: 120, height: 1, color: _textBlack),
             pw.SizedBox(height: 4),
             pw.Text('Authorized Signature', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
             pw.Text('Business Owner', style: pw.TextStyle(fontSize: 9, color: _textGrey)),
          ]
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
             pw.SizedBox(height: 40),
             pw.Container(width: 120, height: 1, color: _textBlack),
             pw.SizedBox(height: 4),
             pw.Text('Customer Signature', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
             pw.Text(customerName, style: pw.TextStyle(fontSize: 9, color: _textGrey)),
          ]
        )
      ]
    );
  }

  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('This is a computer-generated report.', style: pw.TextStyle(fontSize: 8, color: _textGrey)),
        pw.SizedBox(height: 4),
        pw.Divider(color: _borderGrey, thickness: 1),
        pw.SizedBox(height: 6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Powered by SPBOOKS', style: pw.TextStyle(fontSize: 8, color: _textGrey, fontWeight: pw.FontWeight.bold)),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: pw.TextStyle(fontSize: 8, color: _textGrey)),
          ],
        ),
      ],
    );
  }

  // ---- Utils ----
  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  static String _shortDay(DateTime d) => DateFormat('ddMMyyyy').format(d);
}

class _CustomerReportRow {
  final String name;
  final String phone;
  final double willGet;
  final double willGive;

  const _CustomerReportRow({
    required this.name,
    required this.phone,
    required this.willGet,
    required this.willGive,
  });
}
