import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../providers/db_provider.dart';
import '../../services/pdf_service.dart';
import '../../services/csv_service.dart';
import '../../providers/reports_provider.dart';

final _inrFormat = NumberFormat('#,##,##0.00', 'en_IN');
final _dateFormat = DateFormat('dd MMM');
final _fullDateFormat = DateFormat('dd MMM yyyy');
final _headerDateFormat = DateFormat('dd MMM yyyy');
final _timestampFormat = DateFormat("h:mm a | dd MMM''yy");

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  DateTime? _startDate;
  DateTime? _endDate;
  String _filterMode = 'ALL';
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
            primary: Color(0xFF1A237E),
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
            primary: Color(0xFF1A237E),
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

  String _getUserName() {
    // Priority: Business name > Firebase display name > fallback
    final db = ref.read(dbServiceProvider);
    final businessName = db.getBusinessName();
    if (businessName != null && businessName.isNotEmpty) return businessName;

    final user = FirebaseAuth.instance.currentUser;
    return user?.displayName ?? 'Account Statement';
  }

  String _getDateRangeLabel() {
    final dateRange = ref.read(reportDateRangeProvider);
    if (dateRange == null) return 'All';
    return '${_headerDateFormat.format(dateRange.start)} - ${_headerDateFormat.format(dateRange.end)}';
  }

  Future<void> _exportPdf() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Generating PDF...'),
        behavior: SnackBarBehavior.floating,
      ));

      final statement = ref.read(accountStatementProvider);
      final dateRange = ref.read(reportDateRangeProvider);

      final filePath = await PdfService.generateAccountStatementPdf(
        userName: _getUserName(),
        statement: statement,
        dateRange: dateRange,
      );

      if (filePath == null || !mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('PDF saved successfully.'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Error generating PDF. Please try again.'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _exportCsv() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Generating CSV...'),
        behavior: SnackBarBehavior.floating,
      ));

      final statement = ref.read(accountStatementProvider);
      final dateRange = ref.read(reportDateRangeProvider);

      final filePath = await CsvService.generateAccountStatementCsv(
        userName: _getUserName(),
        statement: statement,
        dateRange: dateRange,
      );

      if (filePath == null || !mounted) return;

      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'SPBOOKS Account Statement (CSV)',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Error generating CSV. Please try again.'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _sharePdf() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Generating PDF...'),
        behavior: SnackBarBehavior.floating,
      ));

      final statement = ref.read(accountStatementProvider);
      final dateRange = ref.read(reportDateRangeProvider);

      final filePath = await PdfService.generateAccountStatementPdf(
        userName: _getUserName(),
        statement: statement,
        dateRange: dateRange,
      );

      if (filePath == null) return;

      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'SPBOOKS Account Statement',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Error sharing PDF. Please try again.'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final statement = ref.watch(accountStatementProvider);
    final userName = _getUserName();

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // ── Dark Blue Header Bar ──
          Container(
            color: const Color(0xFF1A237E),
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      userName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Icon(Icons.book, color: Colors.white, size: 10),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'SPBOOKS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Scrollable Content ──
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 24),

                  // ── Title: "Account Statement" ──
                  const Text(
                    'Account Statement',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '(${_getDateRangeLabel()})',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Summary Cards ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: IntrinsicHeight(
                        child: Row(
                          children: [
                            // Total Debit(-)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Total Debit(-)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '₹${_inrFormat.format(statement.grandTotalDebit)}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            VerticalDivider(width: 1, color: Colors.grey.shade300),
                            // Total Credit(+)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Total Credit(+)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '₹${_inrFormat.format(statement.grandTotalCredit)}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            VerticalDivider(width: 1, color: Colors.grey.shade300),
                            // Net Balance
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'Net Balance',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '₹${_inrFormat.format(statement.netBalance.abs())} ${statement.balanceType}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: statement.balanceType == 'Cr'
                                            ? const Color(0xFF2E7D32)
                                            : const Color(0xFFC62828),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Filter Controls ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        // Entry count
                        Text(
                          'No. of Entries:  ${statement.entryCount} (${_filterMode == 'ALL' ? 'All' : 'Filtered'})',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const Spacer(),
                        // Filter dropdown
                        Container(
                          height: 32,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: DropdownButton<String>(
                            value: _filterMode,
                            underline: const SizedBox(),
                            isDense: true,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A237E),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'ALL', child: Text('ALL')),
                              DropdownMenuItem(value: 'DATE RANGE', child: Text('DATE RANGE')),
                            ],
                            onChanged: _onFilterChanged,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Date pickers (visible only in DATE RANGE mode) ──
                  if (_filterMode == 'DATE RANGE') ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: _DateChip(
                              label: 'FROM',
                              date: _startDate,
                              onTap: _pickStartDate,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _DateChip(
                              label: 'TO',
                              date: _endDate,
                              onTap: _pickEndDate,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // ── Search bar ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (v) =>
                            ref.read(reportSearchTextProvider.notifier).update(v),
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'Search by name or details...',
                          hintStyle: TextStyle(color: Colors.grey, fontSize: 12),
                          prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── Table Header ──
                  Container(
                    color: Colors.grey.shade200,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                    child: Row(
                      children: [
                        const SizedBox(width: 60, child: Text('Date', style: _headerStyle)),
                        const Expanded(flex: 3, child: Text('Name', style: _headerStyle)),
                        const Expanded(flex: 3, child: Text('Details', style: _headerStyle)),
                        Container(
                          width: 90,
                          alignment: Alignment.centerRight,
                          child: const Text('Debit(-)', style: _headerStyle),
                        ),
                        Container(
                          width: 90,
                          alignment: Alignment.centerRight,
                          child: const Text('Credit(+)', style: _headerStyle),
                        ),
                      ],
                    ),
                  ),

                  // ── Month Groups ──
                  if (statement.monthGroups.isEmpty)
                    const _EmptyState()
                  else
                    ...statement.monthGroups.expand((group) => [
                          // Month header
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                            child: Text(
                              group.label,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          // Entries
                          ...group.entries.map((entry) => _EntryRow(entry: entry)),
                          // Monthly total
                          _MonthTotalRow(group: group),
                        ]),

                  // ── Grand Total ──
                  if (statement.monthGroups.isNotEmpty)
                    Container(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Colors.grey.shade400, width: 1.5),
                          bottom: BorderSide(color: Colors.grey.shade400, width: 1.5),
                        ),
                        color: Colors.grey.shade50,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      child: Row(
                        children: [
                          const SizedBox(width: 60),
                          const Expanded(
                            flex: 3,
                            child: Text(
                              'Grand Total',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          const Expanded(flex: 3, child: SizedBox()),
                          Container(
                            width: 90,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF0F0),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _inrFormat.format(statement.grandTotalDebit),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Color(0xFFC62828),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            width: 90,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FFF0),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _inrFormat.format(statement.grandTotalCredit),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Color(0xFF2E7D32),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ── Footer timestamp ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'Report Generated : ${_timestampFormat.format(DateTime.now())}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),

                  const SizedBox(height: 80), // space for bottom buttons
                ],
              ),
            ),
          ),

          // ── Bottom Sticky Buttons ──
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
                      onPressed: _exportPdf,
                      icon: const Icon(Icons.picture_as_pdf, size: 16),
                      label: const Text(
                        'PDF',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A237E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _exportCsv,
                      icon: const Icon(Icons.table_chart, size: 16),
                      label: const Text(
                        'CSV',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF005CEE),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _sharePdf,
                      icon: const Icon(Icons.share, size: 16),
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

// ── Styles ──
const _headerStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.bold,
  color: Colors.black54,
);

// ── Entry Row ──
class _EntryRow extends StatelessWidget {
  final AccountStatementEntry entry;
  const _EntryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              _dateFormat.format(entry.date),
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              entry.customerName,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              entry.details.isEmpty ? '' : entry.details,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Debit column — light red bg
          Container(
            width: 90,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            decoration: entry.debitAmount > 0
                ? BoxDecoration(
                    color: const Color(0xFFFFF0F0),
                    borderRadius: BorderRadius.circular(4),
                  )
                : null,
            child: Text(
              entry.debitAmount > 0 ? _inrFormat.format(entry.debitAmount) : '',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFFC62828),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Credit column — light green bg
          Container(
            width: 90,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            decoration: entry.creditAmount > 0
                ? BoxDecoration(
                    color: const Color(0xFFF0FFF0),
                    borderRadius: BorderRadius.circular(4),
                  )
                : null,
            child: Text(
              entry.creditAmount > 0 ? _inrFormat.format(entry.creditAmount) : '',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2E7D32),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Monthly Total Row ──
class _MonthTotalRow extends StatelessWidget {
  final MonthGroup group;
  const _MonthTotalRow({required this.group});

  @override
  Widget build(BuildContext context) {
    // Extract just the month name (e.g. "October" from "October 2023")
    final monthName = group.label.split(' ').first;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey.shade300),
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
        color: Colors.grey.shade50,
      ),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Row(
        children: [
          const SizedBox(width: 60),
          Expanded(
            flex: 3,
            child: Text(
              '$monthName Total',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.black87,
              ),
            ),
          ),
          const Expanded(flex: 3, child: SizedBox()),
          Container(
            width: 90,
            alignment: Alignment.centerRight,
            child: Text(
              _inrFormat.format(group.monthTotalDebit),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Color(0xFFC62828),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Container(
            width: 90,
            alignment: Alignment.centerRight,
            child: Text(
              _inrFormat.format(group.monthTotalCredit),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Color(0xFF2E7D32),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Date Chip ──
class _DateChip extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;

  const _DateChip({required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Text(
              date != null ? _fullDateFormat.format(date!) : label,
              style: TextStyle(
                color: date != null ? Colors.black87 : Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty State ──
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_rounded, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No transactions found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add transactions to see your\naccount statement here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
