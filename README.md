# Khata App (SP-Book)

A professional Ledger (Khata) management application built to help users seamlessly track balances, credit, and debit transactions ("You Got" / "You Gave") completely offline, with secure cloud backup capabilities using Firebase. This app serves as a robust offline-first clone of traditional ledger apps like Khatabook, with performance and security optimizations.

---

## 🚀 What Is Implemented

The application currently supports the following core features:

1. **Multiple ledgers/Khatabooks**: Manage multiple independent businesses or ledgers seamlessly with visual initials and separate transaction data.
2. **Contact Categories**: Create and manage multiple types of contacts including Customers, Suppliers, and Staff. Accent colors and labels adapt dynamically.
3. **Transaction Management**: Record "You Got" (Credit) and "You Gave" (Debit) transactions instantly with real-time running balance calculation.
4. **Professional PDF Reports**: Generate and share customized, printer-friendly PDF statements at both the Customer level and the Khatabook/Ledger level.
5. **Offline-First Architecture**: 100% of the read and write operations happen locally in under 1ms, regardless of network connectivity. 
6. **Cloud Backup (Firestore Auto-Sync)**: Encrypted local data is safely pushed to Firebase Firestore periodically without blocking the UI.
7. **Secure App Lock**: Native biometric authentication (FaceID/Fingerprint) utilizing `local_auth`.

---

## 🏗️ Architecture & Proper Flow of Every Model

The application follows a **Modular Service-Provider Architecture** designed for high scalability and separation of concerns.

### Tech Stack
*   **UI & State**: Flutter (Dart) + Riverpod (`flutter_riverpod`).
*   **Local Database**: Hive (`hive_flutter`) for instant synchronous access.
*   **Remote Backend**: Firebase Firestore & Firebase Auth.

### 🔄 The Data Flow
1. **User Action**: The user interacts with the UI Screen (e.g., adds a transaction).
2. **Provider Layer**: The screen signals the `Provider` (`transaction_provider.dart` or `customer_provider.dart`), which manages the state.
3. **Service & Local DB Layer**: The Provider immediately calls `db_service.dart`. `db_service` writes the changes synchronously to the Hive Box and returns the updated list.
4. **UI Update**: The Provider emits the new State, and the UI re-renders instantly (Zero latency).
5. **Cloud Sync**: In the background, `firestore_backup_service.dart` listens to these local Hive changes (or syncs periodically) and pushes the JSON-serialized data to Firebase Firestore for safe backup.

### 📦 The Models

#### 1. `Khatabook` (`lib/models/khatabook.dart`)
*   **Role**: Represents an independent ledger or business entity (e.g., "Trimurti Chikki", "Personal Expenses").
*   **Flow**: Stored in Hive `typeId = 3`. The `khatabook_provider` loads all ledgers, allowing the user to switch the "Active Ledger". All Customers and Transactions belong to a specific `khatabookId` (defaults to 'default' for legacy migration).

#### 2. `Customer` (`lib/models/customer.dart`)
*   **Role**: Represents an individual entity the business transacts with. 
*   **Fields**: Tracks `contactType` (Customer, Supplier, Staff) and connects to a parent Ledger securely via `khatabookId`.
*   **Flow**: Saved in Hive `typeId = 0`. The UI relies on `customer_provider` to fetch a list of customers strictly filtered by the currently active `Khatabook`. If deleted, it flips an `isDeleted` soft-delete flag to satisfy the sync mechanism.

#### 3. `TransactionModel` (`lib/models/transaction.dart`)
*   **Role**: Represents a financial entry (`amountInPaise`, `isGot`, `note`, `date`).
*   **Flow**: Saved in Hive `typeId = 2`. Tied directly to a `customerId` and a `khatabookId`. The transaction list is pulled down when the user accesses `EntryDetailsScreen`, dynamically calculating the running balances instantly inside the state. Supports attaching optional images (`imagePath`).

#### 4. `ReminderModel` (`lib/models/reminder.dart`)
*   **Role**: Handles custom reminders regarding payments. 
*   **Flow**: Unlike the core transaction ledger, Reminders are stored loosely and mapped seamlessly to Firestore (for scheduled push notifications if necessary) avoiding heavy relation dependencies.

---

## 🔮 Features We Should Implement in the End

To reach full feature completion and parity with top enterprise solutions, the following features remain:

1. **Cloud Image Storage**: Implement `FirebaseStorage` (or Supabase Storage) to upload transaction receipt images reliably. Currently, image paths check the local directory; they need seamless upload to the cloud and download fetching to persist across devices.
2. **Multi-Device Live Sync**: Upgrade the current "Backup/Restore" implementation into a real-time listening stream via Firestore for simultaneous usage across multiple phones.
3. **Advanced Charts & Analytics**: Integrate graphical dashboards (pie charts/bar graphs) to visualize cash flow, top given/taken, and seasonal trends over custom date ranges.
4. **Granular Staff Permissions**: Implement role-based access for `Staff` contacts, where an employee can add entries but cannot delete transactions or view total business profit.
5. **Business Card & QR Code Builder**: Let merchants generate their business card or UPI payment QR Code directly from their ledger profile.
6. **SMS Gateway Integration**: Automatically fire official SMS payment reminders with deep links for immediate debt settlement instead of just WhatsApp share intents.
