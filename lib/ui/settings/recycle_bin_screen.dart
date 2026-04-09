import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/customer.dart';
import '../../models/transaction.dart';
import '../../providers/customer_provider.dart';
import '../../providers/db_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../services/safe_text.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
final _dateFormat = DateFormat('d MMM yyyy, hh:mm a');

// ---------------------------------------------------------------------------
// Riverpod providers for the Recycle Bin contents
// ---------------------------------------------------------------------------

final _deletedCustomersProvider = Provider.autoDispose<List<Customer>>((ref) {
  final db = ref.watch(dbServiceProvider);
  // Rebuild whenever customers or transactions change
  ref.watch(customersProvider);
  return db.getDeletedCustomers();
});

final _deletedTransactionsProvider = Provider.autoDispose<List<TransactionModel>>((ref) {
  final db = ref.watch(dbServiceProvider);
  ref.watch(customersProvider);
  return db.getDeletedTransactions();
});

// ---------------------------------------------------------------------------
// Recycle Bin Screen
// ---------------------------------------------------------------------------

class RecycleBinScreen extends ConsumerStatefulWidget {
  const RecycleBinScreen({super.key});

  @override
  ConsumerState<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends ConsumerState<RecycleBinScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showSnack(String message, {bool isSuccess = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? Colors.green.shade700 : null,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ---- Customer actions ---------------------------------------------------

  Future<void> _restoreCustomer(String id, String name) async {
    await ref.read(dbServiceProvider).restoreCustomer(id);
    // Also restore all associated transactions for that customer
    final db = ref.read(dbServiceProvider);
    final deletedTxns = db.getDeletedTransactions().where((t) => t.customerId == id).toList();
    for (final txn in deletedTxns) {
      await db.restoreTransaction(txn.id);
    }
    ref.invalidate(customersProvider);
    ref.invalidate(dashboardBalancesProvider);
    ref.invalidate(customerBalanceMapProvider);
    if (mounted) _showSnack('$name restored successfully.', isSuccess: true);
  }

  Future<void> _permanentlyDeleteCustomer(String id, String name) async {
    final confirmed = await _confirmPermanentDelete(
      'Permanently delete "$name"?',
      'This will also permanently delete all their transactions. This action CANNOT be undone.',
    );
    if (!confirmed) return;
    await ref.read(dbServiceProvider).permanentlyDeleteCustomer(id);
    ref.invalidate(customersProvider);
    ref.invalidate(dashboardBalancesProvider);
    ref.invalidate(customerBalanceMapProvider);
    if (mounted) _showSnack('"$name" permanently deleted.');
  }

  // ---- Transaction actions ------------------------------------------------

  Future<void> _restoreTransaction(String id) async {
    await ref.read(dbServiceProvider).restoreTransaction(id);
    ref.invalidate(customersProvider);
    ref.invalidate(dashboardBalancesProvider);
    ref.invalidate(customerBalanceMapProvider);
    if (mounted) _showSnack('Transaction restored.', isSuccess: true);
  }

  Future<void> _permanentlyDeleteTransaction(String id, String amount) async {
    final confirmed = await _confirmPermanentDelete(
      'Permanently delete this transaction?',
      'The $amount transaction will be permanently removed. This cannot be undone.',
    );
    if (!confirmed) return;
    await ref.read(dbServiceProvider).permanentlyDeleteTransaction(id);
    ref.invalidate(customersProvider);
    ref.invalidate(dashboardBalancesProvider);
    ref.invalidate(customerBalanceMapProvider);
    if (mounted) _showSnack('Transaction permanently deleted.');
  }

  Future<bool> _confirmPermanentDelete(String title, String content) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            content: Text(content, style: const TextStyle(color: Colors.black54)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCEL'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('DELETE FOREVER'),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ---- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final deletedCustomers = ref.watch(_deletedCustomersProvider);
    final deletedTransactions = ref.watch(_deletedTransactionsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'Recycle Bin',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20, letterSpacing: -0.5),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF005CEE),
          labelColor: const Color(0xFF005CEE),
          unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: [
            Tab(text: 'Customers (${deletedCustomers.length})'),
            Tab(text: 'Transactions (${deletedTransactions.length})'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Info banner: 30-day autopurge notice
          Container(
            width: double.infinity,
            color: const Color(0xFFFFF8E1),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 15, color: Color(0xFFF57F17)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Items in the Recycle Bin are automatically deleted after 30 days.',
                    style: TextStyle(fontSize: 12, color: Color(0xFFF57F17)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // ── Customers Tab ────────────────────────────────────────────
                _buildCustomersTab(deletedCustomers),
                // ── Transactions Tab ─────────────────────────────────────────
                _buildTransactionsTab(deletedTransactions),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomersTab(List<Customer> customers) {
    if (customers.isEmpty) {
      return _EmptyBinState(label: 'No deleted customers');
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: customers.length,
      itemBuilder: (context, index) {
        final c = customers[index];
        final safeName = safeText(c.name, fallback: 'Unknown');
        final initial = safeName.isNotEmpty ? safeName[0].toUpperCase() : '?';
        final deletedAt = c.updatedAt != null ? _dateFormat.format(c.updatedAt!) : 'Unknown';

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.red.shade50,
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Color(0xFFC62828),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        safeName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      if (c.phone != null && c.phone!.isNotEmpty)
                        Text(c.phone!, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                      Text(
                        'Deleted: $deletedAt',
                        style: TextStyle(color: Colors.red.shade300, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                // Actions
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BinActionButton(
                      icon: Icons.restore_rounded,
                      color: const Color(0xFF005CEE),
                      tooltip: 'Restore',
                      onTap: () => _restoreCustomer(c.id, c.name),
                    ),
                    const SizedBox(width: 6),
                    _BinActionButton(
                      icon: Icons.delete_forever_rounded,
                      color: Colors.red,
                      tooltip: 'Delete Forever',
                      onTap: () => _permanentlyDeleteCustomer(c.id, c.name),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTransactionsTab(List<TransactionModel> transactions) {
    if (transactions.isEmpty) {
      return _EmptyBinState(label: 'No deleted transactions');
    }

    // Group by customerId to show customer context
    final db = ref.read(dbServiceProvider);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: transactions.length,
      itemBuilder: (context, index) {
        final t = transactions[index];
        final customer = db.customersBox.get(t.customerId);
        final customerName = customer != null
            ? safeText(customer.name, fallback: 'Unknown')
            : 'Unknown Customer';
        final isGot = t.isGot;
        final amountStr = _currency.format(t.amountInPaise / 100.0);
        final deletedAt = t.updatedAt != null ? _dateFormat.format(t.updatedAt!) : 'Unknown';

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Type badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: isGot ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isGot ? Icons.south_west_rounded : Icons.north_east_rounded,
                    color: isGot ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        amountStr,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isGot ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                        ),
                      ),
                      if (t.note.isNotEmpty)
                        Text(
                          safeText(t.note),
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      Text(
                        'Customer: $customerName',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                      ),
                      Text(
                        'Deleted: $deletedAt',
                        style: TextStyle(color: Colors.red.shade300, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                // Actions
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BinActionButton(
                      icon: Icons.restore_rounded,
                      color: const Color(0xFF005CEE),
                      tooltip: 'Restore',
                      onTap: () => _restoreTransaction(t.id),
                    ),
                    const SizedBox(width: 6),
                    _BinActionButton(
                      icon: Icons.delete_forever_rounded,
                      color: Colors.red,
                      tooltip: 'Delete Forever',
                      onTap: () => _permanentlyDeleteTransaction(t.id, amountStr),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Helper widgets
// ---------------------------------------------------------------------------

class _BinActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _BinActionButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}

class _EmptyBinState extends StatelessWidget {
  final String label;
  const _EmptyBinState({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline_rounded, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Items you delete will appear here.',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
