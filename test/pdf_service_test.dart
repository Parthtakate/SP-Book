import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:khata_app/models/customer.dart';
import 'package:khata_app/models/transaction.dart';
import 'package:khata_app/services/pdf_service.dart';
import 'package:khata_app/providers/reports_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'dart:io';

// Mock path provider
class MockPathProvider extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async {
    return Directory.systemTemp.path;
  }
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PathProviderPlatform.instance = MockPathProvider();
  });

  test('generateCustomerStatementPdfPath should not throw', () async {
    try {
      final customer = Customer(
        id: 'c1',
        name: 'Test Customer',
        phone: '9999999999',
        createdAt: DateTime.now(),
        contactType: ContactType.customer,
      );
      final transactions = [
        TransactionModel(
          id: 't1',
          customerId: 'c1',
          amountInPaise: 50000,
          isGot: false,
          note: 'Gave 500',
          date: DateTime.now(),
        ),
      ];

      final filePath = await PdfService.generateCustomerStatementPdfPath(
        customer: customer,
        transactions: transactions,
        balance: 500.0,
      );

      print('Success! File path: $filePath');
      expect(filePath, isNotEmpty);
    } catch (e, st) {
      print('PdfService ERROR: $e\n$st');
      fail('PdfService threw an exception: $e');
    }
  });

  test('generateAccountStatementPdf should not throw', () async {
    try {
      final statement = AccountStatement(
        monthGroups: [],
        grandTotalDebit: 0,
        grandTotalCredit: 0,
        netBalance: 0,
        balanceType: 'Cr',
        entryCount: 0,
      );
      final filePath = await PdfService.generateAccountStatementPdf(
        userName: 'SPBOOKS',
        statement: statement,
      );
      print('Success! File path: $filePath');
      expect(filePath, isNotNull);
    } catch (e, st) {
      print('PdfService ERROR: $e\n$st');
      fail('PdfService threw an exception: $e');
    }
  });
}
