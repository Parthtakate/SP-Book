import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/firestore_backup_service.dart';

// ---------------------------------------------------------------------------
// Status enum for rich UI feedback
// ---------------------------------------------------------------------------
enum BackupStatus {
  idle,
  working,
  success,
  failedNoInternet,
  failedTimeout,
  failedPermission,
  failedUnknown,
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final firestoreBackupServiceProvider = Provider<FirestoreBackupService>(
  (_) => FirestoreBackupService(),
);

/// Tracks the current backup/restore operation status.
class BackupStatusNotifier extends Notifier<BackupStatus> {
  @override
  BackupStatus build() => BackupStatus.idle;

  void updateStatus(BackupStatus newStatus) {
    state = newStatus;
  }
}

final backupStatusProvider =
    NotifierProvider<BackupStatusNotifier, BackupStatus>(BackupStatusNotifier.new);

/// Loading lock — true while a backup/restore operation is in progress.
/// Prevents double-tap bugs.
class IsProcessingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setProcessing(bool processing) {
    state = processing;
  }
}

final isProcessingProvider =
    NotifierProvider<IsProcessingNotifier, bool>(IsProcessingNotifier.new);

/// Holds the metadata from the most recent cloud backup (nulled when offline/never backed up).
class BackupInfoNotifier extends Notifier<Map<String, dynamic>?> {
  @override
  Map<String, dynamic>? build() => null;

  void setInfo(Map<String, dynamic>? info) {
    state = info;
  }
}

final backupInfoProvider =
    NotifierProvider<BackupInfoNotifier, Map<String, dynamic>?>(BackupInfoNotifier.new);
