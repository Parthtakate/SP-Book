import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/customer.dart';
import 'db_provider.dart';
import 'transaction_provider.dart';

// ---------------------------------------------------------------------------
// Filter State (autoDispose = resets when home screen leaves scope)
// ---------------------------------------------------------------------------

enum FilterMode { all, toReceive, toPay }

final filterModeProvider = NotifierProvider.autoDispose<FilterModeNotifier, FilterMode>(
  () => FilterModeNotifier(),
);

class FilterModeNotifier extends Notifier<FilterMode> {
  @override
  FilterMode build() => FilterMode.all;
  void setFilter(FilterMode mode) => state = mode;
}

final searchQueryProvider = NotifierProvider.autoDispose<SearchQueryNotifier, String>(
  () => SearchQueryNotifier(),
);

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';
  void updateQuery(String query) => state = query;
}

// ---------------------------------------------------------------------------
// Customers
// ---------------------------------------------------------------------------

final customersProvider =
    NotifierProvider<CustomerNotifier, List<Customer>>(() {
  return CustomerNotifier();
});

class CustomerNotifier extends Notifier<List<Customer>> {
  @override
  List<Customer> build() {
    return ref.watch(dbServiceProvider).getAllCustomers();
  }

  Future<void> addCustomer(String name, String? phone) async {
    final customer = Customer(
      id: const Uuid().v4(),
      name: name,
      phone: phone,
      createdAt: DateTime.now(),
    );
    final db = ref.read(dbServiceProvider);
    await db.saveCustomer(customer);
    state = db.getAllCustomers();
  }

  Future<void> updateCustomer(Customer customer) async {
    final db = ref.read(dbServiceProvider);
    await db.saveCustomer(customer);
    state = db.getAllCustomers();
  }

  Future<void> deleteCustomer(String id) async {
    final db = ref.read(dbServiceProvider);
    await db.deleteCustomer(id);
    state = db.getAllCustomers();
  }
}

// ---------------------------------------------------------------------------
// Filtered customer list (reactive — recomputes only when inputs change)
// ---------------------------------------------------------------------------

/// Derives a filtered and searched customer list from Riverpod providers.
/// This replaces the inline computation that previously lived in build().
/// Uses `autoDispose` so it tears down when the home screen is popped.
final filteredCustomersProvider =
    Provider.autoDispose<List<Customer>>((ref) {
  final customers = ref.watch(customersProvider);
  final filterMode = ref.watch(filterModeProvider);
  final query = ref.watch(searchQueryProvider).toLowerCase().trim();
  final balanceMap = ref.watch(customerBalanceMapProvider);

  return customers.where((c) {
    // Search filter
    if (query.isNotEmpty) {
      final nameMatch = c.name.toLowerCase().contains(query);
      final phoneMatch = c.phone?.toLowerCase().contains(query) ?? false;
      if (!nameMatch && !phoneMatch) return false;
    }

    // Balance filter
    if (filterMode != FilterMode.all) {
      final balancePaise = balanceMap[c.id] ?? 0;
      if (filterMode == FilterMode.toReceive && balancePaise <= 0) return false;
      if (filterMode == FilterMode.toPay && balancePaise >= 0) return false;
    }

    return true;
  }).toList();
});
