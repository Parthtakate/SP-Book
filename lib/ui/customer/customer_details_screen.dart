import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/customer.dart';
import '../../models/transaction.dart';
import '../../providers/transaction_provider.dart';
import '../reminder/set_reminder_screen.dart';
import '../reports/reports_screen.dart';
import '../transaction/add_transaction_screen.dart';
import 'edit_customer_screen.dart';
import '../../services/pdf_service.dart';
import '../../services/safe_text.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
final _timeFormat = DateFormat('hh:mm a');
final _dateHeaderFormat = DateFormat('EEEE, d MMM yyyy');

/// Groups a flat list of transactions into {date -> List[TransactionModel]} map.
/// The map maintains insertion order (newest date first) because we sort by date descending.
Map<String, List<TransactionModel>> _groupByDate(
    List<TransactionModel> txns) {
  final grouped = <String, List<TransactionModel>>{};
  for (final t in txns) {
    final key = DateFormat('yyyy-MM-dd').format(t.date);
    grouped.putIfAbsent(key, () => []).add(t);
  }
  return grouped;
}

class CustomerDetailsScreen extends ConsumerStatefulWidget {
  final Customer customer;

  const CustomerDetailsScreen({super.key, required this.customer});

  @override
  ConsumerState<CustomerDetailsScreen> createState() => _CustomerDetailsScreenState();
}

class _CustomerDetailsScreenState extends ConsumerState<CustomerDetailsScreen> {
  DateTimeRange? _filterRange;

  // ---- Image fullscreen ------------------------------------------------
  void _showImageFullscreen(BuildContext context, String imagePath) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
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
                height: double.infinity,
                errorBuilder: (context, error, stackTrace) =>
                    const Center(
                  child: Icon(Icons.broken_image_outlined,
                      size: 64, color: Colors.white54),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Actions ---------------------------------------------------------
  Future<void> _callCustomer(BuildContext context) async {
    if (widget.customer.phone == null || widget.customer.phone!.isEmpty) {
      _showSnack(context, 'No phone number saved for this customer.');
      return;
    }
    final url = Uri.parse('tel:${widget.customer.phone}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (context.mounted) _showSnack(context, 'Could not open phone dialer.');
    }
  }

  Future<void> _showWhatsAppOptions(
    BuildContext context,
    int balancePaise,
    List<TransactionModel> transactions,
  ) async {
    if (widget.customer.phone == null || widget.customer.phone!.isEmpty) {
      _showSnack(context, 'No phone number saved for this customer.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Send via WhatsApp',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              widget.customer.name,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            // Option 1: PDF statement
            _WhatsAppOption(
              icon: Icons.picture_as_pdf_outlined,
              iconColor: const Color(0xFF1565C0),
              title: 'Send Account Statement (PDF)',
              subtitle: 'Generate & share full ledger statement',
              onTap: () {
                Navigator.pop(ctx);
                _shareStatementViaWhatsApp(context, balancePaise, transactions);
              },
            ),
            const SizedBox(height: 12),
            // Option 2: Quick text
            _WhatsAppOption(
              icon: Icons.chat_bubble_outline_rounded,
              iconColor: const Color(0xFF25D366),
              title: 'Send Quick Reminder',
              subtitle: 'Send a payment reminder message',
              onTap: () {
                Navigator.pop(ctx);
                _sendQuickWhatsApp(context, balancePaise);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareStatementViaWhatsApp(
    BuildContext context,
    int balancePaise,
    List<TransactionModel> transactions,
  ) async {
    _showSnack(context, 'Generating statement PDF…');
    try {
      final filePath = await PdfService.generateCustomerStatementPdfPath(
        customer: widget.customer,
        transactions: transactions,
        balance: balancePaise / 100.0,
        dateRange: _filterRange,
      );
      final msg = 'Hi ${widget.customer.name}, please find your account '
          'statement attached. Pending balance: '
          '${_currency.format(balancePaise.abs() / 100.0)}. Please clear it soon.';
      // ignore: deprecated_member_use
      await Share.shareXFiles([XFile(filePath)], text: msg);
    } catch (e) {
      if (context.mounted) {
        _showSnack(context, 'Could not generate PDF. Try again.');
      }
    }
  }

  Future<void> _sendQuickWhatsApp(BuildContext context, int balancePaise) async {
    final msg =
        'Hi ${widget.customer.name}, your pending balance is '
        '${_currency.format(balancePaise.abs() / 100.0)}. Please clear it soon.';
        
    String phoneStr = widget.customer.phone ?? '';
    phoneStr = phoneStr.replaceAll(RegExp(r'[^\d+]'), ''); // Keep only digits and +
    if (phoneStr.length == 10 && !phoneStr.startsWith('+')) {
      phoneStr = '+91$phoneStr';
    } else if (phoneStr.length == 12 && phoneStr.startsWith('91')) {
      phoneStr = '+$phoneStr';
    }

    final url = Uri.parse(
        'whatsapp://send?phone=$phoneStr&text=${Uri.encodeComponent(msg)}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      final smsUrl = Uri.parse(
          'sms:$phoneStr?body=${Uri.encodeComponent(msg)}');
      if (await canLaunchUrl(smsUrl)) {
        await launchUrl(smsUrl);
      } else {
        if (context.mounted) {
          _showSnack(context, 'Could not open WhatsApp or SMS.');
        }
      }
    }
  }

  void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ---- Build -----------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final int balance = ref.watch(customerBalanceProvider(widget.customer.id));
    final transactions = ref.watch(customerTransactionsProvider(widget.customer.id));
    
    var filteredTransactions = transactions;
    if (_filterRange != null) {
      filteredTransactions = transactions.where((t) {
        final date = DateTime(t.date.year, t.date.month, t.date.day);
        final start = DateTime(_filterRange!.start.year, _filterRange!.start.month, _filterRange!.start.day);
        final end = DateTime(_filterRange!.end.year, _filterRange!.end.month, _filterRange!.end.day);
        return !date.isBefore(start) && !date.isAfter(end);
      }).toList();
    }

    final bool owesYou = balance > 0;
    final bool youOwe = balance < 0;
    final String balanceStatus = owesYou
        ? 'You will get'
        : youOwe
            ? 'You will give'
            : 'Settled Up';
    final Color headerColor =
        owesYou ? const Color(0xFF2E7D32) : youOwe ? const Color(0xFFC62828) : Colors.grey;

    final grouped = _groupByDate(filteredTransactions);
    // Build a flat list of items: header strings + transaction objects
    final List<dynamic> flatList = [];
    for (final entry in grouped.entries) {
      flatList.add(entry.key); // date header
      flatList.addAll(entry.value);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Column(
        children: [
          // ----------------------------------------------------------------
          // Gradient header (replaces AppBar)
          // ----------------------------------------------------------------
          _GradientHeader(
            customer: widget.customer,
            balance: balance,
            balanceStatus: balanceStatus,
            headerColor: headerColor,
            isFiltered: _filterRange != null,
            onBack: () => Navigator.pop(context),
            onEdit: () async {
              await Navigator.push<Customer>(
                context,
                MaterialPageRoute(
                  builder: (_) => EditCustomerScreen(customer: widget.customer),
                ),
              );
              // Riverpod state is automatically updated via customersProvider
              // — no extra invalidation needed here.
            },
            onFilter: () async {
              if (_filterRange != null) {
                // Clear filter
                setState(() => _filterRange = null);
                return;
              }
              final initialRange = DateTimeRange(
                start: DateTime.now().subtract(const Duration(days: 30)),
                end: DateTime.now(),
              );
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 1)),
                initialDateRange: initialRange,
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: ColorScheme.light(
                        primary: headerColor,
                        onPrimary: Colors.white,
                        onSurface: Colors.black,
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              if (picked != null) {
                setState(() => _filterRange = picked);
              }
            },
            onCall: () => _callCustomer(context),
            onReminder: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SetReminderScreen(customer: widget.customer),
              ),
            ),
            onReport: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReportsScreen()),
            ),
            onExportPdf: () async {
              try {
                // Show a brief snackbar
                _showSnack(context, 'Generating PDF...');
                await PdfService.generateAndShareCustomerStatement(
                  customer: widget.customer,
                  transactions: transactions,
                  balance: balance / 100.0,
                  dateRange: _filterRange,
                );
              } catch (e) {
                if (context.mounted) {
                  _showSnack(context, 'Error generating PDF. Please try again.');
                }
              }
            },
            onWhatsApp: () => _showWhatsAppOptions(context, balance, transactions),
            showWhatsApp: owesYou,
            onSettle: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Settle Balance?'),
                  content: Text('This will add a ${balance > 0 ? "You Got" : "You Gave"} transaction of ${_currency.format(balance.abs() / 100.0)} to bring the balance to ₹0.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: headerColor,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(ctx, true), 
                      child: const Text('SETTLE')
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                ref.read(transactionServiceProvider).addTransaction(
                  customerId: widget.customer.id,
                  // balance is already in paise — use directly, no need to multiply
                  amountInPaise: balance.abs(),
                  isGot: balance > 0,
                  note: 'Balance Settled',
                );
              }
            },
          ),

          // ----------------------------------------------------------------
          // Transaction list (grouped by date)
          // ----------------------------------------------------------------
          Expanded(
            child: filteredTransactions.isEmpty
                ? const _EmptyTransactions()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: flatList.length,
                    itemBuilder: (context, index) {
                      final item = flatList[index];
                      if (item is String) {
                        // Date header
                        return _DateHeader(dateKey: item);
                      }
                      final t = item as TransactionModel;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _TransactionCard(
                          transaction: t,
                          onImageTap: t.imagePath != null
                              ? () =>
                                  _showImageFullscreen(context, t.imagePath!)
                              : null,
                          onDelete: () {
                            ref
                                .read(transactionServiceProvider)
                                .deleteTransaction(t.id, widget.customer.id);
                          },
                          onEdit: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AddTransactionScreen(
                                  customer: widget.customer,
                                  isGot: t.isGot,
                                  existingTransaction: t,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),

          // ----------------------------------------------------------------
          // Bottom action bar
          // ----------------------------------------------------------------
          _BottomActionBar(
            customer: widget.customer,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Gradient Header
// ---------------------------------------------------------------------------

class _GradientHeader extends StatelessWidget {
  final Customer customer;
  final int balance;
  final String balanceStatus;
  final Color headerColor;
  final bool isFiltered;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onFilter;
  final VoidCallback onCall;
  final VoidCallback onReminder;
  final VoidCallback onReport;
  final VoidCallback onExportPdf;
  final VoidCallback onWhatsApp;
  final bool showWhatsApp;
  final VoidCallback onSettle;

  const _GradientHeader({
    required this.customer,
    required this.balance,
    required this.balanceStatus,
    required this.headerColor,
    required this.isFiltered,
    required this.onBack,
    required this.onEdit,
    required this.onFilter,
    required this.onCall,
    required this.onReminder,
    required this.onReport,
    required this.onExportPdf,
    required this.onWhatsApp,
    required this.showWhatsApp,
    required this.onSettle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            headerColor.withValues(alpha: 0.9),
            headerColor,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Back + Title row
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: onBack,
                  ),
                  Expanded(
                    child: Text(
                      safeText(customer.name, fallback: 'Unknown'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Phase 4: Edit customer button
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: Colors.white),
                    tooltip: 'Edit Customer',
                    onPressed: onEdit,
                  ),
                  if (isFiltered)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('Filtered', style: TextStyle(color: Colors.white, fontSize: 10)),
                    ),
                  IconButton(
                    icon: Icon(
                      isFiltered ? Icons.filter_alt_off : Icons.filter_alt,
                      color: Colors.white,
                    ),
                    onPressed: onFilter,
                  ),
                ],
              ),
            ),

            // Balance
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        balanceStatus,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _currency.format(balance.abs() / 100.0),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (balance != 0)
                    ElevatedButton.icon(
                      onPressed: onSettle,
                      icon: const Icon(Icons.handshake, size: 16),
                      label: const Text('Settle', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: headerColor,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        elevation: 0,
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Action row
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  _ActionButton(
                    icon: Icons.bar_chart_rounded,
                    label: 'Report',
                    onTap: onReport,
                  ),
                  const SizedBox(width: 12),
                  _ActionButton(
                    icon: Icons.picture_as_pdf_outlined,
                    label: 'Export',
                    onTap: onExportPdf,
                  ),
                  const SizedBox(width: 12),
                  _ActionButton(
                    icon: Icons.notifications_outlined,
                    label: 'Reminder',
                    onTap: onReminder,
                  ),
                  const SizedBox(width: 12),
                  _ActionButton(
                    icon: Icons.call_outlined,
                    label: 'Call',
                    onTap: onCall,
                  ),
                  if (showWhatsApp) ...[
                    const SizedBox(width: 12),
                    _ActionButton(
                      icon: Icons.message_outlined,
                      label: 'WhatsApp',
                      onTap: onWhatsApp,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 70, // fixed width for single child scroll view constraints
      margin: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Date Header
// ---------------------------------------------------------------------------

class _DateHeader extends StatelessWidget {
  final String dateKey; // 'yyyy-MM-dd'
  const _DateHeader({required this.dateKey});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse(dateKey);
    final now = DateTime.now();
    final String label;

    final yesterday = now.subtract(const Duration(days: 1));

    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      label = 'Today';
    } else if (date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day) {
      label = 'Yesterday';
    } else {
      label = _dateHeaderFormat.format(date);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
                fontWeight: FontWeight.w600,
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

// ---------------------------------------------------------------------------
// Transaction Card
// ---------------------------------------------------------------------------

class _TransactionCard extends StatelessWidget {
  final TransactionModel transaction;
  final VoidCallback? onImageTap;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _TransactionCard({
    required this.transaction,
    required this.onDelete,
    required this.onEdit,
    this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final isGot = t.isGot;

    final Color tagColor =
        isGot ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    final Color bgColor =
        isGot ? const Color(0xFFF1F8F1) : const Color(0xFFFFF1F1);
    final String typeLabel = isGot ? 'YOU GOT' : 'YOU GAVE';

    return Dismissible(
      key: Key(t.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.red),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Text('Delete Transaction?',
                style: TextStyle(fontWeight: FontWeight.bold)),
            content: const Text(
                'This transaction will be permanently deleted.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCEL'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('DELETE'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => onDelete(),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
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
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Type badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  typeLabel,
                  style: TextStyle(
                    color: tagColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    letterSpacing: 0.5,
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Note + time
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (t.note.isNotEmpty)
                      Text(
                        safeText(t.note),
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 3),
                    Text(
                      _timeFormat.format(t.date),
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Amount + optional image thumbnail
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _currency.format(t.amountInPaise / 100.0),
                    style: TextStyle(
                      color: tagColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  if (t.imagePath != null) ...[
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: onImageTap,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(
                          File(t.imagePath!),
                          width: 36,
                          height: 36,
                          fit: BoxFit.cover,
                          cacheWidth: 108,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(Icons.broken_image_outlined,
                                size: 18, color: Colors.grey.shade400),
                          ),
                        ),
                      ),
                    ),
                ],
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

class _EmptyTransactions extends StatelessWidget {
  const _EmptyTransactions();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No transactions yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap "YOU GAVE" or "YOU GOT"\nbelow to add the first entry.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom Action Bar
// ---------------------------------------------------------------------------

class _BottomActionBar extends StatelessWidget {
  final Customer customer;
  const _BottomActionBar({required this.customer});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: _BottomButton(
                  label: 'YOU GAVE',
                  icon: Icons.arrow_upward_rounded,
                  color: const Color(0xFFC62828),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          AddTransactionScreen(customer: customer, isGot: false),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BottomButton(
                  label: 'YOU GOT',
                  icon: Icons.arrow_downward_rounded,
                  color: const Color(0xFF2E7D32),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          AddTransactionScreen(customer: customer, isGot: true),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _BottomButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ],
      ),
    );
  }
}


// ---------------------------------------------------------------------------
// WhatsApp Option Tile (used in bottom sheet)
// ---------------------------------------------------------------------------
class _WhatsAppOption extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _WhatsAppOption({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade500)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
          ],
        ),
      ),
    );
  }
}
