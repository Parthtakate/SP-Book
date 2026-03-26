import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../providers/customer_provider.dart';

class AddCustomerScreen extends ConsumerStatefulWidget {
  const AddCustomerScreen({super.key});

  @override
  ConsumerState<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

class _AddCustomerScreenState extends ConsumerState<AddCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  bool _isImporting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _importContact() async {
    setState(() => _isImporting = true);
    try {
      // Use permission_handler for robust permission handling
      var permissionStatus = await Permission.contacts.status;
      if (permissionStatus.isDenied) {
        permissionStatus = await Permission.contacts.request();
      }

      if (permissionStatus.isPermanentlyDenied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Contacts permission permanently denied.'),
              action: SnackBarAction(
                label: 'Settings',
                onPressed: () => openAppSettings(),
              ),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
        return;
      }

      if (permissionStatus.isGranted || permissionStatus.isLimited) {
        // Fetch contacts with phone + photo thumbnail
        final contacts = await FlutterContacts.getAll(
          properties: {ContactProperty.phone, ContactProperty.photoThumbnail},
        );

        // Only show contacts that have at least one phone number
        final phonedContacts = contacts
            .where((c) => c.phones.isNotEmpty)
            .toList();

        if (phonedContacts.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('No contacts with phone numbers found'),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
          }
          return;
        }

        if (mounted) {
          final selected = await showModalBottomSheet<Contact>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (ctx) => _ContactPickerSheet(contacts: phonedContacts),
          );

          if (selected != null && mounted) {
            setState(() {
              _nameController.text = selected.displayName ?? '';
              if (selected.phones.isNotEmpty) {
                // Clean up number: remove spaces, dashes, parentheses
                _phoneController.text = selected.phones.first.number
                    .replaceAll(RegExp(r'[\s\-\(\)]'), '');
              }
            });
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Contacts permission denied.'),
              action: SnackBarAction(
                label: 'Settings',
                onPressed: () => openAppSettings(),
              ),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to load contacts. Please try again.'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  void _saveCustomer() async {
    if (_formKey.currentState!.validate()) {
      final name = _nameController.text.trim();
      final phone = _phoneController.text.trim();

      await ref.read(customersProvider.notifier).addCustomer(name, phone);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name added successfully!'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Add New Customer',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 20,
                letterSpacing: -0.5)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: Colors.grey.withValues(alpha: 0.1),
            height: 1,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Top Illustration
                      Center(
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: const Color(0xFF005CEE).withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.person_add_rounded,
                            size: 44,
                            color: Color(0xFF005CEE),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Import from contacts button
                      Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: _isImporting ? null : _importContact,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                            decoration: BoxDecoration(
                              border: Border.all(color: const Color(0xFF005CEE).withValues(alpha: 0.3), width: 1.5),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _isImporting
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF005CEE)))
                                    : const Icon(Icons.contacts_rounded, color: Color(0xFF005CEE), size: 22),
                                const SizedBox(width: 12),
                                Text(
                                  _isImporting ? 'Loading Contacts...' : 'Import from Contacts',
                                  style: const TextStyle(
                                    color: Color(0xFF005CEE),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      Row(
                        children: [
                          Expanded(child: Divider(color: Colors.grey.shade300)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text('OR ENTER MANUALLY',
                                style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5)),
                          ),
                          Expanded(child: Divider(color: Colors.grey.shade300)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      // Input Fields Card
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Customer Details',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.grey.shade800)),
                            const SizedBox(height: 16),
                            
                            // Name field
                            TextFormField(
                              controller: _nameController,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                              decoration: InputDecoration(
                                labelText: 'Full Name',
                                labelStyle: TextStyle(color: Colors.grey.shade600),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFF005CEE), width: 1.5),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                prefixIcon: const Icon(Icons.person_outline_rounded, color: Colors.grey),
                              ),
                              textCapitalization: TextCapitalization.words,
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? 'Please enter a name'
                                      : (value.trim().length > 100
                                          ? 'Name is too long (max 100 characters).'
                                          : null),
                            ),
                            const SizedBox(height: 16),
                            
                            // Phone field
                            TextFormField(
                              controller: _phoneController,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                              decoration: InputDecoration(
                                labelText: 'Phone Number',
                                labelStyle: TextStyle(color: Colors.grey.shade600),
                                hintText: 'Required for reminders',
                                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFF005CEE), width: 1.5),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                prefixIcon: const Icon(Icons.phone_outlined, color: Colors.grey),
                              ),
                              keyboardType: TextInputType.phone,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Phone number is required';
                                }
                                final trimmed = value.trim();
                                if (trimmed.length < 6) {
                                  return 'Phone number is too short';
                                }
                                if (trimmed.length > 20) {
                                  return 'Phone number is too long (max 20 characters).';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
            
            // Bottom Save Button
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: const Color(0xFF005CEE),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                  minimumSize: const Size(double.infinity, 56),
                ),
                onPressed: _saveCustomer,
                child: const Text('SAVE CUSTOMER',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A searchable contact picker bottom sheet
class _ContactPickerSheet extends StatefulWidget {
  final List<Contact> contacts;
  const _ContactPickerSheet({required this.contacts});

  @override
  State<_ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<_ContactPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Contact> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.contacts;
    _searchController.addListener(_onSearch);
  }

  void _onSearch() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filtered = widget.contacts
          .where((c) =>
              (c.displayName ?? '').toLowerCase().contains(query) ||
              (c.phones.isNotEmpty &&
                  c.phones.first.number.contains(query)))
          .toList();
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearch);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'Select Contact',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Text(
                      '${_filtered.length} contacts',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                    ),
                  ],
                ),
              ),
              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by name or number...',
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    filled: true,
                    fillColor: const Color(0xFFF5F7FA),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Divider(height: 1),
              // Contact list
              Expanded(
                child: _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off,
                                size: 48, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text('No contacts found',
                                style: TextStyle(color: Colors.grey.shade500)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: _filtered.length,
                        itemBuilder: (context, index) {
                          final contact = _filtered[index];
                          final phone = contact.phones.first.number;
                          final name = contact.displayName ?? '';
                          final initial =
                              name.isNotEmpty ? name[0].toUpperCase() : '?';

                          return ListTile(
                            leading: contact.photo?.thumbnail != null
                                ? CircleAvatar(
                                    backgroundImage:
                                        MemoryImage(contact.photo!.thumbnail!),
                                  )
                                : CircleAvatar(
                                    backgroundColor:
                                        const Color(0xFF005CEE).withValues(alpha: 0.15),
                                    child: Text(
                                      initial,
                                      style: const TextStyle(
                                          color: Color(0xFF005CEE),
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                            title: Text(name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500)),
                            subtitle: Text(phone,
                                style: TextStyle(color: Colors.grey.shade600)),
                            onTap: () => Navigator.pop(context, contact),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
