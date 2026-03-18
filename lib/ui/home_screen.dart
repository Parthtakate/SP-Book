import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/customer_provider.dart';
import '../providers/transaction_provider.dart';
import 'customer/add_customer_screen.dart';
import 'customer/customer_details_screen.dart';

final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

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
              Navigator.pop(context); // Close dialog
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balances = ref.watch(dashboardBalancesProvider);
    final customers = ref.watch(customersProvider);

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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
                  icon: const Icon(Icons.person_add),
                  label: const Text('ADD CUSTOMER'),
                ),
              ],
            ),
          ),
          Expanded(
            child: customers.isEmpty
                ? const Center(child: Text('No customers yet. Add a customer to start.'))
                : ListView.separated(
                    itemCount: customers.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final customer = customers[index];
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
                            subtitle: Text(
                              customer.phone ?? 'No phone',
                            ),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const AddCustomerScreen()));
        },
        icon: const Icon(Icons.person_add),
        label: const Text('ADD CUSTOMER'),
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
