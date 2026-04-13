import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/khatabook.dart';
import '../../providers/db_provider.dart';
import '../../providers/khatabook_provider.dart';

// ---------------------------------------------------------------------------
// Khatabook Selector Sheet
// ---------------------------------------------------------------------------

/// A draggable bottom sheet that lists all Khatabooks and allows the user to:
///   • Switch to a different book
///   • Long-press to rename or delete a non-default book
///   • Create a new book via the "+ CREATE" button
class KhatabookSelectorSheet extends ConsumerWidget {
  const KhatabookSelectorSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(khatabooksProvider);
    final activeId = ref.watch(activeKhatabookIdProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // ── Drag handle ────────────────────────────────────────────────
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // ── Header ─────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Text(
                      'My Khatabooks',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${books.length} book${books.length == 1 ? '' : 's'}',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),
              Divider(color: Colors.grey.shade100, height: 1),

              // ── Book list ──────────────────────────────────────────────────
              Expanded(
                child: books.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: books.length,
                        itemBuilder: (ctx, i) => _BookTile(
                          book: books[i],
                          isActive: books[i].id == activeId,
                        ),
                      ),
              ),

              // ── Create button ──────────────────────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16, 8, 16, MediaQuery.of(context).viewPadding.bottom + 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF005CEE),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text(
                      '+ CREATE NEW KHATABOOK',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, letterSpacing: 0.5),
                    ),
                    onPressed: () => _showCreateDialog(context, ref),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.menu_book_rounded, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('No Khatabooks yet',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade500)),
          const SizedBox(height: 4),
          Text('Create your first book below.',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
        ],
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => const _CreateKhatabookDialog(),
    );
    if (result != null && result.trim().isNotEmpty && context.mounted) {
      await ref.read(khatabooksProvider.notifier).addKhatabook(result);
      // Switch to the newly created book
      final books = ref.read(khatabooksProvider);
      if (books.isNotEmpty) {
        await ref
            .read(activeKhatabookIdProvider.notifier)
            .switchTo(books.last.id);
      }
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}

// ---------------------------------------------------------------------------
// Individual book tile inside the sheet
// ---------------------------------------------------------------------------

class _BookTile extends ConsumerWidget {
  final Khatabook book;
  final bool isActive;

  const _BookTile({required this.book, required this.isActive});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(dbServiceProvider);
    final contactCount = db.customerCountForBook(book.id);

    return InkWell(
      onTap: () async {
        await ref
            .read(activeKhatabookIdProvider.notifier)
            .switchTo(book.id);
        if (context.mounted) Navigator.of(context).pop();
      },
      onLongPress: book.id == 'default'
          ? null
          : () => _showContextMenu(context, ref, contactCount),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Initials avatar
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFF005CEE).withValues(alpha: 0.12)
                    : Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                book.initials,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isActive
                      ? const Color(0xFF005CEE)
                      : Colors.grey.shade600,
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Name + customer count
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight:
                          isActive ? FontWeight.w700 : FontWeight.w500,
                      color: isActive
                          ? const Color(0xFF005CEE)
                          : const Color(0xFF1E293B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$contactCount contact${contactCount == 1 ? '' : 's'}',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),

            // Active checkmark or long-press hint
            if (isActive)
              const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF005CEE), size: 22)
            else if (book.id != 'default')
              Icon(Icons.more_vert_rounded,
                  color: Colors.grey.shade400, size: 20),
          ],
        ),
      ),
    );
  }

  void _showContextMenu(
      BuildContext context, WidgetRef ref, int contactCount) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 3,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.edit_outlined,
                  color: Color(0xFF005CEE)),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameDialog(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: Colors.red),
              title:
                  const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _tryDelete(context, ref, contactCount);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _showRenameDialog(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: book.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rename Khatabook',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 50,
          decoration: const InputDecoration(
            hintText: 'Enter new name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF005CEE),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('RENAME'),
          ),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty && context.mounted) {
      await ref
          .read(khatabooksProvider.notifier)
          .renameKhatabook(book.id, result);
    }
  }

  Future<void> _tryDelete(
      BuildContext context, WidgetRef ref, int contactCount) async {
    if (contactCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Remove all $contactCount contact${contactCount == 1 ? '' : 's'} from "${book.name}" first before deleting.'),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Khatabook',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(
            'Are you sure you want to delete "${book.name}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCEL')),
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
    ) ?? false;

    if (confirmed && context.mounted) {
      final deleted = await ref
          .read(khatabooksProvider.notifier)
          .deleteKhatabook(book.id);
      if (!deleted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not delete "${book.name}".'),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Create New Khatabook Dialog
// ---------------------------------------------------------------------------

class _CreateKhatabookDialog extends StatefulWidget {
  const _CreateKhatabookDialog();

  @override
  State<_CreateKhatabookDialog> createState() => _CreateKhatabookDialogState();
}

class _CreateKhatabookDialogState extends State<_CreateKhatabookDialog> {
  final _ctrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'New Khatabook',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _ctrl,
          autofocus: true,
          maxLength: 50,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'e.g. Trimurti Chikki',
            labelText: 'Khatabook Name',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.menu_book_rounded),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Please enter a name';
            if (v.trim().length < 2) return 'Name must be at least 2 characters';
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF005CEE),
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () {
            if (_formKey.currentState?.validate() ?? false) {
              Navigator.pop(context, _ctrl.text.trim());
            }
          },
          child: const Text('CREATE'),
        ),
      ],
    );
  }
}
