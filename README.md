# Khata App (SP-Book)

A professional Ledger (Khata) management application built to help users seamlessly track balances, credit, and debit transactions ("You Got" / "You Gave") completely offline with secure cloud backup capabilities using Firebase.

## 🛠️ Tech Stack From Scratch

This project adopts a modern and scalable tech stack tailored for high performance on mobile devices.

### 1. Frontend (UI & State)
*   **Flutter (Dart)**: Used to build the cross-platform mobile UI. Provides native-level performance.
*   **Riverpod (`flutter_riverpod`)**: Responsible for State Management. It bridges the UI with backend services asynchronously, ensuring the UI remains reactive to data changes.

### 2. Backend & Cloud (Firebase Integration)
*   **Firebase Authentication & Google Sign-In**: Handles secure user authentication (`auth_service.dart`).
*   **Cloud Firestore (`cloud_firestore`)**: Works as our remote backend database to store encrypted backups (`firestore_backup_service.dart`). 

### 3. Local Database & Security
*   **Hive (`hive_flutter`)**: Our lightning-fast, NoSQL local database. This makes the app **Offline-First**, meaning all writes/reads happen locally under 1ms.
*   **Flutter Secure Storage**: We encrypt the Hive boxes and store the 256-bit encryption key securely in the device's keystore/keychain.
*   **Local Auth**: Integrates native biometrics (Fingerprint/FaceID) for locking the app (`app_lock_screen.dart`).

---

## 🏗️ How Each Component Connects (Architecture Overview)

The application follows a **Modular Service-Provider Architecture**:

1.  **The Entry Point (`lib/main.dart`)**: Initializes Firebase, Local Storage (Hive), and starts the Riverpod `ProviderScope`.
2.  **Data Models (`lib/models/`)**: 
    -   `customer.dart`, `transaction.dart`: These represent the exact schema stored directly in our local Hive database.
3.  **The Services (`lib/services/`)**: 
    -   `db_service.dart`: The brain of our local data. It opens encrypted Hive boxes, and provides functions to Add/Delete/Update Customers and Transactions.
    -   `firestore_backup_service.dart`: Listens to user backup requests, fetches data from `db_service`, and pushes a secure JSON serialization into remote Cloud Firestore.
    -   `reminder_service.dart` / `auth_service.dart`: Specialized workers for WhatsApp links and Google Logins.
4.  **The Providers (`lib/providers/`)**: 
    -   Files like `customer_provider.dart` or `transaction_provider.dart` sit between the UI and Services. They call `db_service.dart` functions and notify the UI to rebuild when data arrives or changes.
5.  **The UI Screens (`lib/ui/`)**:
    -   Screens ONLY talk to the **Providers**. For example, when adding a transaction in `transaction/`, the UI triggers `ref.read(transactionProvider.notifier).add(...)`. It waits for the provider, which talks to the service, updates the Hive database, and tells the UI "Data is ready!"

---

## 🧹 File Directory Refactoring

During analysis, we noticed the directory structure could be optimized:
*   **Action Taken**: `lib/data/db_service.dart` was isolated. We **refactored** and moved it to `lib/services/db_service.dart` and deleted the empty `data` folder. 
*   **Reasoning**: This consolidates all raw data logic into one unified `services` directory, simplifying import paths across the app. 

---

## 🚀 What We Have To Implement Next

Based on our roadmap for KhataBook V2, here are the core features pending implementation:

1.  **PDF Statement Export**: Allow users to generate and share professional PDF logs for individual customers over a selected timeframe.
2.  **Date-Range Filtering**: Implement UI and provider logic to filter transactions between "Start Date" and "End Date".
3.  **Transaction Editing**: Add the long-press/tap-to-edit feature for transactions that have an existing `id`.
4.  **Balance Settlement (Net Off)**: A quick button to settle down active balances, automatically inserting a clearing transaction.
5.  **Improved Payment Reminders**: Deep link integration for WhatsApp/SMS reminder capabilities using dynamically generated localized string formats.
