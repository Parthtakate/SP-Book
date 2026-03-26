import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/customer.dart';
import 'db_provider.dart';
import '../services/firestore_sync_service.dart';

final customersProvider = NotifierProvider<CustomerNotifier, List<Customer>>(() {
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

    // Incremental cloud sync: keeps customers up to date.
    await ref.read(firestoreSyncServiceProvider).syncCustomerUpsert(customer);

    state = db.getAllCustomers();
  }

  Future<void> updateCustomer(Customer customer) async {
    final db = ref.read(dbServiceProvider);
    await db.saveCustomer(customer);

    // Incremental cloud sync: updates the customer document immediately.
    await ref
        .read(firestoreSyncServiceProvider)
        .syncCustomerUpsert(customer);

    state = db.getAllCustomers();
  }

  Future<void> deleteCustomer(String id) async {
    final db = ref.read(dbServiceProvider);

    // Capture transaction ids before local deletion, so we can delete them
    // from Firestore too (avoid orphan transactions on restore).
    final transactionIds = db.transactionsBox.values
        .where((t) => t.customerId == id)
        .map((t) => t.id)
        .toList();

    await db.deleteCustomer(id);

    await ref.read(firestoreSyncServiceProvider).syncCustomerDelete(
          customerId: id,
          transactionIds: transactionIds,
        );

    state = db.getAllCustomers();
  }
}
