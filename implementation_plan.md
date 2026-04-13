# Multiple Khatabooks Feature

Allow a single user account to manage multiple separate ledgers ("Khatabooks") — similar to Khatabook's book selector. A user can have e.g. "Shop 1", "Shop 2", and switch between them instantly. All existing data is automatically migrated to a **Default** book with zero data loss.

---

## User Review Required

> [!IMPORTANT]
> **Zero data loss guarantee**: Every existing customer and transaction will be silently migrated to a "Default" Khatabook (named after the existing `businessName` setting). No manual action is needed from the user.

> [!IMPORTANT]
> **Hive adapter forward compatibility**: We append a new `khatabookId` field to `CustomerAdapter` (typeId=0) and `TransactionModelAdapter` (typeId=2) using the **identical** `try/catch` pattern already established in the codebase. Old records read without the field default to `'default'`. No box migration or typeId bump is required.

> [!WARNING]
> **Hive typeId=3 is reserved** for the new `KhatabookAdapter`. Confirm no other adapter uses typeId=3 in any future feature branch before merging.

> [!CAUTION]
> **Firestore security rules** must be extended to allow read/write on the new `users/{uid}/khatabooks/{bookId}` sub-collection. You will need to deploy updated rules to Firebase Console after implementation.

---

## Architecture Decision: Single-Box Approach

Rather than opening separate Hive boxes per book (complex, fragile), we add a `khatabookId: String` field to both `Customer` and `TransactionModel`. All data stays in the existing encrypted `customers` and `transactions` boxes. Providers filter by the **active book ID** from a new `activeKhatabookProvider`.

```
Hive Layout (unchanged box names):
  customers      → [Customer(khatabookId='abc'), Customer(khatabookId='xyz'), ...]
  transactions   → [TransactionModel(khatabookId='abc'), ...]
  khatabooks     → [Khatabook(id='default', name='Trimurti Chikki'), ...]  ← NEW
  settings       → { activeKhatabookId: 'abc', businessName: '...', ... }

Firestore Layout (new sub-collection):
  users/{uid}/khatabooks/{bookId}   ← NEW
  users/{uid}/customers/{id}        (+ khatabookId field)
  users/{uid}/transactions/{id}     (+ khatabookId field)
```

---

## Proposed Changes

### Layer 1 — Data Models

#### [NEW] `lib/models/khatabook.dart`
Brand-new model representing a single ledger/book.

```dart
class Khatabook {
  final String id;        // UUID  
  final String name;      // e.g. "Trimurti Chikki"
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isDeleted;
}
```
- `KhatabookAdapter` with **typeId = 3**
- `toFirestore()` / `fromFirestore()` for Firestore sync
- Stored in new Hive box `'khatabooks'`

---

#### [MODIFY] [customer.dart](file:///c:/Users/hp/.gemini/antigravity/scratch/khata_app/lib/models/customer.dart)
Append `khatabookId` field.

```diff
 class Customer {
+  final String khatabookId;  // which book this contact belongs to

   const Customer({
+    this.khatabookId = 'default',
   });

+  // toFirestore / fromFirestore: add 'khatabookId' key
+  // fromFirestore: data['khatabookId'] as String? ?? 'default'
```

`CustomerAdapter.write()` appends `writer.writeString(obj.khatabookId)` **last**.  
`CustomerAdapter.read()` wraps `reader.readString()` in `try/catch` defaulting to `'default'`.

---

#### [MODIFY] [transaction.dart](file:///c:/Users/hp/.gemini/antigravity/scratch/khata_app/lib/models/transaction.dart)
Append `khatabookId` field with identical pattern.

```diff
 class TransactionModel {
+  final String khatabookId;

   const TransactionModel({
+    this.khatabookId = 'default',
   });
```

---

### Layer 2 — DbService

#### [MODIFY] [db_service.dart](file:///c:/Users/hp/.gemini/antigravity/scratch/khata_app/lib/services/db_service.dart)

**New box constant & field:**
```dart
static const String _khatabooksBox = 'khatabooks';
Box<Khatabook>? _khatabooks;
Box<Khatabook> get khatabooksBox => _khatabooks!;
```

**`init()` changes:**
1. Register `KhatabookAdapter()` (typeId=3) if not already registered
2. Open `_khatabooks` box with the same `encryptionCipher`
3. After opening boxes, call **`_migrateToDefaultBook()`** — a private one-time migration method

**`_migrateToDefaultBook()` — idempotent migration:**
```
- If khatabooksBox is empty:
    - Create a Khatabook(id='default', name=businessName ?? 'My Business')
    - Save it to khatabooksBox
- For every Customer where khatabookId is missing/empty → set to 'default', put back
- For every TransactionModel where khatabookId is missing/empty → set 'default', put back
  (This handles Hive records that pre-date this feature — the try/catch in read() 
   gives 'default', but write() hasn't been called yet so the field isn't persisted.)
```
This migration is O(n) but only runs once — after the first app launch with the new code, all records will have the field persisted.

**New CRUD methods:**
```dart
List<Khatabook> getAllKhatabooks()   // non-deleted, sorted by createdAt
Future<void> saveKhatabook(Khatabook book)
Future<void> deleteKhatabook(String id)  // soft-delete
```

**`activeKhatabookId` stored in `_settings` box:**
```dart
String get activeKhatabookId =>
    _settings?.get('activeKhatabookId', defaultValue: 'default') ?? 'default';

Future<void> setActiveKhatabookId(String id) async =>
    await _settings?.put('activeKhatabookId', id);
```

**`clearAll()` updated** to also clear the khatabooks box.

**`autopurgeDeletedItems()` updated** to purge soft-deleted Khatabooks > 30 days.

---

### Layer 3 — FirestoreBackupService

#### [MODIFY] [firestore_backup_service.dart](file:///c:/Users/hp/.gemini/antigravity/scratch/khata_app/lib/services/firestore_backup_service.dart)

**`backupAll()`** — add khatabooks to ops:
```dart
for (final b in db.khatabooksBox.values.toList()) {
  final ref = _firestore
      .collection('users').doc(uid)
      .collection('khatabooks').doc(b.id);
  ops.add(_WriteOp(ref: ref, data: b.toFirestore()));
}
```

**`backupIncremental()`** — handle `type == 'khatabook'` in the queue loop:
```dart
} else if (type == 'khatabook') {
  ref = _firestore.collection('users').doc(uid).collection('khatabooks').doc(id);
}
// Then for 'set' action: db.khatabooksBox.get(id)?.toFirestore()
```

**`restoreAll()`** — fetch khatabooks collection concurrently (add to `Future.wait`), merge with same last-write-wins logic:
```dart
final results = await Future.wait([
  ...,  // existing customers + transactions
  _withAuthRetry(() => _firestore
      .collection('users').doc(uid).collection('khatabooks')
      .get().timeout(...)),
]);
```

---

### Layer 4 — Riverpod Providers

#### [NEW] `lib/providers/khatabook_provider.dart`

```dart
// All khatabooks for the current user
final khatabooksProvider = 
    NotifierProvider<KhatabookNotifier, List<Khatabook>>(...);

class KhatabookNotifier extends Notifier<List<Khatabook>> {
  List<Khatabook> build() => ref.watch(dbServiceProvider).getAllKhatabooks();

  Future<void> addKhatabook(String name) async { ... }
  Future<void> renameKhatabook(String id, String newName) async { ... }
  Future<void> deleteKhatabook(String id) async { ... }
}

// The currently active book ID (persisted in settings)
final activeKhatabookIdProvider =
    NotifierProvider<ActiveKhatabookNotifier, String>(...);

class ActiveKhatabookNotifier extends Notifier<String> {
  String build() => ref.watch(dbServiceProvider).activeKhatabookId;

  Future<void> switchTo(String bookId) async {
    await ref.read(dbServiceProvider).setActiveKhatabookId(bookId);
    state = bookId;
    // Invalidate data providers so lists refresh for the new book
    ref.invalidate(customersProvider);
    ref.invalidate(customerBalanceMapProvider);
    ref.invalidate(dashboardBalancesProvider);
  }
}

// Derived: the active Khatabook object
final activeKhatabookProvider = Provider<Khatabook?>((ref) {
  final books = ref.watch(khatabooksProvider);
  final id = ref.watch(activeKhatabookIdProvider);
  return books.firstWhereOrNull((b) => b.id == id);
});
```

---

#### [MODIFY] [customer_provider.dart](file:///c:/Users/hp/.gemini/antigravity/scratch/khata_app/lib/providers/customer_provider.dart)

**`CustomerNotifier.build()`** — filter by active book:
```dart
List<Customer> build() {
  final activeId = ref.watch(activeKhatabookIdProvider);
  return ref.watch(dbServiceProvider)
      .getAllCustomers()
      .where((c) => c.khatabookId == activeId)
      .toList();
}
```

**`addCustomer()`** — tag with active book ID:
```dart
final customer = Customer(
  ...
  khatabookId: ref.read(activeKhatabookIdProvider),
);
```

---

#### [MODIFY] [auto_sync_provider.dart](file:///c:/Users/hp/.gemini\antigravity/scratch/khata_app/lib/providers/auto_sync_provider.dart)

**`_invalidateDataProviders()`** — add `ref.invalidate(khatabooksProvider)`.

---

### Layer 5 — UI

#### [NEW] `lib/ui/khatabook/khatabook_selector_sheet.dart`
A `showModalBottomSheet` widget (matches the screenshot exactly):

- **Book list**: Each row shows avatar (2-letter initials, colored circle), book name, customer count, and a blue checkmark ✓ for the active book.
- **"+ CREATE NEW KHATABOOK" button**: Blue full-width button at the bottom.
- Tapping a book calls `ref.read(activeKhatabookIdProvider.notifier).switchTo(book.id)` and pops the sheet.
- Each book has a subtle long-press context menu: **Rename** | **Delete** (only allowed if > 1 book exists).

#### [NEW] `lib/ui/khatabook/create_khatabook_dialog.dart`
A dialog with a single text field. On submit:
```dart
ref.read(khatabooksProvider.notifier).addKhatabook(name);
ref.read(activeKhatabookIdProvider.notifier).switchTo(newBook.id);
```

---

#### [MODIFY] [home_screen.dart](file:///c:/Users/hp/.gemini/antigravity/scratch/khata_app/lib/ui/home_screen.dart)

**`_buildAppBar()`** — Replace the static "SPBOOKS" `Text` title with a `_KhatabookSelectorButton`:

```dart
// Before:
Text('SPBOOKS', style: ...)

// After:
_KhatabookSelectorButton()
```

**`_KhatabookSelectorButton`** (private widget in home_screen.dart):
```dart
class _KhatabookSelectorButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(activeKhatabookProvider);
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        builder: (_) => const KhatabookSelectorSheet(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(book?.name ?? 'My Business',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down, color: Colors.white),
        ],
      ),
    );
  }
}
```

The existing logo `Image.asset` is moved to the leading slot (AppBar's `leading:` property) or kept as a small prefix icon in the Row.

---

#### [MODIFY] [settings_screen.dart](file:///c:/Users/hp/.gemini/antigravity/scratch/khata_app/lib/ui/settings_screen.dart)

Add a **"Manage Khatabooks"** list tile that opens the `KhatabookSelectorSheet` (or a dedicated management screen). This gives users a settings-level entry point in addition to the AppBar button.

---

### Layer 6 — Firestore Security Rules

```javascript
// ADD to existing rules:
match /users/{uid}/khatabooks/{bookId} {
  allow read, write: if request.auth != null && request.auth.uid == uid
      && request.resource.data.keys().hasAll(['id','name','createdAt','isDeleted'])
      && request.resource.data.name is string
      && request.resource.data.name.size() <= 100;
}

// UPDATE customers and transactions rules to validate khatabookId:
// + && request.resource.data.khatabookId is string
```

---

## Open Questions

> [!IMPORTANT]
> **Q1 — PDF Reports scope**: When the user generates a PDF report, should it cover only the **active Khatabook's** contacts, or allow the user to choose a book? My recommendation: default to active book, with a book picker on the Reports screen.

> [!IMPORTANT]
> **Q2 — CSV Export scope**: Same question for CSV export in Settings. Scoped to active book or all books?

> [!IMPORTANT]
> **Q3 — Recycle Bin scoping**: Should the Recycle Bin show deleted items from **all books** or only the active book? Recommendation: all books with a book-name label per item.

> [!IMPORTANT]
> **Q4 — Book deletion behavior**: If a user deletes a Khatabook that still has customers in it, what happens? Options: (a) Block deletion unless book is empty, (b) Soft-delete the book and all its customers/transactions cascade. Recommendation: option (a) with a warning count.

---

## Verification Plan

### Automated Tests
- Update `test/balance_logic_test.dart` to test balance calculations with `khatabookId` filtering
- Add unit tests for `KhatabookNotifier.addKhatabook()`, `switchTo()`, and migration logic

### Manual Verification
1. **Fresh install**: App creates a Default book → all flows work as before (zero regression)
2. **Upgrade from old build**: Existing customers are migrated to Default book → customer list shows correctly
3. **Create 2nd book**: Switch books → customer list is empty for the new book (isolated)
4. **Add customers to each book**: Switch between books → each shows only its own customers
5. **Balance summary**: Dashboard totals are scoped to the active book only
6. **PDF/CSV reports**: Generated with correct book scope
7. **Firestore sync**: Both books backup/restore correctly on a second device
8. **Recycle Bin**: Deleted items show the correct book label

---

## Execution Order (Phases)

| Phase | Files | Risk |
|-------|-------|------|
| 1 | `khatabook.dart` model + `KhatabookAdapter` | Low |
| 2 | Update `Customer` + `TransactionModel` (append field) | Low |
| 3 | `DbService` — new box, migration, CRUD, settings key | Medium |
| 4 | `FirestoreBackupService` — khatabooks collection | Medium |
| 5 | `khatabook_provider.dart` + update `customer_provider.dart` | Medium |
| 6 | `KhatabookSelectorSheet` + `CreateKhatabookDialog` UI | Low |
| 7 | `home_screen.dart` AppBar title → KhatabookSelectorButton | Low |
| 8 | `settings_screen.dart` — Manage Khatabooks tile | Low |
| 9 | Firestore rules update | Low |
| 10 | Tests + manual verification | — |
