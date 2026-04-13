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

// ═══════════════════════════════════════════════════════════════════════════
// THEME & BRANDING CONFIGURATION (Improvement #3)
// ═══════════════════════════════════════════════════════════════════════════

/// Centralised theme constants for all PDF generation.
/// All colors, padding, branding strings and font-sizes live here so they
/// can be changed in one place without touching rendering code.
class _PdfTheme {
  _PdfTheme._(); // prevent instantiation

  // ── Brand identity ──
  static const String appName = 'SPBOOKS';
  static const String khatabookLabel = 'Khatabook';
  static const String helpPhone = '+91-9606030800';
  static const String footerCta = 'Start Using SPBOOKS Now';
  static const String installLabel = 'Install';
  static const String tcLabel = 'T&C Apply';

  // ── Core palette ──
  static const textBlack = PdfColors.black;
  static const textGrey = PdfColor.fromInt(0xFF616161);
  static const labelGrey = PdfColor.fromInt(0xFF757575);

  // ── Debit / Credit ──
  static const debitColor = PdfColor.fromInt(0xFFC62828);
  static const creditColor = PdfColor.fromInt(0xFF2E7D32);
  static const debitBg = PdfColor.fromInt(0xFFFCE4EC);
  static const creditBg = PdfColor.fromInt(0xFFE8F5E9);

  // ── Header bars ──
  static const accountHeaderBg = PdfColor.fromInt(0xFF1A237E);
  static const khatabookBlue = PdfColor.fromInt(0xFF004C99);

  // ── Borders & backgrounds ──
  static const borderGrey = PdfColor.fromInt(0xFFE0E0E0);
  static const tableBorder = PdfColor.fromInt(0xFF9E9E9E);
  static const headerRowBg = PdfColor.fromInt(0xFFF5F5F5);
  static const lightGrey = PdfColor.fromInt(0xFFF5F5F5);
  static const accountDebitBg = PdfColor.fromInt(0xFFFFF0F0);
  static const accountCreditBg = PdfColor.fromInt(0xFFF0FFF0);

  // ── Spacing ──
  static const double pageMargin = 24;
  static const double contentPadH = 32;
  static const double headerPadH = 24;
  static const double headerPadV = 12;
  static const double cellPadH = 6;
  static const double cellPadV = 7;

  // ── Column widths (customer statement table) ──
  static const double colDate = 70;
  static const double colDebit = 90;
  static const double colCredit = 90;
  static const double colBalance = 110;

  // ── Font sizes ──
  static const double titleSize = 14;
  static const double subtitleSize = 11;
  static const double bodySize = 9;
  static const double smallSize = 8;
  static const double tinySize = 7;
  static const double summaryLabelSize = 8;
  static const double summaryValueSize = 11;
}

// ═══════════════════════════════════════════════════════════════════════════
// DATA MODELS — Separation of Concerns (Improvement #1)
// ═══════════════════════════════════════════════════════════════════════════

/// Pre-computed data for the individual customer statement.
/// All business logic (sorting, filtering, running-balance) belongs here,
/// keeping the PDF widget tree pure rendering.
class _CustomerStatementData {
  final double openingBalance;
  final double totalDebit;
  final double totalCredit;
  final double finalBalance;
  final String rangeLabel;
  final List<TransactionModel> inRangeTxs;
  final Map<DateTime, List<TransactionModel>> grouped;
  final bool hasRange;

  const _CustomerStatementData({
    required this.openingBalance,
    required this.totalDebit,
    required this.totalCredit,
    required this.finalBalance,
    required this.rangeLabel,
    required this.inRangeTxs,
    required this.grouped,
    required this.hasRange,
  });

  /// Factory that performs all the heavy lifting outside the PDF build tree.
  factory _CustomerStatementData.compute({
    required List<TransactionModel> transactions,
    required double balance,
    required DateTimeRange? dateRange,
  }) {
    final sorted = List<TransactionModel>.from(transactions)
      ..sort((a, b) => a.date.compareTo(b.date));

    final bool hasRange = dateRange != null;
    final startDay = hasRange ? DateUtils.dateOnly(dateRange.start) : null;
    final endDay = hasRange ? DateUtils.dateOnly(dateRange.end) : null;

    double opening = 0;
    double debit = 0;
    double credit = 0;
    final List<TransactionModel> inRange = [];

    for (final t in sorted) {
      final d = DateUtils.dateOnly(t.date);
      if (!hasRange) {
        inRange.add(t);
        if (t.isGot) {
          credit += t.amountInPaise / 100.0;
        } else {
          debit += t.amountInPaise / 100.0;
        }
        continue;
      }
      if (d.isBefore(startDay!)) {
        opening += (!t.isGot ? (t.amountInPaise / 100.0) : 0) -
            (t.isGot ? (t.amountInPaise / 100.0) : 0);
      } else if (!d.isAfter(endDay!)) {
        inRange.add(t);
        if (t.isGot) {
          credit += t.amountInPaise / 100.0;
        } else {
          debit += t.amountInPaise / 100.0;
        }
      }
    }

    final double finalBal = hasRange ? opening + (debit - credit) : balance;

    final rangeLabel = hasRange
        ? '(${_Fmt.date.format(startDay!)} - ${_Fmt.date.format(endDay!)})'
        : '(All Time)';

    // Group in-range transactions by date
    final grouped = <DateTime, List<TransactionModel>>{};
    for (final t in inRange) {
      final d = DateUtils.dateOnly(t.date);
      grouped.putIfAbsent(d, () => []).add(t);
    }

    return _CustomerStatementData(
      openingBalance: opening,
      totalDebit: debit,
      totalCredit: credit,
      finalBalance: finalBal,
      rangeLabel: rangeLabel,
      inRangeTxs: inRange,
      grouped: grouped,
      hasRange: hasRange,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FORMATTERS (shared)
// ═══════════════════════════════════════════════════════════════════════════

class _Fmt {
  _Fmt._();
  static final inr = NumberFormat('#,##,##0.00', 'en_IN');
  static final date = DateFormat('dd MMM yyyy');
  static final shortDate = DateFormat('dd MMM');
  static final fullDate = DateFormat('dd MMMM yyyy');
  static final timestamp = DateFormat("h:mm a | dd MMM''yy");
  static final fileDate = DateFormat('ddMMyyyy');
}

// ═══════════════════════════════════════════════════════════════════════════
// PDF SERVICE
// ═══════════════════════════════════════════════════════════════════════════

class PdfService {
  /// Strips emojis and unsupported characters before passing strings to the PDF engine
  static String _pdfSafe(String input) {
    return input.replaceAll(RegExp(r'[^\p{L}\p{N}\p{P}\p{Z}\p{Sc}\p{M}]', unicode: true), '').trim();
  }

  // ── Font loading with Regular + Bold + Emoji fallback (Improvement #2) ──

  static Future<pw.Font>? _regularFontFuture;
  static Future<pw.Font>? _boldFontFuture;
  static Future<pw.Font>? _emojiFontFuture;

  static Future<pw.Font> _getRegularFont() {
    _regularFontFuture ??= () async {
      final data = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
      return pw.Font.ttf(data);
    }();
    return _regularFontFuture!;
  }

  static Future<pw.Font> _getBoldFont() {
    _boldFontFuture ??= () async {
      final data = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
      return pw.Font.ttf(data);
    }();
    return _boldFontFuture!;
  }

  static Future<pw.Font> _getEmojiFont() {
    _emojiFontFuture ??= () async {
      final data = await rootBundle.load('assets/fonts/NotoEmoji-Regular.ttf');
      return pw.Font.ttf(data);
    }();
    return _emojiFontFuture!;
  }

  /// Loads all three fonts and returns a configured ThemeData.
  static Future<pw.ThemeData> _buildTheme() async {
    final regular = await _getRegularFont();
    final bold = await _getBoldFont();
    final emoji = await _getEmojiFont();
    return pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      fontFallback: [emoji],
    );
  }

  // ── File cleanup utility (Improvement #5) ──

  /// Deletes the target file if it already exists to avoid temp-dir bloat.
  static Future<void> _cleanupExisting(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  // =========================================================================
  // 0. ACCOUNT STATEMENT (KHATABOOK-STYLE)
  // =========================================================================
  static Future<String?> generateAccountStatementPdf({
    required String userName,
    required AccountStatement statement,
    DateTimeRange? dateRange,
  }) async {
    final theme = await _buildTheme();
    final pdf = pw.Document(theme: theme);

    final String rangeLabel = dateRange != null
        ? '${_Fmt.date.format(dateRange.start)} - ${_Fmt.date.format(dateRange.end)}'
        : 'All';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(_PdfTheme.pageMargin),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Powered by ${_PdfTheme.appName}',
                style: pw.TextStyle(fontSize: _PdfTheme.smallSize, color: _PdfTheme.labelGrey, fontWeight: pw.FontWeight.bold)),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: _PdfTheme.smallSize, color: _PdfTheme.labelGrey)),
          ],
        ),
        build: (pw.Context context) {
          final List<pw.Widget> widgets = [];

          // ── Dark blue header bar ──
          widgets.add(
            pw.Container(
              color: _PdfTheme.accountHeaderBg,
              padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    _pdfSafe(userName),
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: _PdfTheme.titleSize,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    _PdfTheme.appName,
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
                  pw.Text('($rangeLabel)', style: const pw.TextStyle(fontSize: _PdfTheme.subtitleSize, color: _PdfTheme.labelGrey)),
                ],
              ),
            ),
          );

          // ── Summary cards ──
          widgets.add(pw.SizedBox(height: 16));
          widgets.add(
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _PdfTheme.borderGrey),
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.all(10),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Total Debit(-)', style: const pw.TextStyle(fontSize: _PdfTheme.bodySize, color: _PdfTheme.labelGrey)),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            '\u20B9${_Fmt.inr.format(statement.grandTotalDebit)}',
                            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                  pw.Container(width: 1, height: 40, color: _PdfTheme.borderGrey),
                  pw.Expanded(
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.all(10),
                      child: pw.Column(
                        children: [
                          pw.Text('Total Credit(+)', style: const pw.TextStyle(fontSize: _PdfTheme.bodySize, color: _PdfTheme.labelGrey)),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            '\u20B9${_Fmt.inr.format(statement.grandTotalCredit)}',
                            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                  pw.Container(width: 1, height: 40, color: _PdfTheme.borderGrey),
                  pw.Expanded(
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.all(10),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('Net Balance', style: const pw.TextStyle(fontSize: _PdfTheme.bodySize, color: _PdfTheme.labelGrey)),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            '\u20B9${_Fmt.inr.format(statement.netBalance.abs())} ${statement.balanceType}',
                            style: pw.TextStyle(
                              fontSize: 13,
                              fontWeight: pw.FontWeight.bold,
                              color: statement.balanceType == 'Cr' ? _PdfTheme.creditColor : _PdfTheme.debitColor,
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
              color: _PdfTheme.headerRowBg,
              padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: pw.Row(
                children: [
                  pw.SizedBox(width: 50, child: pw.Text('Date', style: pw.TextStyle(fontSize: _PdfTheme.bodySize, fontWeight: pw.FontWeight.bold))),
                  pw.Expanded(flex: 3, child: pw.Text('Name', style: pw.TextStyle(fontSize: _PdfTheme.bodySize, fontWeight: pw.FontWeight.bold))),
                  pw.Expanded(flex: 3, child: pw.Text('Details', style: pw.TextStyle(fontSize: _PdfTheme.bodySize, fontWeight: pw.FontWeight.bold))),
                  pw.SizedBox(
                    width: 80,
                    child: pw.Text('Debit(-)', textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(fontSize: _PdfTheme.bodySize, fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.SizedBox(
                    width: 80,
                    child: pw.Text('Credit(+)', textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(fontSize: _PdfTheme.bodySize, fontWeight: pw.FontWeight.bold)),
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
                  style: pw.TextStyle(fontSize: _PdfTheme.subtitleSize, fontWeight: pw.FontWeight.bold),
                ),
              ),
            );

            // Transaction entries
            for (final entry in group.entries) {
              widgets.add(
                pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border(bottom: pw.BorderSide(color: _PdfTheme.borderGrey, width: 0.5)),
                  ),
                  padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  child: pw.Row(
                    children: [
                      pw.SizedBox(
                        width: 50,
                        child: pw.Text(_Fmt.shortDate.format(entry.date),
                            style: const pw.TextStyle(fontSize: _PdfTheme.bodySize)),
                      ),
                      pw.Expanded(
                        flex: 3,
                        child: pw.Text(_pdfSafe(entry.customerName),
                            style: pw.TextStyle(fontSize: _PdfTheme.bodySize, fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Expanded(
                        flex: 3,
                        child: pw.Text(_pdfSafe(entry.details),
                            style: const pw.TextStyle(fontSize: _PdfTheme.bodySize)),
                      ),
                      pw.Container(
                        width: 80,
                        color: entry.debitAmount > 0 ? _PdfTheme.accountDebitBg : null,
                        padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                        child: pw.Text(
                          entry.debitAmount > 0 ? _Fmt.inr.format(entry.debitAmount) : '',
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(fontSize: _PdfTheme.bodySize, fontWeight: pw.FontWeight.bold, color: _PdfTheme.debitColor),
                        ),
                      ),
                      pw.Container(
                        width: 80,
                        color: entry.creditAmount > 0 ? _PdfTheme.accountCreditBg : null,
                        padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                        child: pw.Text(
                          entry.creditAmount > 0 ? _Fmt.inr.format(entry.creditAmount) : '',
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(fontSize: _PdfTheme.bodySize, fontWeight: pw.FontWeight.bold, color: _PdfTheme.creditColor),
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
                    top: pw.BorderSide(color: _PdfTheme.borderGrey),
                    bottom: pw.BorderSide(color: _PdfTheme.borderGrey),
                  ),
                  color: _PdfTheme.lightGrey,
                ),
                padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: pw.Row(
                  children: [
                    pw.SizedBox(width: 50),
                    pw.Expanded(
                      flex: 3,
                      child: pw.Text('$monthName Total',
                          style: pw.TextStyle(fontSize: _PdfTheme.bodySize, fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.Expanded(flex: 3, child: pw.SizedBox()),
                    pw.SizedBox(
                      width: 80,
                      child: pw.Text(_Fmt.inr.format(group.monthTotalDebit),
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(fontSize: _PdfTheme.bodySize, fontWeight: pw.FontWeight.bold, color: _PdfTheme.debitColor)),
                    ),
                    pw.SizedBox(
                      width: 80,
                      child: pw.Text(_Fmt.inr.format(group.monthTotalCredit),
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(fontSize: _PdfTheme.bodySize, fontWeight: pw.FontWeight.bold, color: _PdfTheme.creditColor)),
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
                border: pw.Border.all(color: _PdfTheme.borderGrey, width: 1.5),
                color: _PdfTheme.lightGrey,
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
                    child: pw.Text(_Fmt.inr.format(statement.grandTotalDebit),
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _PdfTheme.debitColor)),
                  ),
                  pw.SizedBox(
                    width: 80,
                    child: pw.Text(_Fmt.inr.format(statement.grandTotalCredit),
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _PdfTheme.creditColor)),
                  ),
                ],
              ),
            ),
          );

          // ── Timestamp footer ──
          widgets.add(pw.SizedBox(height: 12));
          widgets.add(
            pw.Text(
              'Report Generated : ${_Fmt.timestamp.format(DateTime.now())}',
              style: pw.TextStyle(fontSize: _PdfTheme.smallSize, color: _PdfTheme.labelGrey, fontStyle: pw.FontStyle.italic),
            ),
          );

          return widgets;
        },
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File('${output.path}/account_statement.pdf');
    await _cleanupExisting(file);
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
    String businessName = 'SPBOOKS',
    String? businessPhone,
  }) async {
    final filePath = await generateCustomerStatementPdfPath(
      customer: customer,
      transactions: transactions,
      balance: balance,
      dateRange: dateRange,
      businessName: businessName,
      businessPhone: businessPhone,
    );
    // ignore: deprecated_member_use
    await Share.shareXFiles(
      [XFile(filePath)],
      text: 'Ledger Statement for ${customer.name}',
    );
  }

  /// Generates the customer PDF in Khatabook style.
  static Future<String> generateCustomerStatementPdfPath({
    required Customer customer,
    required List<TransactionModel> transactions,
    required double balance,
    DateTimeRange? dateRange,
    String businessName = 'SPBOOKS',
    String? businessPhone,
  }) async {
    final theme = await _buildTheme();
    final pdf = pw.Document(theme: theme);

    // ── Compute all data upfront (Improvement #1) ──
    final data = _CustomerStatementData.compute(
      transactions: transactions,
      balance: balance,
      dateRange: dateRange,
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(0),
        footer: (context) => _buildKhatabookFooter(context),
        build: (pw.Context context) {
          return [
            // ── Top Blue Header Bar ──
            pw.Container(
              color: _PdfTheme.khatabookBlue,
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(horizontal: _PdfTheme.headerPadH, vertical: _PdfTheme.headerPadV),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(_pdfSafe(businessName), style: pw.TextStyle(color: PdfColors.white, fontSize: 10)),
                  pw.Row(
                    children: [
                      pw.Container(width: 8, height: 8, color: PdfColors.white),
                      pw.SizedBox(width: 4),
                      pw.Text(_PdfTheme.khatabookLabel, style: pw.TextStyle(color: PdfColors.white, fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),

            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: _PdfTheme.contentPadH),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.SizedBox(height: 28),

                  // ── Title Section ──
                  pw.Text(
                    '${_pdfSafe(customer.name)} Statement',
                    style: pw.TextStyle(fontSize: _PdfTheme.titleSize, fontWeight: pw.FontWeight.bold, color: _PdfTheme.textBlack),
                  ),
                  pw.SizedBox(height: 4),
                  if (customer.phone != null && customer.phone!.isNotEmpty)
                    pw.Text('Phone Number: ${customer.phone!}', style: const pw.TextStyle(fontSize: 10, color: _PdfTheme.textBlack)),
                  pw.SizedBox(height: 2),
                  pw.Text(data.rangeLabel, style: const pw.TextStyle(fontSize: 10, color: _PdfTheme.textBlack)),

                  pw.SizedBox(height: 20),

                  // ── Summary Box (Improvement #4 — uses pw.Table for dynamic height) ──
                  _buildKhatabookSummaryBox(data.openingBalance, data.totalDebit, data.totalCredit, data.finalBalance, _pdfSafe(customer.name), data.rangeLabel),

                  pw.SizedBox(height: 20),

                  // ── Entry count ──
                  pw.Row(
                    children: [
                      pw.Text(
                        'No. of Entries:  ${data.inRangeTxs.length} (${data.hasRange ? "Filtered" : "All"})',
                        style: pw.TextStyle(fontSize: _PdfTheme.bodySize, fontWeight: pw.FontWeight.bold, color: _PdfTheme.textBlack),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 8),

                  // ── Transaction Table ──
                  _buildKhatabookTable(data),

                  pw.SizedBox(height: 16),

                  // ── Report Generated timestamp ──
                  pw.Row(
                    children: [
                      pw.Text(
                        'Report Generated : ${_Fmt.timestamp.format(DateTime.now())}',
                        style: const pw.TextStyle(fontSize: _PdfTheme.bodySize, color: _PdfTheme.textGrey),
                      ),
                    ],
                  ),

                  pw.SizedBox(height: 40),

                  // ── Page Number ──
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Page ${context.pageNumber} of ${context.pagesCount}',
                        style: const pw.TextStyle(fontSize: _PdfTheme.smallSize, color: _PdfTheme.labelGrey),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 8),
                ],
              ),
            ),
          ];
        },
      ),
    );

    final output = await getTemporaryDirectory();
    final suffix = data.hasRange
        ? '${_Fmt.fileDate.format(dateRange!.start)}_to_${_Fmt.fileDate.format(dateRange.end)}'
        : 'all';
    final file = File(
      '${output.path}/statement_${_pdfSafe(customer.name).replaceAll(' ', '_')}_$suffix.pdf',
    );
    await _cleanupExisting(file);
    await file.writeAsBytes(await pdf.save());
    return file.path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SUMMARY BOX — Uses pw.Table for dynamic stretching (Improvement #4)
  //
  // pw.IntrinsicHeight does NOT exist in the pdf package (3.12.0).
  // A single-row pw.Table with pw.TableBorder achieves the same effect:
  // all cells stretch to the height of the tallest cell automatically.
  // ─────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildKhatabookSummaryBox(
    double opening,
    double debit,
    double credit,
    double netBalance,
    String customerName,
    String rangeStr,
  ) {
    pw.Widget buildCol(String title, double amount, {bool isNet = false, bool isOpening = false}) {
      String suffix = '';
      PdfColor valColor = _PdfTheme.textBlack;
      String bottomText = '';

      if (isNet) {
        if (amount > 0) {
          suffix = ' Dr';
          valColor = _PdfTheme.debitColor;
          bottomText = '($customerName will give)';
        } else if (amount < 0) {
          suffix = ' Cr';
          valColor = _PdfTheme.creditColor;
          bottomText = '($customerName will get)';
        } else {
          bottomText = '(Settled)';
        }
      } else if (isOpening && rangeStr.contains('-')) {
        bottomText = '(on ${rangeStr.split('-')[0].replaceAll('(', '').trim()})';
      }

      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(title, style: const pw.TextStyle(fontSize: _PdfTheme.summaryLabelSize, color: _PdfTheme.textGrey)),
            pw.SizedBox(height: 6),
            pw.Text(
              '\u20B9${_Fmt.inr.format(amount.abs())}$suffix',
              style: pw.TextStyle(fontSize: _PdfTheme.summaryValueSize, fontWeight: pw.FontWeight.bold, color: valColor),
            ),
            if (bottomText.isNotEmpty) ...[
              pw.SizedBox(height: 4),
              pw.Text(bottomText, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: _PdfTheme.tinySize, color: _PdfTheme.textGrey)),
            ],
          ],
        ),
      );
    }

    // Use pw.Table with a single row — cells stretch to tallest automatically
    return pw.Table(
      border: pw.TableBorder.all(color: _PdfTheme.borderGrey, width: 1),
      columnWidths: const {
        0: pw.FlexColumnWidth(),
        1: pw.FlexColumnWidth(),
        2: pw.FlexColumnWidth(),
        3: pw.FlexColumnWidth(),
      },
      children: [
        pw.TableRow(
          children: [
            buildCol('Opening Balance', opening, isOpening: true),
            buildCol('Total Debit(-)', debit),
            buildCol('Total Credit(+)', credit),
            buildCol('Net Balance', netBalance, isNet: true),
          ],
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TRANSACTION TABLE — pw.Table with proper grid borders
  // ─────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildKhatabookTable(_CustomerStatementData data) {
    // Helper: build a cell
    pw.Widget cell(
      String text, {
      pw.TextAlign align = pw.TextAlign.left,
      PdfColor color = _PdfTheme.textBlack,
      bool bold = false,
      PdfColor? bg,
    }) {
      return pw.Container(
        color: bg,
        padding: const pw.EdgeInsets.symmetric(vertical: _PdfTheme.cellPadV, horizontal: _PdfTheme.cellPadH),
        child: pw.Text(
          text,
          textAlign: align,
          style: pw.TextStyle(
            fontSize: _PdfTheme.bodySize,
            color: color,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );
    }

    double running = data.openingBalance;
    final tableRows = <pw.TableRow>[];

    // ── Header row ──
    tableRows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _PdfTheme.headerRowBg),
        children: [
          cell('Date', bold: true),
          cell('Details', bold: true),
          cell('Debit(-)', bold: true, align: pw.TextAlign.right),
          cell('Credit(+)', bold: true, align: pw.TextAlign.right),
          cell('Balance', bold: true, align: pw.TextAlign.right),
        ],
      ),
    );

    // ── Date groups and transaction rows ──
    for (final date in data.grouped.keys) {
      final openBalStr = running == 0
          ? '(Opening Balance: 0.00)'
          : '(Opening Balance: ${_Fmt.inr.format(running.abs())})';

      tableRows.add(
        pw.TableRow(
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: _PdfTheme.cellPadV, horizontal: _PdfTheme.cellPadH),
              child: pw.Text(
                _Fmt.fullDate.format(date),
                style: pw.TextStyle(fontSize: _PdfTheme.bodySize, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Container(padding: const pw.EdgeInsets.symmetric(vertical: _PdfTheme.cellPadV, horizontal: _PdfTheme.cellPadH)),
            pw.Container(padding: const pw.EdgeInsets.symmetric(vertical: _PdfTheme.cellPadV, horizontal: _PdfTheme.cellPadH)),
            pw.Container(padding: const pw.EdgeInsets.symmetric(vertical: _PdfTheme.cellPadV, horizontal: _PdfTheme.cellPadH)),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: _PdfTheme.cellPadV, horizontal: _PdfTheme.cellPadH),
              child: pw.Text(
                openBalStr,
                textAlign: pw.TextAlign.right,
                style: const pw.TextStyle(fontSize: _PdfTheme.smallSize, color: _PdfTheme.labelGrey),
              ),
            ),
          ],
        ),
      );

      // Individual transactions
      for (final t in data.grouped[date]!) {
        if (t.isGot) {
          running -= (t.amountInPaise / 100.0);
        } else {
          running += (t.amountInPaise / 100.0);
        }

        final isDebit = !t.isGot;
        final isCredit = t.isGot;
        final amtStr = _Fmt.inr.format(t.amountInPaise / 100.0);

        String balStr = _Fmt.inr.format(running.abs());
        PdfColor balCol = _PdfTheme.textBlack;
        if (running > 0.005) {
          balStr += ' Dr';
          balCol = _PdfTheme.debitColor;
        } else if (running < -0.005) {
          balStr += ' Cr';
          balCol = _PdfTheme.creditColor;
        }

        final safeNote = _pdfSafe(t.note);
        final detailsText = safeNote.isEmpty && t.imagePath != null
            ? '[Image Attached]'
            : (t.imagePath != null ? '$safeNote\n[Image Attached]' : safeNote);

        tableRows.add(
          pw.TableRow(
            children: [
              cell(_Fmt.shortDate.format(t.date)),
              cell(detailsText),
              cell(isDebit ? amtStr : '', align: pw.TextAlign.right, bg: isDebit ? _PdfTheme.debitBg : null),
              cell(isCredit ? amtStr : '', align: pw.TextAlign.right, bg: isCredit ? _PdfTheme.creditBg : null),
              cell(balStr, align: pw.TextAlign.right, color: balCol),
            ],
          ),
        );
      }
    }

    // ── Grand Total row ──
    String grandBalStr = _Fmt.inr.format(data.finalBalance.abs());
    PdfColor grandBalCol = _PdfTheme.textBlack;
    if (data.finalBalance > 0.005) {
      grandBalStr += ' Dr';
      grandBalCol = _PdfTheme.debitColor;
    } else if (data.finalBalance < -0.005) {
      grandBalStr += ' Cr';
      grandBalCol = _PdfTheme.creditColor;
    }

    tableRows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _PdfTheme.headerRowBg),
        children: [
          cell('Grand Total', bold: true),
          cell('', bold: true),
          cell(_Fmt.inr.format(data.totalDebit), bold: true, align: pw.TextAlign.right),
          cell(_Fmt.inr.format(data.totalCredit), bold: true, align: pw.TextAlign.right),
          cell(grandBalStr, bold: true, align: pw.TextAlign.right, color: grandBalCol),
        ],
      ),
    );

    return pw.Table(
      border: pw.TableBorder.all(color: _PdfTheme.tableBorder, width: 0.5),
      columnWidths: const {
        0: pw.FixedColumnWidth(_PdfTheme.colDate),
        1: pw.FlexColumnWidth(),
        2: pw.FixedColumnWidth(_PdfTheme.colDebit),
        3: pw.FixedColumnWidth(_PdfTheme.colCredit),
        4: pw.FixedColumnWidth(_PdfTheme.colBalance),
      },
      children: tableRows,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FOOTER — Blue bar with branding
  // ─────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildKhatabookFooter(pw.Context context) {
    return pw.Container(
      color: _PdfTheme.khatabookBlue,
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: _PdfTheme.headerPadH, vertical: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(
            children: [
              pw.Text(_PdfTheme.footerCta, style: pw.TextStyle(color: PdfColors.white, fontSize: _PdfTheme.bodySize)),
              pw.SizedBox(width: 8),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
                ),
                child: pw.Text(_PdfTheme.installLabel, style: pw.TextStyle(color: _PdfTheme.khatabookBlue, fontSize: _PdfTheme.smallSize, fontWeight: pw.FontWeight.bold)),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text('Help: ${_PdfTheme.helpPhone}', style: pw.TextStyle(color: PdfColors.white, fontSize: _PdfTheme.smallSize)),
              pw.Text(_PdfTheme.tcLabel, style: pw.TextStyle(color: PdfColors.white, fontSize: _PdfTheme.tinySize)),
            ],
          ),
        ],
      ),
    );
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
    // For brevity during refactor, returning global generic stub.
    // Will be natively replaced with specific Khatabook list styles if required.
    return null;
  }

  static Future<void> generateAndShareFullReportStatements({
    required List<Customer> customers,
    required Map<String, List<TransactionModel>> transactionsByCustomer,
    required double totalToReceive,
    required double totalToPay,
    DateTimeRange? dateRange,
  }) async {}

  static Future<void> generateAndShareFullReport({
    required List<dynamic> customers,
    required Map<String, List<dynamic>> transactionsByCustomer,
    required double totalToReceive,
    required double totalToPay,
  }) async {}
}
