# Fix Data Inconsistency in Running Balance Calculation

There's a critical performance issue in `EntryDetailsScreen` where `_calculateRunningBalance()` executes an O(N) loop on every single `build()`. Since `build()` can be called up to 60 times a second during animations or scrolling, an O(N) loop with 5000+ items will easily cause dropped frames and severe jank.

## Proposed Strategy

You suggested two valid approaches:
1. **Best Fix:** Pre-compute a list or provider with running balances for all transactions.
2. **Alternative (Lighter):** Cache the calculation inside the screen's state (`StatefulWidget`).

**Decision:** I have chosen to implement the **Alternative (Lighter)** approach by converting `EntryDetailsScreen` to a `ConsumerStatefulWidget`.

**Why?**
Because currently, *no other screen* (not even `CustomerDetailsScreen` or `ContactLedgerScreen`) needs the per-transaction running balance rendered dynamically in a list. If we use a global provider to pre-compute a map of 5,000 running balances, we allocate O(N) memory just for `EntryDetailsScreen` to read **one** single value. 
By calculating it once in `initState` of `EntryDetailsScreen`, we get the exact same UI performance benefit (O(N) computation only happens **once** when the screen opens), but with **O(1)** memory. It is simply the most optimal solution for our specific use case.

## Proposed Changes

### `lib/ui/transaction/entry_details_screen.dart`
- Change `EntryDetailsScreen` from a `ConsumerWidget` to a `ConsumerStatefulWidget`.
- Create a `late int _runningBalancePaise;` state variable.
- Move `_calculateRunningBalance()` into the `_EntryDetailsScreenState` class.
- Override `initState()` to call `_runningBalancePaise = _calculateRunningBalance();` once.
- In `build()`, replace `int runningBalancePaise = _calculateRunningBalance();` with simply `int runningBalancePaise = _runningBalancePaise;`.
- Use `_runningBalancePaise` in `_shareEntry()` to avoid recalculating it there as well.

## User Review Required
> [!IMPORTANT]
> Please review this plan. The `StatefulWidget` fix perfectly solves the jank issue and uses zero extra memory. If you still strictly want the global provider approach so you can show running balances in `CustomerDetailsScreen` in the future, let me know and I will happily implement the provider instead!

## Verification Plan

### Manual Verification
- Open the app and navigate to a customer with transactions.
- Tap on an entry. The screen should push smoothly.
- The Running Balance displayed should be completely accurate.
- Sharing the entry should display the correct running balance in the shared text.
