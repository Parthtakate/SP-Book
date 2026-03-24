import 'dart:io';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/customer.dart';
import '../models/transaction.dart';

class PdfService {
  static Future<void> generateAndShareCustomerStatement({
    required Customer customer,
    required List<TransactionModel> transactions,
    required double balance,
  }) async {
    final pdf = pw.Document();
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: 'Rs.');
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

    final sortedTxs = List<TransactionModel>.from(transactions)
      ..sort((a, b) => b.date.compareTo(a.date));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Ledger Statement', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                  pw.Text(
                    'Balance: ${currencyFormat.format(balance.abs())} ${balance > 0 ? '(Get)' : balance < 0 ? '(Give)' : '(Nil)'}',
                    style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: balance > 0 ? PdfColors.green700 : balance < 0 ? PdfColors.red700 : PdfColors.black),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text('Customer: ${customer.name}', style: const pw.TextStyle(fontSize: 14)),
            if (customer.phone != null && customer.phone!.isNotEmpty)
              pw.Text('Phone: ${customer.phone}', style: const pw.TextStyle(fontSize: 12)),
            pw.Text('Date Generated: ${dateFormat.format(DateTime.now())}', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              context: context,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
              rowDecoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
              ),
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellAlignment: pw.Alignment.centerLeft,
              data: [
                ['Date', 'Details', 'You Gave', 'You Got'],
                ...sortedTxs.map((t) {
                  return [
                    dateFormat.format(t.date),
                    t.note.isEmpty ? '-' : t.note,
                    !t.isGot ? currencyFormat.format(t.amount) : '',
                    t.isGot ? currencyFormat.format(t.amount) : '',
                  ];
                }),
              ],
            ),
          ];
        },
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File('${output.path}/statement_${customer.name.replaceAll(' ', '_')}.pdf');
    await file.writeAsBytes(await pdf.save());

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Ledger Statement for ${customer.name}',
    );
  }

  /// Generates a complete report for ALL customers (user-level export).
  static Future<void> generateAndShareFullReport({
    required List<dynamic> customers,
    required Map<String, List<dynamic>> transactionsByCustomer,
    required double totalToReceive,
    required double totalToPay,
  }) async {
    final pdf = pw.Document();
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: 'Rs.');
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');
    final shortDate = DateFormat('dd MMM yyyy');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          final List<pw.Widget> widgets = [];

          // ---- Cover / Summary header
          widgets.add(
            pw.Container(
              decoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF005CEE),
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              padding: const pw.EdgeInsets.all(20),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Khata Book – Full Report',
                      style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white)),
                  pw.SizedBox(height: 6),
                  pw.Text('Generated: ${dateFormat.format(DateTime.now())}',
                      style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey300)),
                  pw.SizedBox(height: 16),
                  pw.Row(children: [
                    _summaryBadge('Total to Receive',
                        currencyFormat.format(totalToReceive), PdfColors.green300),
                    pw.SizedBox(width: 16),
                    _summaryBadge('Total to Pay',
                        currencyFormat.format(totalToPay), PdfColors.red300),
                  ]),
                ],
              ),
            ),
          );
          widgets.add(pw.SizedBox(height: 24));

          // ---- Per customer section
          for (final customer in customers) {
            final txns = transactionsByCustomer[customer.id] ?? [];
            if (txns.isEmpty) continue;

            double balance = 0;
            for (final t in txns) {
              balance += t.isGot ? -t.amount : t.amount;
            }

            widgets.add(
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                padding: const pw.EdgeInsets.all(12),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(customer.name,
                              style: pw.TextStyle(
                                  fontSize: 14, fontWeight: pw.FontWeight.bold)),
                          pw.Text(
                            balance > 0
                                ? 'Will Give: ${currencyFormat.format(balance.abs())}'
                                : balance < 0
                                    ? 'You Give: ${currencyFormat.format(balance.abs())}'
                                    : 'Settled',
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: balance > 0
                                  ? PdfColors.green700
                                  : balance < 0
                                      ? PdfColors.red700
                                      : PdfColors.grey,
                            ),
                          ),
                        ]),
                    if (customer.phone != null && customer.phone!.isNotEmpty)
                      pw.Text(customer.phone!,
                          style: const pw.TextStyle(
                              fontSize: 10, color: PdfColors.grey)),
                    pw.SizedBox(height: 8),
                    pw.TableHelper.fromTextArray(
                      context: context,
                      headerStyle: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                          fontSize: 9),
                      headerDecoration:
                          const pw.BoxDecoration(color: PdfColors.blueGrey700),
                      cellStyle: const pw.TextStyle(fontSize: 9),
                      cellAlignment: pw.Alignment.centerLeft,
                      data: [
                        ['Date', 'Note', 'You Gave', 'You Got'],
                        ...txns.map((t) => [
                              shortDate.format(t.date),
                              t.note.isEmpty ? '-' : t.note,
                              !t.isGot ? currencyFormat.format(t.amount) : '',
                              t.isGot ? currencyFormat.format(t.amount) : '',
                            ]),
                      ],
                    ),
                  ],
                ),
              ),
            );
            widgets.add(pw.SizedBox(height: 16));
          }

          return widgets;
        },
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File('${output.path}/khatabook_full_report.pdf');
    await file.writeAsBytes(await pdf.save());

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'KhataBook – Full Ledger Report',
    );
  }

  static pw.Widget _summaryBadge(String label, String amount, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.white)),
          pw.Text(amount,
              style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white)),
        ],
      ),
    );
  }
}

