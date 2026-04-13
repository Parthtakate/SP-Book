import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';

import '../providers/customer_provider.dart';
import '../providers/khatabook_provider.dart';
import '../providers/transaction_provider.dart';
import '../providers/customer_last_transaction_provider.dart';
import '../models/customer.dart';
import 'customer/add_customer_screen.dart';
import 'customer/customer_details_screen.dart';
import 'khatabook/khatabook_selector_sheet.dart';
import 'reports/reports_screen.dart';
import 'settings_screen.dart';
import '../providers/auto_sync_provider.dart';
import '../providers/db_provider.dart';
import '../services/safe_text.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
final _relativeDate = DateFormat('d MMM');

// ─────────────────────────────────────────────────────────────────────────────
// HomeScreen — Tabbed (Customer / Supplier / Staff)
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  late final AnimationController _fabAnimController;
  late final Animation<double> _fabScaleAnimation;

  static const List<ContactType> _types = [
    ContactType.customer,
    ContactType.supplier,
    ContactType.staff,
  ];
  static const List<String> _fabLabels = [
    'Add Customer',
    'Add Supplier',
    'Add Staff',
  ];

  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);

    _fabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fabScaleAnimation = CurvedAnimation(
      parent: _fabAnimController,
      curve: Curves.elasticOut,
    );
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _fabAnimController.forward();
    });
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging &&
        _tabController.index != _currentTabIndex) {
      setState(() => _currentTabIndex = _tabController.index);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _fabAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep AutoSync alive while HomeScreen is mounted
    final syncState = ref.watch(autoSyncProvider);
    final db = ref.watch(dbServiceProvider);
    final allCustomers = ref.watch(customersProvider);
    final isRestoring = ref.watch(isRestoringProvider);
    final isGuest = FirebaseAuth.instance.currentUser == null ||
        FirebaseAuth.instance.currentUser!.isAnonymous;

    final isEmpty = allCustomers.isEmpty && db.transactionsBox.isEmpty;

    if (isEmpty && isRestoring && !isGuest) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(color: Color(0xFF005CEE)),
              SizedBox(height: 18),
              Text(
                'Setting up your account...',
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: _buildAppBar(context),
      body: Column(
        children: [
          // Sync status banner — sits above the tab pages
          _SyncStatusBanner(
            status: syncState.status,
            isRestoring: isRestoring,
            onRetry: () {
              ref.read(autoSyncProvider.notifier).stop();
              ref.read(autoSyncProvider.notifier).start();
            },
          ),

          // Three fully-separate tab pages
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _ContactTypePage(type: ContactType.customer),
                _ContactTypePage(type: ContactType.supplier),
                _ContactTypePage(type: ContactType.staff),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: ScaleTransition(
        scale: _fabScaleAnimation,
        child: FloatingActionButton.extended(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddCustomerScreen(
                contactType: _types[_currentTabIndex],
              ),
            ),
          ),
          icon: const Icon(Icons.person_add_alt_1),
          label: Text(
            _fabLabels[_currentTabIndex],
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFF045CC5), // Khatabook-style deep blue
          foregroundColor: Colors.white,
          elevation: 4,
        ),
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    return AppBar(
      // Logo as leading widget, frees up full title width for the book selector
      leading: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            'assets/images/logo.png',
            width: 32,
            height: 32,
            fit: BoxFit.cover,
          ),
        ),
      ),
      title: const _KhatabookSelectorButton(), // ← replaces static 'SPBOOKS' text
      backgroundColor: const Color(0xFF045CC5), // Khatabook-style deep blue
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
      // ── Khatabook-style tab bar ──
      bottom: TabBar(
        controller: _tabController,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white60,
        indicatorColor: Colors.white,
        indicatorWeight: 3,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.normal,
          fontSize: 13,
        ),
        tabs: const [
          Tab(icon: Icon(Icons.people, size: 18), text: 'CUSTOMERS'),
          Tab(icon: Icon(Icons.store, size: 18), text: 'SUPPLIERS'),
          Tab(icon: Icon(Icons.badge, size: 18), text: 'STAFF'),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Khatabook selector button shown in the AppBar title slot
// ───────────────────────────────────────────────────────────────────────────

class _KhatabookSelectorButton extends ConsumerWidget {
  const _KhatabookSelectorButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(activeKhatabookProvider);
    final bookName = book?.name ?? 'My Business';

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const KhatabookSelectorSheet(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                bookName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Separate page for each contact type
// AutomaticKeepAliveClientMixin preserves scroll & search when switching tabs.
// ─────────────────────────────────────────────────────────────────────────────

class _ContactTypePage extends ConsumerStatefulWidget {
  final ContactType type;
  const _ContactTypePage({required this.type});

  @override
  ConsumerState<_ContactTypePage> createState() => _ContactTypePageState();
}

class _ContactTypePageState extends ConsumerState<_ContactTypePage>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  FilterMode _filterMode = FilterMode.all;
  Timer? _debounce;

  @override
  bool get wantKeepAlive => true; // Preserve state when switching tabs

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchQuery = value.toLowerCase().trim());
    });
  }

  void _tryDeleteCustomer(String customerId, String name) {
    final balanceMap = ref.read(customerBalanceMapProvider);
    final balancePaise = balanceMap[customerId] ?? 0;

    if (balancePaise != 0) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _UnsettledDeleteSheet(
          name: name,
          balancePaise: balancePaise,
          onViewAccount: () => Navigator.pop(context),
        ),
      );
    } else {
      _showDeleteConfirmation(customerId, name);
    }
  }

  void _showDeleteConfirmation(String customerId, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete $_typeLabel?',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Delete "${safeText(name, fallback: 'this contact')}" and all their '
          'transactions? This cannot be undone.',
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
                  borderRadius: BorderRadius.circular(8)),
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

  // ── Per-type display strings ─────────────────────────────────────────────

  String get _typeLabel {
    switch (widget.type) {
      case ContactType.customer:
        return 'Customer';
      case ContactType.supplier:
        return 'Supplier';
      case ContactType.staff:
        return 'Staff Member';
    }
  }

  String get _pageTitle {
    switch (widget.type) {
      case ContactType.customer:
        return 'Your Customers';
      case ContactType.supplier:
        return 'Your Suppliers';
      case ContactType.staff:
        return 'Your Staff';
    }
  }

  String get _emptyTitle {
    switch (widget.type) {
      case ContactType.customer:
        return 'No customers yet';
      case ContactType.supplier:
        return 'No suppliers yet';
      case ContactType.staff:
        return 'No staff members yet';
    }
  }

  String get _searchHint {
    switch (widget.type) {
      case ContactType.customer:
        return 'Search customers…';
      case ContactType.supplier:
        return 'Search suppliers…';
      case ContactType.staff:
        return 'Search staff…';
    }
  }

  /// Returns (payLabel, receiveLabel) for the mini dashboard card.
  (String, String) get _dashLabels {
    switch (widget.type) {
      case ContactType.customer:
        return ('You will give', 'You will get');
      case ContactType.supplier:
        return ('You will pay', 'You will receive');
      case ContactType.staff:
        return ('Advance Given', 'Salary Due');
    }
  }

  Color get _typeAccent {
    switch (widget.type) {
      case ContactType.customer:
        return const Color(0xFF005CEE);
      case ContactType.supplier:
        return const Color(0xFFE65100);
      case ContactType.staff:
        return const Color(0xFF6A1B9A);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    final allCustomers = ref.watch(customersProvider);
    final balanceMap = ref.watch(customerBalanceMapProvider);

    // ── Filter by type first ─────────────────────────────────────────────
    var typeContacts = allCustomers
        .where((c) => c.contactType == widget.type)
        .toList();

    // ── Apply search ─────────────────────────────────────────────────────
    var filteredList = _searchQuery.isEmpty
        ? typeContacts
        : typeContacts.where((c) {
            return c.name.toLowerCase().contains(_searchQuery) ||
                (c.phone?.toLowerCase().contains(_searchQuery) ?? false);
          }).toList();

    // ── Apply balance filter ─────────────────────────────────────────────
    if (_filterMode != FilterMode.all) {
      filteredList = filteredList.where((c) {
        final balance = balanceMap[c.id] ?? 0;
        if (_filterMode == FilterMode.toReceive) return balance > 0;
        if (_filterMode == FilterMode.toPay) return balance < 0;
        return true;
      }).toList();
    }

    // ── Compute type-specific totals for the mini dashboard ──────────────
    double toReceive = 0;
    double toPay = 0;
    for (final c in typeContacts) {
      final balance = balanceMap[c.id] ?? 0;
      if (balance > 0) {
        toReceive += balance / 100.0;
      } else if (balance < 0) {
        toPay += balance.abs() / 100.0;
      }
    }

    final (payLabel, receiveLabel) = _dashLabels;

    return Column(
      children: [
        // ── Mini dashboard card (type-specific) ──────────────────────────
        _DashboardCard(
          toReceive: toReceive,
          toPay: toPay,
          receiveLabel: receiveLabel,
          payLabel: payLabel,
          accentColor: _typeAccent,
          onViewReports: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReportsScreen(filterType: widget.type),
            ),
          ),
        ),

        // ── Search + filter ───────────────────────────────────────────────
        _SearchAndFilterBar(
          controller: _searchController,
          hint: _searchHint,
          currentFilter: _filterMode,
          onSearch: _onSearch,
          onFilter: (mode) => setState(() => _filterMode = mode),
        ),

        // ── List header ───────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _pageTitle,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                '${filteredList.length} shown',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),

        // ── Contact list ──────────────────────────────────────────────────
        Expanded(
          child: filteredList.isEmpty
              ? _EmptyState(
                  hasItems: typeContacts.isNotEmpty,
                  emptyTitle: _emptyTitle,
                  addLabel: 'Add $_typeLabel',
                  typeAccent: _typeAccent,
                  onAdd: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          AddCustomerScreen(contactType: widget.type),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                  itemCount: filteredList.length,
                  itemBuilder: (context, index) {
                    final customer = filteredList[index];
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
                        onLongPress: () =>
                            _tryDeleteCustomer(customer.id, customer.name),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard Card (type-aware labels + accent color)
// ─────────────────────────────────────────────────────────────────────────────

class _DashboardCard extends StatelessWidget {
  final double toReceive;
  final double toPay;
  final String receiveLabel;
  final String payLabel;
  final Color accentColor;
  final VoidCallback onViewReports;

  const _DashboardCard({
    required this.toReceive,
    required this.toPay,
    required this.receiveLabel,
    required this.payLabel,
    required this.accentColor,
    required this.onViewReports,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // This container extends the blue header color downwards slightly behind the white card
        Container(
          height: 40,
          color: const Color(0xFF045CC5),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Top Section: Balances
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            payLabel,
                            style: const TextStyle(
                              color: Color(0xFF5F6368),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _currency.format(toPay),
                            style: const TextStyle(
                              color: Color(0xFF0F9D58), // Green for 'You will give' (or whatever they owe)
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 48,
                      color: Colors.grey.withValues(alpha: 0.3),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            receiveLabel,
                            style: const TextStyle(
                              color: Color(0xFF5F6368),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _currency.format(toReceive),
                            style: const TextStyle(
                              color: Color(0xFFD50000), // Red for 'You will get' 
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Bottom Section: View Reports
              InkWell(
                onTap: onViewReports,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                    border: Border(
                      top: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.picture_as_pdf_outlined,
                        color: Color(0xFF045CC5),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'View Reports',
                        style: TextStyle(
                          color: Color(0xFF045CC5),
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Search and Filter Bar
// ─────────────────────────────────────────────────────────────────────────────

class _SearchAndFilterBar extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final FilterMode currentFilter;
  final ValueChanged<String> onSearch;
  final ValueChanged<FilterMode> onFilter;

  const _SearchAndFilterBar({
    required this.controller,
    required this.hint,
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
          // Search field
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
                hintText: hint,
                hintStyle:
                    TextStyle(color: Colors.grey.shade400, fontSize: 14),
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

// ─────────────────────────────────────────────────────────────────────────────
// Customer / Contact List Card
// ─────────────────────────────────────────────────────────────────────────────

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
    final int balance = ref.watch(customerBalanceProvider(customer.id));
    final lastTxnDate =
        ref.watch(customerLastTransactionProvider(customer.id));

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

    final safeName = safeText(customer.name, fallback: '?');
    final initial = safeName.isNotEmpty ? safeName[0].toUpperCase() : '?';

    // Avatar color per type
    final Color avatarTop;
    final Color avatarBottom;
    switch (customer.contactType) {
      case ContactType.customer:
        avatarTop = const Color(0xFF005CEE);
        avatarBottom = const Color(0xFF5B9BFF);
      case ContactType.supplier:
        avatarTop = const Color(0xFFE65100);
        avatarBottom = const Color(0xFFFF8A65);
      case ContactType.staff:
        avatarTop = const Color(0xFF6A1B9A);
        avatarBottom = const Color(0xFFAB47BC);
    }

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
                // Gradient avatar (color adapts to type)
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [avatarTop, avatarBottom],
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

                // Name + last transaction
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
                            : safeText(customer.phone,
                                fallback: 'No transactions yet'),
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
                      _currency.format(balance.abs() / 100.0),
                      style: TextStyle(
                        color: balanceColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
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

// ─────────────────────────────────────────────────────────────────────────────
// Empty state (per type)
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasItems;
  final String emptyTitle;
  final String addLabel;
  final Color typeAccent;
  final VoidCallback onAdd;

  const _EmptyState({
    required this.hasItems,
    required this.emptyTitle,
    required this.addLabel,
    required this.typeAccent,
    required this.onAdd,
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
              hasItems ? Icons.search_off : Icons.people_outline,
              size: 72,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              hasItems ? 'No matches found' : emptyTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasItems
                  ? 'Try a different name or clear your search.'
                  : 'Tap the button below to add one.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            ),
            if (!hasItems) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.person_add_alt_1),
                label: Text(addLabel),
                style: ElevatedButton.styleFrom(
                  backgroundColor: typeAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
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

// ─────────────────────────────────────────────────────────────────────────────
// Settlement Guard Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

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
    final isOwed = balancePaise > 0;
    final absAmount = _currency.format(balancePaise.abs() / 100.0);
    final color = isOwed ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    final safeName = safeText(name, fallback: 'this contact');
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
            'Cannot Delete Contact',
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
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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

// ─────────────────────────────────────────────────────────────────────────────
// Sync Status Banner
// ─────────────────────────────────────────────────────────────────────────────

class _SyncStatusBanner extends StatelessWidget {
  final SyncStatus status;
  final bool isRestoring;
  final VoidCallback onRetry;

  const _SyncStatusBanner({
    required this.status,
    required this.isRestoring,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final bool showBanner = isRestoring ||
        status == SyncStatus.syncing ||
        status == SyncStatus.failed ||
        status == SyncStatus.offline;

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: showBanner
          ? AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _buildContent(),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildContent() {
    if (isRestoring || status == SyncStatus.syncing) {
      return _bannerContainer(
        key: const ValueKey('syncing'),
        color: const Color(0xFFE3F2FD),
        borderColor: const Color(0xFF90CAF9),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF1565C0),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isRestoring
                    ? 'Restoring your data from cloud...'
                    : 'Syncing your data...',
                style: const TextStyle(
                  color: Color(0xFF1565C0),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (status == SyncStatus.failed) {
      return _bannerContainer(
        key: const ValueKey('failed'),
        color: const Color(0xFFFFF3E0),
        borderColor: const Color(0xFFFFCC80),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Color(0xFFE65100), size: 18),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Sync failed',
                style: TextStyle(
                  color: Color(0xFFE65100),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE65100),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (status == SyncStatus.offline) {
      return _bannerContainer(
        key: const ValueKey('offline'),
        color: const Color(0xFFFCE4EC),
        borderColor: const Color(0xFFF48FB1),
        child: Row(
          children: const [
            Icon(Icons.cloud_off_rounded, color: Color(0xFFC62828), size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'You\'re offline — changes will sync when back online',
                style: TextStyle(
                  color: Color(0xFFC62828),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _bannerContainer({
    required Key key,
    required Color color,
    required Color borderColor,
    required Widget child,
  }) {
    return Container(
      key: key,
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: child,
    );
  }
}
