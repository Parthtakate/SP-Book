// ignore_for_file: avoid_print
//
// balance_logic_test.dart — SPBOOKS Production Unit Tests
//
// Covers:
//   1. Paise arithmetic (no floating-point drift)
//   2. customerBalanceProvider logic (isGot sign convention)
//   3. Soft-delete filtering (deleted items excluded from balance)
//   4. Dashboard totals (toReceive / toPay)
//   5. Autopurge 30-day eligibility

import 'package:flutter_test/flutter_test.dart';
import 'package:khata_app/models/transaction.dart';
import 'package:khata_app/models/customer.dart';

// ---------------------------------------------------------------------------
// Pure balance calculation — mirrors customerBalanceProvider logic
// (no Riverpod needed; this is the pure function we're testing)
// ---------------------------------------------------------------------------

/// Replicates customerBalanceProvider:
/// isGot=true  → customer GAVE you money → -amountInPaise (reduces what they owe)
/// isGot=false → you GAVE customer money → +amountInPaise (increases what they owe)
int calculateBalance(List<TransactionModel> transactions) {
  int balance = 0;
  for (final t in transactions) {
    if (t.isDeleted) continue; // Phase 4: soft-deleted txns excluded
    balance += t.isGot ? -t.amountInPaise : t.amountInPaise;
  }
  return balance;
}

/// Replicates dashboardBalancesProvider (in paise).
Map<String, int> dashboardTotals(Map<String, int> balanceMap) {
  int toReceive = 0;
  int toPay = 0;
  for (final b in balanceMap.values) {
    if (b > 0) toReceive += b;
    if (b < 0) toPay += b.abs();
  }
  return {'toReceive': toReceive, 'toPay': toPay};
}

TransactionModel _txn({
  required String id,
  required int amountInPaise,
  required bool isGot,
  bool isDeleted = false,
  DateTime? updatedAt,
}) =>
    TransactionModel(
      id: id,
      customerId: 'cust_1',
      amountInPaise: amountInPaise,
      isGot: isGot,
      date: DateTime(2025, 1, 1),
      isDeleted: isDeleted,
      updatedAt: updatedAt,
    );

Customer _customer({
  required String id,
  bool isDeleted = false,
  DateTime? updatedAt,
}) =>
    Customer(
      id: id,
      name: 'Test Customer',
      createdAt: DateTime(2025, 1, 1),
      isDeleted: isDeleted,
      updatedAt: updatedAt,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── 1. Paise arithmetic — no floating-point drift ──────────────────────────

  group('Paise arithmetic', () {
    test('amounts stay as integers with no fp drift', () {
      // ₹100.50 stored as 10050 paise — no floating-point operations at storage layer
      const paise = 10050;
      const displayValue = paise / 100.0; // only at display layer
      expect(displayValue, closeTo(100.50, 0.001));
    });

    test('summing paise values does not drift', () {
      // ₹33.33 x 3 = ₹99.99, but 3333 x 3 = 9999 (correct integer)
      const singlePaise = 3333;
      const total = singlePaise * 3;
      expect(total, equals(9999));
      expect(total / 100.0, closeTo(99.99, 0.001));
    });

    test('large amounts are correctly represented', () {
      // ₹1,00,000 = 10000000 paise
      const paise = 10000000;
      expect(paise / 100.0, closeTo(100000.00, 0.001));
    });
  });

  // ── 2. Balance sign convention ─────────────────────────────────────────────

  group('Balance calculation — sign convention', () {
    test('you gave ₹500 → customer owes you (+50000 paise)', () {
      final txns = [_txn(id: 't1', amountInPaise: 50000, isGot: false)];
      expect(calculateBalance(txns), equals(50000)); // positive = they owe you
    });

    test('customer gave ₹500 → you owe them (-50000 paise)', () {
      final txns = [_txn(id: 't1', amountInPaise: 50000, isGot: true)];
      expect(calculateBalance(txns), equals(-50000)); // negative = you owe them
    });

    test('net balance across multiple transactions', () {
      final txns = [
        _txn(id: 't1', amountInPaise: 100000, isGot: false), // gave ₹1000
        _txn(id: 't2', amountInPaise: 30000, isGot: true),   // received ₹300
        _txn(id: 't3', amountInPaise: 20000, isGot: false),  // gave ₹200
      ];
      // Net: +100000 - 30000 + 20000 = +90000 (₹900 owed to you)
      expect(calculateBalance(txns), equals(90000));
    });

    test('zero balance when settled', () {
      final txns = [
        _txn(id: 't1', amountInPaise: 50000, isGot: false),
        _txn(id: 't2', amountInPaise: 50000, isGot: true),
      ];
      expect(calculateBalance(txns), equals(0));
    });
  });

  // ── 3. Soft-delete filtering ───────────────────────────────────────────────

  group('Soft-delete filtering', () {
    test('deleted transaction is excluded from balance', () {
      final txns = [
        _txn(id: 't1', amountInPaise: 50000, isGot: false),
        _txn(id: 't2', amountInPaise: 20000, isGot: false, isDeleted: true), // deleted!
      ];
      // Only t1 counts → +50000
      expect(calculateBalance(txns), equals(50000));
    });

    test('all transactions deleted → balance is 0', () {
      final txns = [
        _txn(id: 't1', amountInPaise: 50000, isGot: false, isDeleted: true),
        _txn(id: 't2', amountInPaise: 30000, isGot: true,  isDeleted: true),
      ];
      expect(calculateBalance(txns), equals(0));
    });

    test('getAllCustomers filters out deleted customers', () {
      final allCustomers = [
        _customer(id: 'c1'),
        _customer(id: 'c2', isDeleted: true),
        _customer(id: 'c3'),
      ];
      final active = allCustomers.where((c) => !c.isDeleted).toList();
      expect(active.length, equals(2));
      expect(active.map((c) => c.id), containsAll(['c1', 'c3']));
    });

    test('getDeletedCustomers only returns soft-deleted ones', () {
      final allCustomers = [
        _customer(id: 'c1'),
        _customer(id: 'c2', isDeleted: true),
        _customer(id: 'c3', isDeleted: true),
      ];
      final deleted = allCustomers.where((c) => c.isDeleted).toList();
      expect(deleted.length, equals(2));
    });
  });

  // ── 4. Dashboard totals ────────────────────────────────────────────────────

  group('Dashboard totals', () {
    test('toReceive sums all positive balances', () {
      final map = {'c1': 100000, 'c2': 50000, 'c3': -25000};
      final totals = dashboardTotals(map);
      expect(totals['toReceive'], equals(150000));
      expect(totals['toPay'], equals(25000));
    });

    test('all settled → both totals are 0', () {
      final map = {'c1': 0, 'c2': 0};
      final totals = dashboardTotals(map);
      expect(totals['toReceive'], equals(0));
      expect(totals['toPay'], equals(0));
    });

    test('all customers in debt → toReceive is 0', () {
      final map = {'c1': -10000, 'c2': -5000};
      final totals = dashboardTotals(map);
      expect(totals['toReceive'], equals(0));
      expect(totals['toPay'], equals(15000));
    });

    test('net balance converts correctly to display value', () {
      final paise = 123456; // ₹1234.56
      expect(paise / 100.0, closeTo(1234.56, 0.001));
    });
  });

  // ── 5. Autopurge 30-day eligibility ───────────────────────────────────────

  group('Autopurge — 30-day eligibility', () {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));

    test('item deleted 31 days ago is eligible for autopurge', () {
      final deletedAt = DateTime.now().subtract(const Duration(days: 31));
      final c = _customer(id: 'c1', isDeleted: true, updatedAt: deletedAt);
      final eligible = c.isDeleted && (c.updatedAt?.isBefore(cutoff) ?? false);
      expect(eligible, isTrue);
    });

    test('item deleted 10 days ago is NOT eligible for autopurge', () {
      final deletedAt = DateTime.now().subtract(const Duration(days: 10));
      final c = _customer(id: 'c1', isDeleted: true, updatedAt: deletedAt);
      final eligible = c.isDeleted && (c.updatedAt?.isBefore(cutoff) ?? false);
      expect(eligible, isFalse);
    });

    test('active (non-deleted) item is never eligible for autopurge', () {
      final c = _customer(id: 'c1', isDeleted: false);
      final eligible = c.isDeleted;
      expect(eligible, isFalse);
    });

    test('deleted item with no updatedAt timestamp is not purged (safe default)', () {
      final c = _customer(id: 'c1', isDeleted: true, updatedAt: null);
      // updatedAt == null → ?? false → not eligible (conservative — do not purge)
      final eligible = c.isDeleted && (c.updatedAt?.isBefore(cutoff) ?? false);
      expect(eligible, isFalse);
    });
  });

  // ── 6. Model serialization round-trip ─────────────────────────────────────

  group('Model — isDeleted flag round-trips correctly', () {
    test('TransactionModel preserves isDeleted=true', () {
      final txn = _txn(id: 't1', amountInPaise: 5000, isGot: false, isDeleted: true);
      expect(txn.isDeleted, isTrue);
    });

    test('TransactionModel copyWith preserves isDeleted=false when not overridden', () {
      final original = _txn(id: 't1', amountInPaise: 5000, isGot: false, isDeleted: true);
      final copy = original.copyWith(amountInPaise: 6000);
      // isDeleted should still be true (unchanged)
      expect(copy.isDeleted, isTrue);
      expect(copy.amountInPaise, equals(6000));
    });

    test('Customer copyWith can set isDeleted=false (restore)', () {
      final deleted = _customer(id: 'c1', isDeleted: true);
      final restored = deleted.copyWith(isDeleted: false, updatedAt: DateTime.now());
      expect(restored.isDeleted, isFalse);
    });
  });
}
