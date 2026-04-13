import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/customer.dart';
import '../../providers/customer_provider.dart';
import '../../providers/db_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../services/pdf_service.dart';
import 'reports_screen.dart';

class ReportsHubScreen extends ConsumerStatefulWidget {
  final ContactType initialTab;

  const ReportsHubScreen({super.key, this.initialTab = ContactType.customer});

  @override
  ConsumerState<ReportsHubScreen> createState() => _ReportsHubScreenState();
}

class _ReportsHubScreenState extends ConsumerState<ReportsHubScreen> {
  final List<String> _tabs = ['All', 'Customer', 'Bills', 'GST', 'Day-wise'];
  late String _selectedTab;
  bool _isGeneratingPdf = false;

  @override
  void initState() {
    super.initState();
    _selectedTab = _mapContactTypeToTab(widget.initialTab);
  }

  String _mapContactTypeToTab(ContactType type) {
    if (type == ContactType.customer) return 'Customer';
    // Suppliers and Staff aren't explicitly in the image mockup, we could map them to 'All' or just default to Customer.
    return 'Customer'; 
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _generateCustomerListPdf() async {
    if (_isGeneratingPdf) return;
    setState(() => _isGeneratingPdf = true);
    
    try {
      _showSnack('Generating PDF...');
      
      final db = ref.read(dbServiceProvider);
      final businessName = db.getBusinessName() ?? 'My Business';
      
      // Get all customers and balance maps
      final allCustomers = ref.read(customersProvider);
      final balanceMap = ref.read(customerBalanceMapProvider);

      final filePath = await PdfService.generateCustomerListPdfPath(
        customers: allCustomers,
        balanceMap: balanceMap,
        businessName: businessName,
      );

      if (filePath.isNotEmpty && mounted) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(filePath)],
            text: 'Customer List Report',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Error generating PDF');
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingPdf = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), // Light grey matching Khatabook
      appBar: AppBar(
        title: const Text('View Reports'),
        backgroundColor: const Color(0xFF045CC5), // Khatabook-style deep blue
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Tabs
          Container(
            color: const Color(0xFFF5F7FA),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: _tabs.map((tab) => _buildTabChip(tab)).toList(),
              ),
            ),
          ),

          // Content Box
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300, width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text(
                          '$_selectedTab Reports',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),

                      if (_selectedTab == 'Customer') ...[
                        // Item 1: Customer Transactions report
                        _buildReportTile(
                          icon: Icons.receipt_long_outlined,
                          title: 'Customer Transactions report',
                          subtitle: 'Summary of all customer transactions',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ReportsScreen(
                                  filterType: ContactType.customer,
                                ),
                              ),
                            );
                          },
                        ),
                        
                        Divider(height: 1, thickness: 1, color: Colors.grey.shade100, indent: 64),
                        
                        // Item 2: Customer list pdf
                        _buildReportTile(
                          icon: Icons.picture_as_pdf_outlined,
                          title: 'Customer list pdf',
                          subtitle: 'List of all Customers',
                          isLoading: _isGeneratingPdf,
                          onTap: _generateCustomerListPdf,
                        ),
                      ] else ...[
                        // Placeholder for other tabs
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(
                            child: Text(
                              'No reports available for $_selectedTab yet.',
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
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

  Widget _buildTabChip(String label) {
    final isSelected = _selectedTab == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: () => setState(() => _selectedTab = label),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? const Color(0xFF045CC5) : Colors.grey.shade300,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? const Color(0xFF045CC5) : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReportTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isLoading = false,
  }) {
    return InkWell(
      onTap: isLoading ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF045CC5), size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            if (isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(Icons.chevron_right, color: Colors.black, size: 24),
          ],
        ),
      ),
    );
  }
}
