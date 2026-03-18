import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/customer_provider.dart';
import '../providers/transaction_provider.dart';
import '../providers/db_provider.dart';
import '../models/customer.dart';
import 'customer/add_customer_screen.dart';
import 'customer/customer_details_screen.dart';

final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

enum FilterMode { all, toReceive, toPay }

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _searchQuery = '';
  FilterMode _filterMode = FilterMode.all;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showDeleteConfirmation(BuildContext context, WidgetRef ref, String customerId, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Customer?'),
        content: Text('Are you sure you want to delete "$name" and all their transactions? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          TextButton(
            onPressed: () {
              ref.read(customersProvider.notifier).deleteCustomer(customerId);
              Navigator.pop(context);
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final balances = ref.watch(dashboardBalancesProvider);
    final allCustomers = ref.watch(customersProvider);
    final db = ref.watch(dbServiceProvider);
    
    // Watch transaction changes to ensure filter rebuilds when a transaction is added
    ref.watch(anyTransactionChangeProvider);

    // Apply Search and Filtering
    final List<Customer> filteredCustomers = allCustomers.where((c) {
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final nameMatches = c.name.toLowerCase().contains(query);
        final phoneMatches = c.phone?.toLowerCase().contains(query) ?? false;
        if (!nameMatches && !phoneMatches) return false;
      }

      if (_filterMode != FilterMode.all) {
        final transactions = db.getTransactionsForCustomer(c.id);
        double balance = 0;
        for (var t in transactions) {
          if (t.isGot) balance -= t.amount;
          else balance += t.amount;
        }
        
        if (_filterMode == FilterMode.toReceive && balance <= 0) return false;
        if (_filterMode == FilterMode.toPay && balance >= 0) return false;
      }
      
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('📘 Khata Book', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildDashboardCard(context, balances['toReceive'] ?? 0, balances['toPay'] ?? 0),
          
          // Search and Filter Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by Name or Phone',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                    });
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildFilterChip('All', FilterMode.all),
                    const SizedBox(width: 8),
                    _buildFilterChip('To Receive', FilterMode.toReceive),
                    const SizedBox(width: 8),
                    _buildFilterChip('To Pay', FilterMode.toPay),
                  ],
                ),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Your Customers',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AddCustomerScreen()));
                  },
                  icon: const Icon(Icons.person_add, size: 18),
                  label: const Text('ADD CUSTOMER'),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: filteredCustomers.isEmpty
                ? Center(
                    child: Text(
                      allCustomers.isEmpty 
                          ? 'No customers yet. Add a customer to start.'
                          : 'No matching customers found.',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.separated(
                    itemCount: filteredCustomers.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final customer = filteredCustomers[index];
                      // Even though we calculated balance for filtering, we watch it here for UI specifically.
                      return Consumer(
                        builder: (context, ref, child) {
                          final balance = ref.watch(customerBalanceProvider(customer.id));
                          
                          Color subColor = Colors.grey;
                          String subtitle = 'Settled up';
                          if (balance > 0) {
                            subColor = Colors.green;
                            subtitle = 'Will give you';
                          } else if (balance < 0) {
                            subColor = Colors.red;
                            subtitle = 'You will give';
                          }

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                              child: Text(customer.name.substring(0, 1).toUpperCase()),
                            ),
                            title: Text(customer.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(customer.phone ?? 'No phone'),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  currencyFormat.format(balance.abs()),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: subColor,
                                  ),
                                ),
                                Text(
                                  subtitle,
                                  style: TextStyle(fontSize: 12, color: subColor),
                                ),
                              ],
                            ),
                            onTap: () {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailsScreen(customer: customer)));
                            },
                            onLongPress: () {
                              _showDeleteConfirmation(context, ref, customer.id, customer.name);
                            },
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, FilterMode mode) {
    final isSelected = _filterMode == mode;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _filterMode = mode;
          });
        }
      },
      selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
      checkmarkColor: Theme.of(context).colorScheme.primary,
      labelStyle: TextStyle(
        color: isSelected ? Theme.of(context).colorScheme.primary : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildDashboardCard(BuildContext context, double toReceive, double toPay) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            offset: const Offset(0, 4),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('You will give', style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  currencyFormat.format(toPay),
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 22),
                ),
              ],
            ),
          ),
          Container(height: 40, width: 1, color: Colors.grey.shade300),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('You will get', style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  currencyFormat.format(toReceive),
                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 22),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
