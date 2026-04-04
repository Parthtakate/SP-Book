import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:async';

import '../providers/customer_provider.dart';
import '../providers/transaction_provider.dart';
import '../providers/customer_last_transaction_provider.dart';
import '../models/customer.dart';
import 'customer/add_customer_screen.dart';
import 'customer/customer_details_screen.dart';
import 'reports/reports_screen.dart';
import 'settings_screen.dart';
import '../providers/auto_sync_provider.dart';
import '../services/safe_text.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
final _relativeDate = DateFormat('d MMM');

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  late final AnimationController _fabAnimController;
  late final Animation<double> _fabScaleAnimation;

  @override
  void initState() {
    super.initState();
    _fabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fabScaleAnimation = CurvedAnimation(
      parent: _fabAnimController,
      curve: Curves.elasticOut,
    );
    // Delay the FAB entrance for a polished feel
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _fabAnimController.forward();
    });

    Future.microtask(() async {
      // Background sync triggers removed for architectural simplification.
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _fabAnimController.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(searchQueryProvider.notifier).updateQuery(value);
    });
  }

  void _tryDeleteCustomer(
      BuildContext context, WidgetRef ref, String customerId, String name) {
    final balanceMap = ref.read(customerBalanceMapProvider);
    final balancePaise = balanceMap[customerId] ?? 0;

    if (balancePaise != 0) {
      // Unsettled account — show blocking sheet
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _UnsettledDeleteSheet(
          name: name,
          balancePaise: balancePaise,
          onViewAccount: () {
            Navigator.pop(context);
          },
        ),
      );
    } else {
      // Settled — show normal confirm dialog
      _showDeleteConfirmation(context, ref, customerId, name);
    }
  }

  void _showDeleteConfirmation(
      BuildContext context, WidgetRef ref, String customerId, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Customer?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          'Delete "${safeText(name, fallback: 'this customer')}" and all their transactions? This cannot be undone.',
          style: const TextStyle(color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              ref.read(customersProvider.notifier).deleteCustomer(customerId);
              Navigator.pop(context);
            },
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keep auto-sync alive
    ref.watch(autoSyncProvider);

    final balances = ref.watch(dashboardBalancesProvider);
    final filteredCustomers = ref.watch(filteredCustomersProvider);
    final allCustomers = ref.watch(customersProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: _buildAppBar(context),
      floatingActionButton: ScaleTransition(
        scale: _fabScaleAnimation,
        child: FloatingActionButton.extended(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddCustomerScreen()),
            );
          },
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Add Customer', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF005CEE),
          foregroundColor: Colors.white,
          elevation: 4,
        ),
      ),
      body: Column(
        children: [
          // Dashboard Card
          _DashboardCard(
            toReceive: balances['toReceive'] ?? 0,
            toPay: balances['toPay'] ?? 0,
            onViewReports: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReportsScreen()),
            ),
          ),

          // Search + filter bar
          _SearchAndFilterBar(
            controller: _searchController,
            currentFilter: ref.watch(filterModeProvider),
            onSearch: _onSearch,
            onFilter: (mode) =>
                ref.read(filterModeProvider.notifier).setFilter(mode),
          ),

          // Legend header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Your Customers',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${filteredCustomers.length} shown',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),

          // Customer list
          Expanded(
            child: filteredCustomers.isEmpty
                ? _EmptyState(
                    hasCustomers: allCustomers.isNotEmpty,
                    onAddCustomer: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AddCustomerScreen()),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                    itemCount: filteredCustomers.length,
                    itemBuilder: (context, index) {
                      final customer = filteredCustomers[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _CustomerListCard(
                          customer: customer,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  CustomerDetailsScreen(customer: customer),
                            ),
                          ),
                          onLongPress: () => _tryDeleteCustomer(
                            context,
                            ref,
                            customer.id,
                            customer.name,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    return AppBar(
      title: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/images/logo.png',
              width: 32,
              height: 32,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'SPBOOKS',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
        ],
      ),
      backgroundColor: const Color(0xFF005CEE),
      foregroundColor: Colors.white,
      elevation: 0,
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Settings & Backup',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Dashboard Card
// ---------------------------------------------------------------------------

class _DashboardCard extends StatelessWidget {
  final double toReceive;
  final double toPay;
  final VoidCallback onViewReports;

  const _DashboardCard({
    required this.toReceive,
    required this.toPay,
    required this.onViewReports,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF005CEE), Color(0xFF1A7CFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF005CEE).withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Net Balance',
              style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 0.5),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _BalanceColumn(
                    label: 'You will give',
                    amount: toPay,
                    color: const Color(0xFFFF8A80),
                    icon: Icons.arrow_upward_rounded,
                  ),
                ),
                Container(
                  width: 1,
                  height: 48,
                  color: Colors.white24,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                ),
                Expanded(
                  child: _BalanceColumn(
                    label: 'You will get',
                    amount: toReceive,
                    color: const Color(0xFF69F0AE),
                    icon: Icons.arrow_downward_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: onViewReports,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.bar_chart_rounded, color: Colors.white70, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'View Full Reports',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.chevron_right, color: Colors.white70, size: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceColumn extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final IconData icon;

  const _BalanceColumn({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _currency.format(amount),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Search and Filter Bar
// ---------------------------------------------------------------------------

class _SearchAndFilterBar extends StatelessWidget {
  final TextEditingController controller;
  final FilterMode currentFilter;
  final ValueChanged<String> onSearch;
  final ValueChanged<FilterMode> onFilter;

  const _SearchAndFilterBar({
    required this.controller,
    required this.currentFilter,
    required this.onSearch,
    required this.onFilter,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          // Search
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: controller,
              onChanged: onSearch,
              decoration: InputDecoration(
                hintText: 'Search by name or phone…',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close, color: Colors.grey.shade400),
                        onPressed: () {
                          controller.clear();
                          onSearch('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Filter chips
          Row(
            children: [
              _FilterPill(
                label: 'All',
                mode: FilterMode.all,
                currentMode: currentFilter,
                onTap: onFilter,
              ),
              const SizedBox(width: 8),
              _FilterPill(
                label: '↓ To Receive',
                mode: FilterMode.toReceive,
                currentMode: currentFilter,
                onTap: onFilter,
                activeColor: const Color(0xFF2E7D32),
              ),
              const SizedBox(width: 8),
              _FilterPill(
                label: '↑ To Pay',
                mode: FilterMode.toPay,
                currentMode: currentFilter,
                onTap: onFilter,
                activeColor: const Color(0xFFC62828),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final FilterMode mode;
  final FilterMode currentMode;
  final ValueChanged<FilterMode> onTap;
  final Color activeColor;

  const _FilterPill({
    required this.label,
    required this.mode,
    required this.currentMode,
    required this.onTap,
    this.activeColor = const Color(0xFF005CEE),
  });

  @override
  Widget build(BuildContext context) {
    final selected = mode == currentMode;
    return GestureDetector(
      onTap: () => onTap(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? activeColor : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? activeColor : Colors.grey.shade300,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black54,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Customer List Card
// ---------------------------------------------------------------------------

class _CustomerListCard extends ConsumerWidget {
  final Customer customer;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _CustomerListCard({
    required this.customer,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(customerBalanceProvider(customer.id));
    final lastTxnDate = ref.watch(customerLastTransactionProvider(customer.id));

    final Color balanceColor;
    final String balanceLabel;

    if (balance > 0) {
      balanceColor = const Color(0xFF2E7D32);
      balanceLabel = 'Will give you';
    } else if (balance < 0) {
      balanceColor = const Color(0xFFC62828);
      balanceLabel = 'You will give';
    } else {
      balanceColor = Colors.grey;
      balanceLabel = 'Settled up';
    }

    // Use safeText first to strip any malformed UTF-16 before we
    // slice characters. Directly indexing customer.name[0] can crash
    // if the first codeunit is a lone surrogate (e.g. some emoji).
    final safeName = safeText(customer.name, fallback: '?');
    final initial = safeName.isNotEmpty ? safeName[0].toUpperCase() : '?';

    return Material(
      borderRadius: BorderRadius.circular(12),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Gradient avatar
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF005CEE), Color(0xFF5B9BFF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // Name + last transaction date
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        safeText(customer.name, fallback: '?'),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        lastTxnDate != null
                            ? 'Last: ${_relativeDate.format(lastTxnDate)}'
                            : safeText(customer.phone, fallback: 'No transactions yet'),
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Balance + label
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _currency.format(balance.abs()),
                      style: TextStyle(
                        color: balanceColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: balanceColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        balanceLabel,
                        style: TextStyle(color: balanceColor, fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final bool hasCustomers;
  final VoidCallback onAddCustomer;

  const _EmptyState({
    required this.hasCustomers,
    required this.onAddCustomer,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasCustomers ? Icons.search_off : Icons.people_outline,
              size: 72,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              hasCustomers ? 'No customers found' : 'No customers yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasCustomers
                  ? 'Try a different name or clear your search.'
                  : 'Tap the button below to add your first customer.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            ),
            if (!hasCustomers) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onAddCustomer,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Add your first customer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF005CEE),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Settlement Guard Bottom Sheet
// ---------------------------------------------------------------------------

class _UnsettledDeleteSheet extends StatelessWidget {
  final String name;
  final int balancePaise;
  final VoidCallback onViewAccount;

  const _UnsettledDeleteSheet({
    required this.name,
    required this.balancePaise,
    required this.onViewAccount,
  });

  @override
  Widget build(BuildContext context) {
    final isOwed = balancePaise > 0; // customer owes you
    final absAmount = _currency.format(balancePaise.abs() / 100.0);
    final color = isOwed ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    final safeName = safeText(name, fallback: 'this customer');
    final label = isOwed
        ? '$safeName owes you $absAmount'
        : 'You owe $safeName $absAmount';

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Red lock icon
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.lock_outline_rounded,
                color: Colors.red.shade400, size: 30),
          ),
          const SizedBox(height: 16),
          const Text(
            'Cannot Delete Customer',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Please settle the account before deleting.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),
          const SizedBox(height: 16),
          // Balance chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isOwed
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                  color: color,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onViewAccount,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF005CEE),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Got it',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
