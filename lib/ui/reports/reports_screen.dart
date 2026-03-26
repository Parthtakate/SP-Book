import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../providers/db_provider.dart';
import '../../services/pdf_service.dart';
import '../../providers/reports_provider.dart';
import '../../models/customer.dart';
import '../../models/transaction.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
final _dateFormat = DateFormat('dd MMM yy');

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  DateTime? _startDate;
  DateTime? _endDate;
  String _filterMode = 'ALL'; // 'ALL' or 'DATE RANGE'
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now().subtract(const Duration(days: 30)),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF1565C0),
            onPrimary: Colors.white,
            onSurface: Colors.black,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() => _startDate = picked);
    _applyDateRange();
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF1565C0),
            onPrimary: Colors.white,
            onSurface: Colors.black,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() => _endDate = picked);
    _applyDateRange();
  }

  void _applyDateRange() {
    if (_filterMode == 'DATE RANGE' && _startDate != null && _endDate != null) {
      ref.read(reportDateRangeProvider.notifier).setRange(
            DateTimeRange(start: _startDate!, end: _endDate!),
          );
    }
  }

  void _onFilterChanged(String? value) {
    if (value == null) return;
    setState(() => _filterMode = value);
    if (value == 'ALL') {
      ref.read(reportDateRangeProvider.notifier).clear();
    } else {
      _applyDateRange();
    }
  }

  Future<String?> _generatePdfFile() async {
    final dateRange = ref.read(reportDateRangeProvider);
    final report = ref.read(reportsProvider);
    final db = ref.read(dbServiceProvider);

    // Keep PDF consistent with what user sees:
    // - respect the same date range filters
    // - respect the same search filter (reportsProvider already filters it)
    final customerIds = report.perCustomer.map((e) => e.customerId).toSet();
    final customers = report.perCustomer
        .map((e) => db.customersBox.get(e.customerId))
        .whereType<Customer>()
        .toList();

    // Build map in one pass over transactions instead of N x scans.
    final txnsByCustomer = <String, List<TransactionModel>>{};
    for (final t in db.transactionsBox.values) {
      if (!customerIds.contains(t.customerId)) continue;
      txnsByCustomer.putIfAbsent(t.customerId, () => []).add(t);
    }

    return await PdfService.generateCustomerListReportPdf(
      customers: customers,
      transactionsByCustomer: txnsByCustomer,
      totalToReceive: report.totalCredit,
      totalToPay: report.totalDebit,
      dateRange: dateRange,
    );
  }

  Future<void> _downloadPdf() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Generating PDF...'),
        behavior: SnackBarBehavior.floating,
      ));

      final filePath = await _generatePdfFile();
      if (filePath == null) return;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('PDF saved successfully.'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Error generating PDF. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _sharePdf() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Generating PDF...'),
        behavior: SnackBarBehavior.floating,
      ));

      final filePath = await _generatePdfFile();
      if (filePath == null) return;

      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'SPBOOKS Customer List Report',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Error sharing PDF. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(reportsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      // ---- AppBar ----
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'View Report',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: Column(
        children: [
          // ---- Blue header area ----
          Container(
            color: const Color(0xFF1565C0),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                // Date pickers row
                Row(
                  children: [
                    Expanded(
                      child: _DatePickerBox(
                        label: 'START DATE',
                        date: _startDate,
                        onTap: _pickStartDate,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DatePickerBox(
                        label: 'END DATE',
                        date: _endDate,
                        onTap: _pickEndDate,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Search + dropdown row
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (v) =>
                              ref.read(reportSearchTextProvider.notifier).update(v),
                          style: const TextStyle(fontSize: 14),
                          decoration: const InputDecoration(
                            hintText: 'Search Entries',
                            hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                            prefixIcon: Icon(Icons.search, size: 20, color: Colors.grey),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String>(
                        value: _filterMode,
                        underline: const SizedBox(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1565C0),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'ALL', child: Text('ALL')),
                          DropdownMenuItem(
                              value: 'DATE RANGE', child: Text('DATE RANGE')),
                        ],
                        onChanged: _onFilterChanged,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ---- Net Balance Row ----
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Net Balance',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  _currency.format(report.net.abs()),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: report.net >= 0
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFFC62828),
                  ),
                ),
              ],
            ),
          ),

          // ---- Aggregate Header Row ----
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border(
                top: BorderSide(color: Colors.grey.shade200),
                bottom: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TOTAL',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${report.totalEntries} Entries',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        'YOU GAVE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _currency.format(report.totalDebit),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFC62828),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'YOU GOT',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _currency.format(report.totalCredit),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ---- Transaction List ----
          Expanded(
            child: report.perCustomer.isEmpty
                ? const _EmptyReportsState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: report.perCustomer.length,
                    itemBuilder: (ctx, i) {
                      final summary = report.perCustomer[i];
                      return _TransactionRow(summary: summary);
                    },
                  ),
          ),

          // ---- Bottom Sticky Buttons ----
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _downloadPdf,
                      icon: const Icon(Icons.picture_as_pdf, size: 18),
                      label: const Text(
                        'PDF DOWNLOAD',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _sharePdf,
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text(
                        'SHARE',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Date Picker Box
// ---------------------------------------------------------------------------

class _DatePickerBox extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;

  const _DatePickerBox({
    required this.label,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white54),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white.withValues(alpha: 0.1),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                date != null ? _dateFormat.format(date!) : label,
                style: TextStyle(
                  color: date != null ? Colors.white : Colors.white60,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Transaction Row (Global View)
// ---------------------------------------------------------------------------

class _TransactionRow extends StatelessWidget {
  final CustomerSummary summary;
  const _TransactionRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    final hasGave = summary.totalDebit > 0;
    final hasGot = summary.totalCredit > 0;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Left — Customer info
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      summary.customerName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      summary.lastTransactionDate != null
                          ? _dateFormat.format(summary.lastTransactionDate!)
                          : '${summary.transactionCount} entries',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Right — Gave column
            Container(
              width: 90,
              color: hasGave ? const Color(0xFFFFF0F0) : null,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: hasGave
                  ? Text(
                      _currency.format(summary.totalDebit),
                      style: const TextStyle(
                        color: Color(0xFFC62828),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : const SizedBox.shrink(),
            ),
            // Right — Got column
            Container(
              width: 90,
              color: hasGot ? const Color(0xFFF0FFF0) : null,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: hasGot
                  ? Text(
                      _currency.format(summary.totalCredit),
                      style: const TextStyle(
                        color: Color(0xFF2E7D32),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyReportsState extends StatelessWidget {
  const _EmptyReportsState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bar_chart_rounded, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No data yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add customers and transactions\nto see your ledger report.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
