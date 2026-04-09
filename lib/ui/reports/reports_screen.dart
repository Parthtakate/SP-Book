import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../providers/db_provider.dart';
import '../../services/pdf_service.dart';
import '../../services/csv_service.dart';
import '../../providers/reports_provider.dart';

// ── Formatters (unchanged) ──────────────────────────────────────────────────
final _inrFormat = NumberFormat('#,##,##0.00', 'en_IN');
final _dateFormat = DateFormat('dd MMM');
final _fullDateFormat = DateFormat('dd MMM yyyy');
final _headerDateFormat = DateFormat('dd MMM yyyy');
final _timestampFormat = DateFormat("h:mm a | dd MMM''yy");

// ── Design tokens ───────────────────────────────────────────────────────────
const _kPrimary = Color(0xFF1A237E);
const _kDebit = Color(0xFFC62828);
const _kDebitBg = Color(0xFFFFF0F0);
const _kCredit = Color(0xFF2E7D32);
const _kCreditBg = Color(0xFFF0FFF0);
const _kBg = Color(0xFFF1F5F9); // slate-100

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  // ── State (unchanged) ────────────────────────────────────────────────────
  DateTime? _startDate;
  DateTime? _endDate;
  String _filterMode = 'ALL';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Date pickers (logic unchanged) ───────────────────────────────────────
  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _startDate ?? DateTime.now().subtract(const Duration(days: 30)),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _kPrimary,
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
            primary: _kPrimary,
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
    if (_filterMode == 'DATE RANGE' &&
        _startDate != null &&
        _endDate != null) {
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

  // ── Helpers (logic unchanged) ─────────────────────────────────────────────
  String _getUserName() {
    final db = ref.read(dbServiceProvider);
    final businessName = db.getBusinessName();
    if (businessName != null && businessName.isNotEmpty) return businessName;
    final user = FirebaseAuth.instance.currentUser;
    return user?.displayName ?? 'Account Statement';
  }

  String _getDateRangeLabel() {
    final dateRange = ref.read(reportDateRangeProvider);
    if (dateRange == null) return 'All Time';
    return '${_headerDateFormat.format(dateRange.start)} – ${_headerDateFormat.format(dateRange.end)}';
  }

  // ── Export/Share actions (logic unchanged, deprecated API fixed) ──────────
  Future<void> _exportPdf() async {
    try {
      _showSnack('Generating PDF…');
      final statement = await ref.read(accountStatementProvider.future);
      final dateRange = ref.read(reportDateRangeProvider);
      final filePath = await PdfService.generateAccountStatementPdf(
        userName: _getUserName(),
        statement: statement,
        dateRange: dateRange,
      );
      if (filePath == null || !mounted) return;
      _showSnack('PDF saved successfully.');
    } catch (_) {
      _showSnack('Error generating PDF. Please try again.');
    }
  }

  Future<void> _exportCsv() async {
    try {
      _showSnack('Generating CSV…');
      final statement = await ref.read(accountStatementProvider.future);
      final dateRange = ref.read(reportDateRangeProvider);
      final filePath = await CsvService.generateAccountStatementCsv(
        userName: _getUserName(),
        statement: statement,
        dateRange: dateRange,
      );
      if (filePath == null || !mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath)],
          text: 'SPBOOKS Account Statement (CSV)',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _showSnack('Error generating CSV. Please try again.');
    }
  }

  Future<void> _sharePdf() async {
    try {
      _showSnack('Generating PDF…');
      final statement = await ref.read(accountStatementProvider.future);
      final dateRange = ref.read(reportDateRangeProvider);
      final filePath = await PdfService.generateAccountStatementPdf(
        userName: _getUserName(),
        statement: statement,
        dateRange: dateRange,
      );
      if (filePath == null) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath)],
          text: 'SPBOOKS Account Statement',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _showSnack('Error sharing PDF. Please try again.');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final statementAsync = ref.watch(accountStatementProvider);
    final userName = _getUserName();
    final isFiltered = _filterMode == 'DATE RANGE';

    return Scaffold(
      backgroundColor: _kBg,
      body: Column(
        children: [
          // ── Premium Gradient Header ──────────────────────────────────────
          _ReportHeader(
            userName: userName,
            dateRangeLabel: _getDateRangeLabel(),
            onBack: () => Navigator.pop(context),
          ),

          // ── Body: AsyncValue unwrap ──────────────────────────────────────
          Expanded(
            child: statementAsync.when(
              loading: () => const _StatementShimmer(),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: _kDebit, size: 40),
                    const SizedBox(height: 12),
                    const Text('Failed to load statement',
                        style: TextStyle(color: _kDebit)),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => ref.invalidate(accountStatementProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (statement) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SummaryRow(statement: statement),
                    const SizedBox(height: 20),
                    _FilterCard(
                      filterMode: _filterMode,
                      entryCount: statement.entryCount,
                      searchCtrl: _searchCtrl,
                      startDate: _startDate,
                      endDate: _endDate,
                      isFiltered: isFiltered,
                      onFilterChanged: _onFilterChanged,
                      onSearchChanged: (v) =>
                          ref.read(reportSearchTextProvider.notifier).update(v),
                      onPickStart: _pickStartDate,
                      onPickEnd: _pickEndDate,
                    ),
                    const SizedBox(height: 20),
                    _StatementTable(statement: statement),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        'Generated: ${_timestampFormat.format(DateTime.now())}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade400,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom Action Bar ────────────────────────────────────────────
          _ActionBar(
            onPdf: _exportPdf,
            onCsv: _exportCsv,
            onShare: _sharePdf,
          ),
        ],
      ),
    );
  }
}


// ════════════════════════════════════════════════════════════════════════════
// Shimmer loading placeholder
// ════════════════════════════════════════════════════════════════════════════

class _StatementShimmer extends StatefulWidget {
  const _StatementShimmer();

  @override
  State<_StatementShimmer> createState() => _StatementShimmerState();
}

class _StatementShimmerState extends State<_StatementShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _bar({double width = double.infinity, double height = 14.0}) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) => Container(
        width: width,
        height: height,
        margin: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          color: Colors.grey.shade300.withValues(alpha: _anim.value),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary cards skeleton
          Row(
            children: [
              for (int i = 0; i < 3; i++) ...[
                Expanded(
                  child: Container(
                    height: 88,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _bar(width: 24, height: 24),
                        const SizedBox(height: 6),
                        _bar(width: 50, height: 10),
                        _bar(width: 70, height: 12),
                      ],
                    ),
                  ),
                ),
                if (i < 2) const SizedBox(width: 10),
              ],
            ],
          ),
          const SizedBox(height: 20),
          // Filter card skeleton
          Container(
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(children: [_bar(), _bar(width: 200)]),
          ),
          const SizedBox(height: 20),
          // Table skeleton
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: List.generate(
                8,
                (_) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      _bar(width: 40, height: 10),
                      const SizedBox(width: 8),
                      Expanded(child: _bar(height: 10)),
                      const SizedBox(width: 8),
                      _bar(width: 60, height: 10),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Sub-widgets — pure UI, zero business logic
// ════════════════════════════════════════════════════════════════════════════

// ── Header ──────────────────────────────────────────────────────────────────
class _ReportHeader extends StatelessWidget {
  final String userName;
  final String dateRangeLabel;
  final VoidCallback onBack;

  const _ReportHeader({
    required this.userName,
    required this.dateRangeLabel,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D1B6E), Color(0xFF1A237E), Color(0xFF283593)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Back + brand row
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: onBack,
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.book,
                            color: Colors.white, size: 11),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'SPBOOKS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.receipt_long_rounded,
                          color: Colors.white60, size: 14),
                      const SizedBox(width: 6),
                      const Text(
                        'Account Statement  •  ',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                      Text(
                        dateRangeLabel,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
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

// ── Summary Row ─────────────────────────────────────────────────────────────
class _SummaryRow extends StatelessWidget {
  final AccountStatement statement;
  const _SummaryRow({required this.statement});

  @override
  Widget build(BuildContext context) {
    final isCr = statement.balanceType == 'Cr';
    return Row(
      children: [
        Expanded(
          child: _SummaryTile(
            label: 'Total Debit',
            value: '₹${_inrFormat.format(statement.grandTotalDebit)}',
            icon: Icons.arrow_upward_rounded,
            color: _kDebit,
            bgColor: _kDebitBg,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryTile(
            label: 'Total Credit',
            value: '₹${_inrFormat.format(statement.grandTotalCredit)}',
            icon: Icons.arrow_downward_rounded,
            color: _kCredit,
            bgColor: _kCreditBg,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryTile(
            label: 'Net Balance',
            value:
                '₹${_inrFormat.format(statement.netBalance.abs())} ${statement.balanceType}',
            icon: isCr ? Icons.account_balance_wallet_rounded : Icons.warning_amber_rounded,
            color: isCr ? _kCredit : _kDebit,
            bgColor: isCr ? _kCreditBg : _kDebitBg,
            isBalance: true,
          ),
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final bool isBalance;

  const _SummaryTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.bgColor,
    this.isBalance = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: isBalance ? Border.all(color: color.withValues(alpha: 0.3)) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Filter + Search Card ─────────────────────────────────────────────────────
class _FilterCard extends StatelessWidget {
  final String filterMode;
  final int entryCount;
  final TextEditingController searchCtrl;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isFiltered;
  final ValueChanged<String?> onFilterChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  const _FilterCard({
    required this.filterMode,
    required this.entryCount,
    required this.searchCtrl,
    required this.startDate,
    required this.endDate,
    required this.isFiltered,
    required this.onFilterChanged,
    required this.onSearchChanged,
    required this.onPickStart,
    required this.onPickEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Entry count + filter toggle
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _kPrimary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$entryCount entries',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _kPrimary,
                    ),
                  ),
                ),
                const Spacer(),
                // Filter chips
                _FilterChip2(
                  label: 'All',
                  selected: filterMode == 'ALL',
                  onTap: () => onFilterChanged('ALL'),
                ),
                const SizedBox(width: 6),
                _FilterChip2(
                  label: 'Date Range',
                  selected: filterMode == 'DATE RANGE',
                  onTap: () => onFilterChanged('DATE RANGE'),
                  icon: Icons.date_range_rounded,
                ),
              ],
            ),
          ),

          // Date pickers
          if (isFiltered) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _DateChip(
                      label: 'FROM',
                      date: startDate,
                      onTap: onPickStart,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DateChip(
                      label: 'TO',
                      date: endDate,
                      onTap: onPickEnd,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Divider + search
          Divider(height: 1, color: Colors.grey.shade100),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: searchCtrl,
              onChanged: onSearchChanged,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search by name or note…',
                hintStyle:
                    TextStyle(color: Colors.grey.shade400, fontSize: 13),
                prefixIcon: Icon(Icons.search,
                    size: 20, color: Colors.grey.shade400),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip2 extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  const _FilterChip2({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? _kPrimary : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: selected ? Colors.white : Colors.grey),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: selected ? Colors.white : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Statement Table ──────────────────────────────────────────────────────────
class _StatementTable extends StatelessWidget {
  final AccountStatement statement;
  const _StatementTable({required this.statement});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Table header
          Container(
            color: _kPrimary,
            padding:
                const EdgeInsets.symmetric(vertical: 11, horizontal: 16),
            child: Row(
              children: [
                const SizedBox(
                    width: 52,
                    child: Text('Date', style: _kHeaderStyle)),
                const Expanded(
                    flex: 3,
                    child: Text('Name', style: _kHeaderStyle)),
                const Expanded(
                    flex: 3,
                    child: Text('Details', style: _kHeaderStyle)),
                Container(
                  width: 80,
                  alignment: Alignment.centerRight,
                  child: const Text('Debit(−)', style: _kHeaderStyle),
                ),
                const SizedBox(width: 4),
                Container(
                  width: 80,
                  alignment: Alignment.centerRight,
                  child: const Text('Credit(+)', style: _kHeaderStyle),
                ),
              ],
            ),
          ),

          // Month groups or empty state
          if (statement.monthGroups.isEmpty)
            const _EmptyState()
          else
            ...statement.monthGroups.expand((group) => [
                  _MonthHeader(label: group.label),
                  ...group.entries
                      .map((entry) => _EntryRow(entry: entry)),
                  _MonthTotalRow(group: group),
                ]),

          // Grand total
          if (statement.monthGroups.isNotEmpty) _GrandTotalRow(statement: statement),
        ],
      ),
    );
  }
}

// ── Month header ─────────────────────────────────────────────────────────────
class _MonthHeader extends StatelessWidget {
  final String label;
  const _MonthHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFEEF2FF), // indigo-50
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              color: _kPrimary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: _kPrimary,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Entry Row ─────────────────────────────────────────────────────────────────
class _EntryRow extends StatelessWidget {
  final AccountStatementEntry entry;
  const _EntryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final hasDebit = entry.debitAmount > 0;
    final hasCredit = entry.creditAmount > 0;

    return Container(
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: Colors.grey.shade100, width: 0.8)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Row(
        children: [
          // Date
          SizedBox(
            width: 52,
            child: Text(
              _dateFormat.format(entry.date),
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500),
            ),
          ),
          // Name
          Expanded(
            flex: 3,
            child: Text(
              entry.customerName,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Details
          Expanded(
            flex: 3,
            child: Text(
              entry.details.isEmpty ? '—' : entry.details,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Debit
          Container(
            width: 80,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
            decoration: hasDebit
                ? BoxDecoration(
                    color: _kDebitBg,
                    borderRadius: BorderRadius.circular(5),
                  )
                : null,
            child: Text(
              hasDebit ? _inrFormat.format(entry.debitAmount) : '',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _kDebit),
            ),
          ),
          const SizedBox(width: 4),
          // Credit
          Container(
            width: 80,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
            decoration: hasCredit
                ? BoxDecoration(
                    color: _kCreditBg,
                    borderRadius: BorderRadius.circular(5),
                  )
                : null,
            child: Text(
              hasCredit ? _inrFormat.format(entry.creditAmount) : '',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _kCredit),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Monthly Total Row ─────────────────────────────────────────────────────────
class _MonthTotalRow extends StatelessWidget {
  final MonthGroup group;
  const _MonthTotalRow({required this.group});

  @override
  Widget build(BuildContext context) {
    final monthName = group.label.split(' ').first;
    return Container(
      color: const Color(0xFFF8FAFF),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Row(
        children: [
          const SizedBox(width: 52),
          Expanded(
            flex: 3,
            child: Text(
              '$monthName Total',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: _kPrimary,
              ),
            ),
          ),
          const Expanded(flex: 3, child: SizedBox()),
          SizedBox(
            width: 80,
            child: Text(
              _inrFormat.format(group.monthTotalDebit),
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: _kDebit),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 80,
            child: Text(
              _inrFormat.format(group.monthTotalCredit),
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: _kCredit),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Grand Total Row ───────────────────────────────────────────────────────────
class _GrandTotalRow extends StatelessWidget {
  final AccountStatement statement;
  const _GrandTotalRow({required this.statement});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _kPrimary.withValues(alpha: 0.06),
            _kPrimary.withValues(alpha: 0.03),
          ],
        ),
        border: Border(
          top: BorderSide(color: _kPrimary.withValues(alpha: 0.25), width: 1.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      child: Row(
        children: [
          const SizedBox(width: 52),
          const Expanded(
            flex: 3,
            child: Text(
              'Grand Total',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: _kPrimary,
              ),
            ),
          ),
          const Expanded(flex: 3, child: SizedBox()),
          Container(
            width: 80,
            alignment: Alignment.centerRight,
            padding:
                const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
            decoration: BoxDecoration(
              color: _kDebitBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _inrFormat.format(statement.grandTotalDebit),
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: _kDebit),
            ),
          ),
          const SizedBox(width: 4),
          Container(
            width: 80,
            alignment: Alignment.centerRight,
            padding:
                const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
            decoration: BoxDecoration(
              color: _kCreditBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _inrFormat.format(statement.grandTotalCredit),
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: _kCredit),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Date Chip ────────────────────────────────────────────────────────────────
class _DateChip extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  const _DateChip(
      {required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasDate = date != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: hasDate
              ? _kPrimary.withValues(alpha: 0.06)
              : Colors.grey.shade50,
          border: Border.all(
            color:
                hasDate ? _kPrimary.withValues(alpha: 0.4) : Colors.grey.shade300,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded,
                size: 14,
                color: hasDate ? _kPrimary : Colors.grey.shade500),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasDate ? _fullDateFormat.format(date!) : label,
                style: TextStyle(
                  color: hasDate ? _kPrimary : Colors.grey.shade500,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_rounded,
              size: 64, color: Colors.grey.shade200),
          const SizedBox(height: 16),
          Text(
            'No transactions found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade500,
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

// ── Bottom Action Bar ─────────────────────────────────────────────────────────
class _ActionBar extends StatelessWidget {
  final VoidCallback onPdf;
  final VoidCallback onCsv;
  final VoidCallback onShare;

  const _ActionBar({
    required this.onPdf,
    required this.onCsv,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: _ActionButton(
                onTap: onPdf,
                icon: Icons.picture_as_pdf_rounded,
                label: 'Save PDF',
                color: _kPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionButton(
                onTap: onCsv,
                icon: Icons.table_chart_rounded,
                label: 'Export CSV',
                color: const Color(0xFF00695C), // teal-800
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionButton(
                onTap: onShare,
                icon: Icons.share_rounded,
                label: 'Share PDF',
                color: const Color(0xFF1565C0), // blue-800
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final String label;
  final Color color;

  const _ActionButton({
    required this.onTap,
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared header style ───────────────────────────────────────────────────────
const _kHeaderStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.bold,
  color: Colors.white70,
  letterSpacing: 0.3,
);
