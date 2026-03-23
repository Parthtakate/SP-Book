# Khata App - Comprehensive Overview

A professional, offline-first Ledger (Khata) management application built with **Flutter**. Designed to help users track balances, credit, and debit transactions ("You Got" / "You Gave"). It leverages high-performance encrypted local storage and cloud sync capabilities.

---

## 🛠️ Tech Stack & Core Dependencies

-   **Framework**: Flutter (Dart SDK `>=3.10.4`)
-   **State Management**: `flutter_riverpod` (v3.3.1) with `@riverpod_annotation`
-   **Local Database**: `hive` (v2.2.3) + `hive_flutter`
-   **Secure Storage**: `flutter_secure_storage` (v10.0.0) — used for encryption keys
-   **Authentication**: `firebase_auth` (v5.5.2) + `google_sign_in` (v6.2.2)
-   **Cloud Database**: `cloud_firestore` (v5.6.6)
-   **Biometrics**: `local_auth` (v3.0.1) — App Lock feature
-   **Utilities**: `image_picker` (Attachments), `url_launcher` (WhatsApp reminding), `intl` (Formatting)

---

## 🏗️ Architecture

The application follows a **Modular Service-Provider Architecture**:

1.  **UI Component Layer** (`lib/ui/`)
    *   `HomeScreen`: Master dashboard display.
    *   `SettingsScreen`: Google Login, Backup trigger, Biometrics toggle.
    *   Sub-modules: `/customer`, `/transaction`, `/reminder`, `/reports`.
2.  **State Management (Riverpod Providers)** (`lib/providers/`)
    *   Provides high-level reactive controllers that the UI listens to for rendering state.
    *   `AuthProvider`: Tracks user login status.
    *   `BackupProvider`: Tracks "Backup in Progress" feedback.
    *   `CustomerProvider` & `TransactionProvider`: Track lists and triggers CRUD on DB.
3.  **Service / Data Layer** (`lib/services/`, `lib/data/`)
    *   `DbService`: Handles low-level Hive box management, reading, and writing.
    *   `FirestoreBackupService`: Orchestrates reading local Hive storage, formatting it for Firestore, and batch updates.

---

## 🔒 Security & Safe-Storage

### 🔐 Database Encryption (Hive)
To protect user ledger accounting logs from tampering on rooted/jailbroken devices:
-   **Secure Keys**: A 256-bit encryption key is generated at runtime via `Hive.generateSecureKey()` on first launch if not found.
-   **Keychain Injection**: Key gets encoded in base64 URL format and safely piped into `FlutterSecureStorage`.
-   **Encrypted Boxes**: Opened with an `HiveAesCipher` using the secured key.

### 🔑 App Lock
-   Managed with `local_auth` for unlocking access.
-   Typically triggers an `AppLockScreen` overlay before allowing dashboard mounting.

---

## 📦 Data Models & Schema (Hive)

### 👤 `Customer` (Type ID: 0)
Represents a client or contact.
-   `id` (`String`): UUID (Standard lookup key).
-   `name` (`String`): Display name.
-   `phone` (`String?`): Optional contact number.
-   `createdAt` (`DateTime`): Initial creation timestamp.
-   **🚀 V3 Extension Field (Nullable)**:
    -   `updatedAt` (`DateTime?`): Tracked updates for deterministic merging during Firestore conflict resolution.

### 💰 `TransactionModel` (Type ID: 1)
Represents a credit or debit.
-   `id` (`String`): UUID.
-   `customerId` (`String`): Foreign Key pointing to the Customer block.
-   `amount` (`double`): Magnitude.
-   `isGot` (`bool`): Direct operation classifier.
    -   `true` = "You Got" (Received Money)
    -   `false` = "You Gave" (Paid Money)
-   `note` (`String`): Supporting description (Default: `''`).
-   `date` (`DateTime`): Log datum.
-   `imagePath` (`String?`): Path to visual receipt or item receipt (Attachments).
-   **🚀 V3 Extension Field (Nullable)**:
    -   `updatedAt` (`DateTime?`): Increments automatically on rewrite.

---

## 🔄 Cloud Sync & Backup Workflow

Managed by `FirestoreBackupService`:
1.  Provides Google Sign-In with transparent Auth.
2.  Data triggers batch-writes in Firestore (atomic uploads to prevent state inconsistencies).
3.  Backups are tied to unique User UID references in Cloud Firestore.
4.  Conflict updates resolve via the `.updatedAt` schema flags if present.

---

## 🧩 Critical Edge Case Designs

### 🧹 Cascading Delete
In `DbService.deleteCustomer(id)`, deleting a customer **automatically deletes all related transactions** possessing the respective `customerId` to prevent dangling references leaking space or breaking reports.

### 📐 String Format Handling
Image Paths rely on localized storage addressing. Users backing up and restoring to another operating system might encounter dangling image addresses if not resolved absolute vs scoped relative correctly.

---

## 🚀 Getting Started setup

1.  Standard Flutter environment check (`flutter doctor`).
2.  Fetch packages: `flutter pub get`.
3.  Set up Firebase configuration on Android/iOS via `flutterfire configure`.
4.  Ensure `firestore.rules` are deployed for strict user scope isolating writes strictly to `request.auth.uid`.
