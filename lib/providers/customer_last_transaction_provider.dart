import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'transaction_provider.dart';

/// Returns the [DateTime] of the most recent transaction for [customerId].
/// Returns null if the customer has no transactions.
///
/// Watches [customerTransactionsProvider] to stay reactive.
/// Uses the existing sorted order (newest-first) — no extra sort needed.
final customerLastTransactionProvider =
    Provider.autoDispose.family<DateTime?, String>((ref, customerId) {
  final txns = ref.watch(customerTransactionsProvider(customerId));
  if (txns.isEmpty) return null;
  return txns.first.date;
});
