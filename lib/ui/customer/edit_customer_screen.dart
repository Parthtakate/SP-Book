import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/customer.dart';
import '../../providers/customer_provider.dart';

class EditCustomerScreen extends ConsumerStatefulWidget {
  final Customer customer;

  const EditCustomerScreen({super.key, required this.customer});

  @override
  ConsumerState<EditCustomerScreen> createState() => _EditCustomerScreenState();
}

class _EditCustomerScreenState extends ConsumerState<EditCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late ContactType _contactType;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.customer.name);
    _contactType = widget.customer.contactType;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _saveCustomer() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final updated = widget.customer.copyWith(
        name: _nameController.text.trim(),
        contactType: _contactType,
        updatedAt: DateTime.now(),
      );
      await ref.read(customersProvider.notifier).updateCustomer(updated);
      if (mounted) {
        Navigator.pop(context, updated);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${updated.name} updated successfully!'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Per-type helpers ──────────────────────────────────────────────────────

  Color _accentFor(ContactType type) {
    switch (type) {
      case ContactType.customer:
        return const Color(0xFF005CEE);
      case ContactType.supplier:
        return const Color(0xFFE65100);
      case ContactType.staff:
        return const Color(0xFF6A1B9A);
    }
  }

  IconData _iconFor(ContactType type) {
    switch (type) {
      case ContactType.customer:
        return Icons.person_rounded;
      case ContactType.supplier:
        return Icons.store_rounded;
      case ContactType.staff:
        return Icons.badge_rounded;
    }
  }

  String _labelFor(ContactType type) {
    switch (type) {
      case ContactType.customer:
        return 'Customer';
      case ContactType.supplier:
        return 'Supplier';
      case ContactType.staff:
        return 'Staff';
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accentFor(_contactType);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Edit Contact',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20, letterSpacing: -0.5),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.withValues(alpha: 0.1), height: 1),
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
                      // Top illustration — icon adapts to current type
                      Center(
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _iconFor(_contactType),
                            size: 44,
                            color: accent,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // ── Contact Type selector (Khatabook-style 3 chips) ──
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
                            Text(
                              'Contact Type',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.grey.shade800,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: ContactType.values.map((type) {
                                final isSelected = _contactType == type;
                                final typeAccent = _accentFor(type);
                                return Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      right: type != ContactType.staff ? 8 : 0,
                                    ),
                                    child: GestureDetector(
                                      onTap: () =>
                                          setState(() => _contactType = type),
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 200),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 10),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? typeAccent
                                              : Colors.grey.shade100,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                            color: isSelected
                                                ? typeAccent
                                                : Colors.grey.shade300,
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            Icon(
                                              _iconFor(type),
                                              color: isSelected
                                                  ? Colors.white
                                                  : Colors.grey,
                                              size: 20,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _labelFor(type),
                                              style: TextStyle(
                                                color: isSelected
                                                    ? Colors.white
                                                    : Colors.grey.shade600,
                                                fontSize: 11,
                                                fontWeight: isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Name + Phone card ──
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
                            Text(
                              'Contact Details',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.grey.shade800,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Name field (editable)
                            TextFormField(
                              controller: _nameController,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w500),
                              decoration: InputDecoration(
                                labelText: 'Full Name',
                                labelStyle:
                                    TextStyle(color: Colors.grey.shade600),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      BorderSide(color: accent, width: 1.5),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 16),
                                prefixIcon: const Icon(
                                    Icons.person_outline_rounded,
                                    color: Colors.grey),
                              ),
                              textCapitalization: TextCapitalization.words,
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? 'Please enter a name'
                                      : (value.trim().length > 100
                                          ? 'Name too long (max 100 characters).'
                                          : null),
                            ),
                            const SizedBox(height: 16),

                            // Phone field (read-only)
                            TextFormField(
                              initialValue:
                                  widget.customer.phone ?? 'No phone saved',
                              readOnly: true,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade400,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Phone Number (cannot be changed)',
                                labelStyle:
                                    TextStyle(color: Colors.grey.shade500),
                                filled: true,
                                fillColor: Colors.grey.shade100,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 16),
                                prefixIcon: Icon(Icons.phone_outlined,
                                    color: Colors.grey.shade400),
                                suffixIcon: Tooltip(
                                  message:
                                      'Phone number cannot be changed\nonce a customer is created.',
                                  child: Icon(Icons.lock_outline,
                                      color: Colors.grey.shade400, size: 18),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Phone is linked to the customer ID and cannot be changed.',
                              style: TextStyle(
                                  color: Colors.grey.shade400, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom save button
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
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                  minimumSize: const Size(double.infinity, 56),
                ),
                onPressed: _isSaving ? null : _saveCustomer,
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        'SAVE CHANGES',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
