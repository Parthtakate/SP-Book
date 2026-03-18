import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/customer.dart';
import 'db_provider.dart';

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
