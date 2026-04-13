import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/customer.dart';
import '../../models/transaction.dart';
import '../../services/pdf_service.dart';
import '../../services/safe_text.dart';

// ─── Formatters ────────────────────────────────────────────────────────────
final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
final _dateHeader = DateFormat('dd MMMM yyyy');
final _timeFormat = DateFormat('hh:mm a');

/// Displays the ledger (account statement) for a single contact.
/// Opened from the "Report" button inside [CustomerDetailsScreen].
class ContactLedgerScreen extends StatefulWidget {
  final Customer customer;
  final List<TransactionModel> transactions;
  final int balancePaise; // positive = contact owes you, negative = you owe them
  final DateTimeRange? initialDateRange;

  const ContactLedgerScreen({
    super.key,
    required this.customer,
    required this.transactions,
    required this.balancePaise,
    this.initialDateRange,
  });

  @override
  State<ContactLedgerScreen> createState() => _ContactLedgerScreenState();
}

class _ContactLedgerScreenState extends State<ContactLedgerScreen> {
  DateTimeRange? _filterRange;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _filterRange = widget.initialDateRange;
  }

  // ── Theme helpers ─────────────────────────────────────────────────────────
  Color get _accentColor {
    switch (widget.customer.contactType) {
      case ContactType.customer:
        return const Color(0xFF005CEE);
      case ContactType.supplier:
        return const Color(0xFFE65100);
      case ContactType.staff:
        return const Color(0xFF6A1B9A);
    }
  }

  String get _typeLabel {
    switch (widget.customer.contactType) {
      case ContactType.customer:
        return 'Customer';
      case ContactType.supplier:
        return 'Supplier';
      case ContactType.staff:
        return 'Staff Member';
    }
  }

  String get _reportTitle {
    switch (widget.customer.contactType) {
      case ContactType.customer:
        return 'Customer Ledger';
      case ContactType.supplier:
        return 'Supplier Ledger';
      case ContactType.staff:
        return 'Staff Ledger';
    }
  }

  // ── Filtered transactions ─────────────────────────────────────────────────
  List<TransactionModel> get _filteredTx {
    if (_filterRange == null) return widget.transactions;
    final start = DateUtils.dateOnly(_filterRange!.start);
    final end = DateUtils.dateOnly(_filterRange!.end);
    return widget.transactions.where((t) {
      final d = DateUtils.dateOnly(t.date);
      return !d.isBefore(start) && !d.isAfter(end);
    }).toList();
  }

  // ── Date-grouped map ─────────────────────────────────────────────────────
  Map<String, List<TransactionModel>> get _grouped {
    final sorted = List<TransactionModel>.from(_filteredTx)
      ..sort((a, b) => a.date.compareTo(b.date));
    final map = <String, List<TransactionModel>>{};
    for (final t in sorted) {
      final key = DateFormat('yyyy-MM-dd').format(t.date);
      map.putIfAbsent(key, () => []).add(t);
    }
    return map;
  }

  // ── Summary values ────────────────────────────────────────────────────────
  double get _totalDebit =>
      _filteredTx.where((t) => !t.isGot).fold(0, (s, t) => s + t.amountInPaise / 100.0);

  double get _totalCredit =>
      _filteredTx.where((t) => t.isGot).fold(0, (s, t) => s + t.amountInPaise / 100.0);

  double get _netBalance => widget.balancePaise / 100.0;

  // ── Actions ───────────────────────────────────────────────────────────────
  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  Future<void> _exportPdf() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    _showSnack('Generating PDF...');
    try {
      final filePath = await PdfService.generateCustomerStatementPdfPath(
        customer: widget.customer,
        transactions: widget.transactions,
        balance: _netBalance,
        dateRange: _filterRange,
      );
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath)],
          text: '${widget.customer.name} – $_typeLabel Statement',
        ),
      );
    } catch (e, st) {
      debugPrint('ContactLedgerScreen._exportPdf error: $e\n$st');
      if (mounted) _showSnack('Error generating PDF. Please try again.');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _pickDateRange() async {
    final initialRange = _filterRange ??
        DateTimeRange(
          start: DateTime.now().subtract(const Duration(days: 30)),
          end: DateTime.now(),
        );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: initialRange,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: _accentColor,
            onPrimary: Colors.white,
            onSurface: Colors.black,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _filterRange = picked);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;
    final txCount = _filteredTx.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Column(
        children: [
          // ── Header ─────────────────────────────────────────────────────
          _LedgerHeader(
            customer: widget.customer,
            accentColor: _accentColor,
            reportTitle: _reportTitle,
            filterRange: _filterRange,
            isExporting: _isExporting,
            onBack: () => Navigator.pop(context),
            onFilter: _filterRange != null
                ? () => setState(() => _filterRange = null)
                : _pickDateRange,
            onExportPdf: _exportPdf,
          ),

          // ── Summary Row ────────────────────────────────────────────────
          _SummaryBar(
            totalDebit: _totalDebit,
            totalCredit: _totalCredit,
            netBalance: _netBalance,
            accentColor: _accentColor,
          ),

          // ── Entry count pill ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _accentColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$txCount ${txCount == 1 ? 'entry' : 'entries'}${_filterRange != null ? ' (filtered)' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _accentColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Transaction list ───────────────────────────────────────────
          Expanded(
            child: txCount == 0
                ? _EmptyLedger(accentColor: _accentColor)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: _buildFlatList(grouped).length,
                    itemBuilder: (context, i) {
                      final item = _buildFlatList(grouped)[i];
                      if (item is _DateGroup) {
                        return _DateGroupHeader(
                          dateKey: item.dateKey,
                          openingBalance: item.openingBalance,
                        );
                      }
                      final tx = item as TransactionModel;
                      return _LedgerRow(transaction: tx);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Flattens the grouped map into a mixed list of [_DateGroup] headers and [TransactionModel] rows.
  List<dynamic> _buildFlatList(Map<String, List<TransactionModel>> grouped) {
    final items = <dynamic>[];
    double running = 0.0;

    for (final entry in grouped.entries) {
      items.add(_DateGroup(dateKey: entry.key, openingBalance: running));
      for (final tx in entry.value) {
        items.add(tx);
        if (!tx.isGot) {
          running += tx.amountInPaise / 100.0;
        } else {
          running -= tx.amountInPaise / 100.0;
        }
      }
    }
    return items;
  }
}

// ─── Internal model for date group headers ────────────────────────────────
class _DateGroup {
  final String dateKey;
  final double openingBalance;
  const _DateGroup({required this.dateKey, required this.openingBalance});
}

// ─── Header ───────────────────────────────────────────────────────────────

class _LedgerHeader extends StatelessWidget {
  final Customer customer;
  final Color accentColor;
  final String reportTitle;
  final DateTimeRange? filterRange;
  final bool isExporting;
  final VoidCallback onBack;
  final VoidCallback onFilter;
  final VoidCallback onExportPdf;

  const _LedgerHeader({
    required this.customer,
    required this.accentColor,
    required this.reportTitle,
    required this.filterRange,
    required this.isExporting,
    required this.onBack,
    required this.onFilter,
    required this.onExportPdf,
  });

  @override
  Widget build(BuildContext context) {
    final gradientEnd = HSLColor.fromColor(accentColor)
        .withLightness(
            (HSLColor.fromColor(accentColor).lightness + 0.12).clamp(0.0, 1.0))
        .toColor();

    final dateFormat = DateFormat('dd MMM yyyy');
    final rangeLabel = filterRange != null
        ? '${dateFormat.format(filterRange!.start)} – ${dateFormat.format(filterRange!.end)}'
        : 'All Time';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accentColor, gradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Back + actions row
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: onBack,
                ),
                Expanded(
                  child: Text(
                    safeText(customer.name, fallback: 'Contact'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Date filter toggle
                IconButton(
                  icon: Icon(
                    filterRange != null ? Icons.filter_alt_off : Icons.date_range_rounded,
                    color: Colors.white,
                  ),
                  tooltip: filterRange != null ? 'Clear filter' : 'Filter by date',
                  onPressed: onFilter,
                ),
                // Export PDF button
                isExporting
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white),
                        tooltip: 'Export PDF',
                        onPressed: onExportPdf,
                      ),
              ],
            ),

            // Label + date range
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reportTitle,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded,
                          color: Colors.white60, size: 12),
                      const SizedBox(width: 5),
                      Text(
                        rangeLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Summary Bar ─────────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  final double totalDebit;
  final double totalCredit;
  final double netBalance;
  final Color accentColor;

  const _SummaryBar({
    required this.totalDebit,
    required this.totalCredit,
    required this.netBalance,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final isCr = netBalance < 0; // you owe them → Credit side
    final netColor = isCr ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    final netLabel = isCr ? 'You Will Pay' : 'You Will Get';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          _SummaryCell(
            label: 'Total Debit(-)',
            value: _currency.format(totalDebit),
            color: const Color(0xFFC62828),
            icon: Icons.arrow_upward_rounded,
          ),
          _Divider(),
          _SummaryCell(
            label: 'Total Credit(+)',
            value: _currency.format(totalCredit),
            color: const Color(0xFF2E7D32),
            icon: Icons.arrow_downward_rounded,
          ),
          _Divider(),
          _SummaryCell(
            label: netLabel,
            value: _currency.format(netBalance.abs()),
            color: netColor,
            icon: Icons.account_balance_wallet_rounded,
            isHighlighted: true,
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 52, color: const Color(0xFFEEEEEE));
}

class _SummaryCell extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final bool isHighlighted;

  const _SummaryCell({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 11, color: color),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isHighlighted ? color : Colors.black87,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Date Group Header ────────────────────────────────────────────────────

class _DateGroupHeader extends StatelessWidget {
  final String dateKey; // 'yyyy-MM-dd'
  final double openingBalance;

  const _DateGroupHeader({required this.dateKey, required this.openingBalance});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse(dateKey);
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _dateHeader.format(date),
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: Colors.grey.shade300, height: 1)),
        ],
      ),
    );
  }
}

// ─── Ledger Row ───────────────────────────────────────────────────────────

class _LedgerRow extends StatelessWidget {
  final TransactionModel transaction;

  const _LedgerRow({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final isDebit = !t.isGot; // you gave → debit
    final amount = t.amountInPaise / 100.0;

    final Color tagColor =
        isDebit ? const Color(0xFFC62828) : const Color(0xFF2E7D32);
    final Color bgColor =
        isDebit ? const Color(0xFFFFF1F1) : const Color(0xFFF1F8F1);
    final String typeLabel = isDebit ? 'YOU GAVE' : 'YOU GOT';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: tagColor.withValues(alpha: 0.15),
          width: 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // Tag pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: tagColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                typeLabel,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: tagColor,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Time + note
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _timeFormat.format(t.date),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                  if (t.note.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      t.note,
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (t.imagePath != null && t.imagePath!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.image_outlined, size: 12, color: Colors.grey.shade400),
                        const SizedBox(width: 3),
                        Text(
                          'Image attached',
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Amount
            Text(
              _currency.format(amount),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: tagColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────

class _EmptyLedger extends StatelessWidget {
  final Color accentColor;
  const _EmptyLedger({required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Center(
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
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try clearing the date filter\nor add a transaction to get started.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }
}
