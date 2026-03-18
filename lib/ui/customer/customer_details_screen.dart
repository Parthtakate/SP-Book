import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/customer.dart';
import '../../providers/transaction_provider.dart';
import '../transaction/add_transaction_screen.dart';

final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

class CustomerDetailsScreen extends ConsumerWidget {
  final Customer customer;

  const CustomerDetailsScreen({super.key, required this.customer});

  void _showImageFullscreen(BuildContext context, String imagePath) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              child: Image.file(
                File(imagePath), 
                fit: BoxFit.contain, 
                width: double.infinity, 
                height: double.infinity
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(customerBalanceProvider(customer.id));
    final transactions = ref.watch(customerTransactionsProvider(customer.id));

    String balanceStatus = 'Settled Up';
    Color balanceColor = Colors.grey;
    if (balance > 0) {
      balanceStatus = 'You will get';
      balanceColor = Colors.green;
    } else if (balance < 0) {
      balanceStatus = 'You will give';
      balanceColor = Colors.red;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(customer.name),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            color: balanceColor.withOpacity(0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      balanceStatus,
                      style: TextStyle(color: balanceColor, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      currencyFormat.format(balance.abs()),
                      style: TextStyle(color: balanceColor, fontWeight: FontWeight.bold, fontSize: 24),
                    ),
                  ],
                ),
                Icon(
                  Icons.account_balance_wallet,
                  size: 40,
                  color: balanceColor,
                ),
              ],
            ),
          ),
          
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('All Transactions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          
          Expanded(
            child: transactions.isEmpty
                ? const Center(child: Text('No transactions yet.'))
                : ListView.builder(
                    itemCount: transactions.length,
                    itemBuilder: (context, index) {
                      final t = transactions[index];
                      return ListTile(
                        leading: t.imagePath != null
                          ? GestureDetector(
                              onTap: () => _showImageFullscreen(context, t.imagePath!),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.file(
                                  File(t.imagePath!), 
                                  width: 40, 
                                  height: 40, 
                                  fit: BoxFit.cover
                                ),
                              ),
                            )
                          : const SizedBox(width: 40, child: Icon(Icons.receipt_long, color: Colors.grey)),
                        title: Text(
                          t.isGot ? 'You Got' : 'You Gave', 
                          style: TextStyle(
                            color: t.isGot ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold
                          )
                        ),
                        subtitle: Text('${dateFormat.format(t.date)}${t.note.isNotEmpty ? '\nNote: ${t.note}' : ''}'),
                        isThreeLine: t.note.isNotEmpty,
                        trailing: Text(
                          currencyFormat.format(t.amount),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      );
                    },
                  ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => AddTransactionScreen(customer: customer, isGot: false)
                        ));
                      },
                      child: const Text('🔴 YOU GAVE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => AddTransactionScreen(customer: customer, isGot: true)
                        ));
                      },
                      child: const Text('🟢 YOU GOT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
