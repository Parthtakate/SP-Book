import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/customer.dart';
import '../../models/transaction.dart';
import '../../providers/transaction_provider.dart';
import 'add_transaction_screen.dart';

class EntryDetailsScreen extends ConsumerStatefulWidget {
  final Customer customer;
  final TransactionModel transaction;
  final List<TransactionModel> allTransactions;

  const EntryDetailsScreen({
    super.key,
    required this.customer,
    required this.transaction,
    required this.allTransactions,
  });

  @override
  ConsumerState<EntryDetailsScreen> createState() => _EntryDetailsScreenState();
}

class _EntryDetailsScreenState extends ConsumerState<EntryDetailsScreen> {
  late int _runningBalancePaise;

  @override
  void initState() {
    super.initState();
    _runningBalancePaise = _calculateRunningBalance();
  }

  Color _getContactColor(ContactType type) {
    switch (type) {
      case ContactType.customer:
        return const Color(0xFF005CEE);
      case ContactType.supplier:
        return const Color(0xFFE65100);
      case ContactType.staff:
        return const Color(0xFF6A1B9A);
    }
  }

  int _calculateRunningBalance() {
    int balance = 0;
    // allTransactions is sorted newest first. Reverse to calculate running balance.
    for (var tx in widget.allTransactions.reversed) {
      if (!tx.isGot) {
        balance += tx.amountInPaise;
      } else {
        balance -= tx.amountInPaise;
      }
      if (tx.id == widget.transaction.id) {
        break;
      }
    }
    return balance;
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final dateFormat = DateFormat('dd MMM yy • hh:mm a');
    final headerColor = _getContactColor(widget.customer.contactType);
    
    final amountText = currency.format(widget.transaction.amountInPaise / 100.0);
    final finalAmountColor = widget.transaction.isGot ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    final typeLabel = widget.transaction.isGot ? 'You got' : 'You gave';

    int runningBalancePaise = _runningBalancePaise;
    final Color rbColor = runningBalancePaise >= 0 ? const Color(0xFF2E7D32) : const Color(0xFFC62828);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Entry Details'),
        backgroundColor: headerColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Content Card 1
          Container(
            color: Colors.white,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.black,
                        child: Text(
                          widget.customer.name.isNotEmpty ? widget.customer.name[0].toUpperCase() : '?',
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.customer.name,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              dateFormat.format(widget.transaction.date),
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(amountText, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: finalAmountColor)),
                          const SizedBox(height: 2),
                          Text(typeLabel, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Running Balance', style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
                      Text(
                        currency.format(runningBalancePaise.abs() / 100.0),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: rbColor),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AddTransactionScreen(
                          customer: widget.customer,
                          isGot: widget.transaction.isGot,
                          existingTransaction: widget.transaction,
                        ),
                      ),
                    ).then((_) {
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.edit, color: headerColor, size: 16),
                        const SizedBox(width: 8),
                        Text('EDIT ENTRY', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: headerColor)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Content Card 2: Message/SMS Section
          Container(
            color: Colors.white,
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 18, color: Colors.grey.shade800),
                      const SizedBox(width: 8),
                      Text('SMS disabled', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'You ${widget.transaction.isGot ? 'got' : 'gave'}: ${currency.format(widget.transaction.amountInPaise / 100.0)}',
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text('Balance: ', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                          Text(
                            '${runningBalancePaise > 0 ? '+' : '-'}(${currency.format(runningBalancePaise.abs() / 100.0)})',
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'https://khatabook.com/t/${widget.transaction.id.substring(0, 10)}', // Dummy link similar to image
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Backup Card
          Container(
            color: Colors.white,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Icon(Icons.cloud_done_outlined, size: 20, color: Colors.grey.shade600),
                const SizedBox(width: 12),
                Text('Entry is backed up', style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Safe & Secure
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.security, color: Colors.green.shade600, size: 18),
              const SizedBox(width: 8),
              Text('100% Safe and Secure', style: TextStyle(color: Colors.green.shade600, fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
          
          const Spacer(),
          
          // Bottom Action Bar
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE0E0E0), width: 1)),
            ),
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red, width: 1),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    onPressed: () => _deleteTransaction(context),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('DELETE', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: headerColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    onPressed: () => _shareEntry(context),
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('SHARE', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteTransaction(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Transaction?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('This transaction will be permanently deleted.'),
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
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      ref.read(transactionServiceProvider).deleteTransaction(widget.transaction.id, widget.customer.id);
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaction deleted')),
        );
      }
    }
  }

  void _shareEntry(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final amountText = currency.format(widget.transaction.amountInPaise / 100.0);
    final text = 'Hi ${widget.customer.name},\n'
        'You ${widget.transaction.isGot ? 'got' : 'gave'}: $amountText\n'
        'Date: ${DateFormat('dd MMM yy').format(widget.transaction.date)}\n'
        'Balance: ${currency.format(_runningBalancePaise.abs() / 100.0)}\n'
        'Shared via SPBOOKS App';
    // ignore: deprecated_member_use
    SharePlus.instance.share(
      ShareParams(
        text: text,
      ),
    );
  }
}
