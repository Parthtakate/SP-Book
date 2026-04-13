import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/khatabook.dart';
import 'db_provider.dart';
import 'customer_provider.dart';
import 'transaction_provider.dart';
import 'reports_provider.dart';

// ---------------------------------------------------------------------------
// All Khatabooks list
// ---------------------------------------------------------------------------

class KhatabookNotifier extends Notifier<List<Khatabook>> {
  @override
  List<Khatabook> build() => ref.watch(dbServiceProvider).getAllKhatabooks();

  Future<void> addKhatabook(String name) async {
    final db = ref.read(dbServiceProvider);
    final book = Khatabook(
      id: const Uuid().v4(),
      name: name.trim(),
      createdAt: DateTime.now(),
    );
    await db.saveKhatabook(book);
    state = db.getAllKhatabooks();
  }

  Future<void> renameKhatabook(String id, String newName) async {
    final db = ref.read(dbServiceProvider);
    final book = db.khatabooksBox.get(id);
    if (book == null) return;
    final updated = book.copyWith(
      name: newName.trim(),
      updatedAt: DateTime.now(),
    );
    await db.saveKhatabook(updated);
    state = db.getAllKhatabooks();
  }

  /// Tries to soft-delete a Khatabook.
  /// Returns false (and does NOT delete) if the book still has active contacts.
  /// The caller is responsible for showing an error to the user.
  Future<bool> deleteKhatabook(String id) async {
    final db = ref.read(dbServiceProvider);
    final count = db.customerCountForBook(id);
    if (count > 0) return false;
    await db.softDeleteKhatabook(id);
    state = db.getAllKhatabooks();
    return true;
  }
}

final khatabooksProvider =
    NotifierProvider<KhatabookNotifier, List<Khatabook>>(
  KhatabookNotifier.new,
);

// ---------------------------------------------------------------------------
// Active Khatabook ID — persisted to Hive settings box
// ---------------------------------------------------------------------------

class ActiveKhatabookNotifier extends Notifier<String> {
  @override
  String build() => ref.watch(dbServiceProvider).activeKhatabookId;

  Future<void> switchTo(String bookId) async {
    await ref.read(dbServiceProvider).setActiveKhatabookId(bookId);
    state = bookId;
    _invalidateAll();
  }

  void _invalidateAll() {
    ref.invalidate(customersProvider);
    ref.invalidate(customerBalanceMapProvider);
    ref.invalidate(dashboardBalancesProvider);
    ref.invalidate(accountStatementProvider);
  }
}

final activeKhatabookIdProvider =
    NotifierProvider<ActiveKhatabookNotifier, String>(
  ActiveKhatabookNotifier.new,
);

// ---------------------------------------------------------------------------
// Active Khatabook object — derived from list + active ID
// ---------------------------------------------------------------------------

final activeKhatabookProvider = Provider<Khatabook?>((ref) {
  final books = ref.watch(khatabooksProvider);
  final id = ref.watch(activeKhatabookIdProvider);
  try {
    return books.firstWhere((b) => b.id == id);
  } catch (_) {
    return books.isEmpty ? null : books.first;
  }
});
