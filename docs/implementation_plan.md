# Implementation Plan - Update Firebase Configuration

The goal is to ensure the app is fully connected to the new Firebase project (`spbooks-ac97e`) using the updated [google-services.json](file:///c:/Users/hp/.gemini/antigravity/scratch/khata_app/android/app/google-services.json) file.

## Current State

*   **Android**: [android/app/google-services.json](file:///c:/Users/hp/.gemini/antigravity/scratch/khata_app/android/app/google-services.json) is already updated and present in the project.
*   **iOS**: No `GoogleService-Info.plist` found. It appears setting up for iOS is not currently required or configured.
*   **`firebase_options.dart`**: Does not exist. The app uses the traditional platform-specific file approach (`await Firebase.initializeApp();` in [main.dart](file:///c:/Users/hp/.gemini/antigravity/scratch/khata_app/lib/main.dart)).

## Proposed Steps

### 1. Verification of Configuration
*   Confirm [android/app/google-services.json](file:///c:/Users/hp/.gemini/antigravity/scratch/khata_app/android/app/google-services.json) is picked up correctly by checking the build setup. The `com.google.gms.google-services` plugin is already applied in [android/app/build.gradle.kts](file:///c:/Users/hp/.gemini/antigravity/scratch/khata_app/android/app/build.gradle.kts).

### 2. Cleanup & Cache Removal
*   Run cleanup to remove any cached configurations or build artifacts from the old Firebase project.
    *   `flutter clean`
    *   `flutter pub get`

### 3. Verification Build
*   Run a debug build to ensure compiling succeeds with the new configuration files.
    *   `flutter build apk --debug`

## Verification Plan

### Automated/Compilation Verification
1.  Run `flutter build apk --debug` to verify that the Android app builds successfully with the new [google-services.json](file:///c:/Users/hp/.gemini/antigravity/scratch/khata_app/android/app/google-services.json) configuration.

### Manual Verification (User Action Required)
Since full connectivity cannot be tested without running on a device connected to the network and interacting with Firebase services:
1.  **Run the app** on an Android device/emulator.
2.  **Verify Authentication**: Attempt to log in or sign up.
3.  **Verify Firestore**: Perform an action that reads/writes data (e.g., creating a transaction/entry) and check if it reflects in the app (or back up/sync).
4.  **Verify Storage**: If applicable, test any item/media upload.
5.  All these should connect to the new Firebase project console (`spbooks-ac97e`).
