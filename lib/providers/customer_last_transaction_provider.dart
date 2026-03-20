import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'db_provider.dart';
import 'transaction_provider.dart';

/// Returns the [DateTime] of the most recent transaction for [customerId].
/// Returns null if the customer has no transactions.
///
/// Piggybacks on [anyTransactionChangeProvider] to stay reactive.
/// Uses the existing sorted order from [DbService.getTransactionsForCustomer]
/// (already sorted newest-first) — no extra sort needed.
final customerLastTransactionProvider =
    Provider.family<DateTime?, String>((ref, customerId) {
  ref.watch(anyTransactionChangeProvider);
  final db = ref.watch(dbServiceProvider);
  final txns = db.getTransactionsForCustomer(customerId);
  if (txns.isEmpty) return null;
  return txns.first.date;
});
