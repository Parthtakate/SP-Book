import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/firestore_backup_service.dart';
import 'auth_provider.dart';
import 'customer_provider.dart';
import 'db_provider.dart';
import 'transaction_provider.dart';

enum SyncStatus { synced, syncing, offline, failed, idle }

class AutoSyncState {
  final SyncStatus status;
  final DateTime? lastSyncedAt;

  const AutoSyncState({
    this.status = SyncStatus.idle,
    this.lastSyncedAt,
  });

  AutoSyncState copyWith({
    SyncStatus? status,
    DateTime? lastSyncedAt,
  }) {
    return AutoSyncState(
      status: status ?? this.status,
      // If a new status is provided but no new date, retain the old date unless specified otherwise (but dart doesn't easily do Optionals, so we just use the existing one if null)
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}

final firestoreBackupServiceProvider = Provider<FirestoreBackupService>((ref) {
  return FirestoreBackupService();
});

final autoSyncProvider = NotifierProvider<AutoSyncNotifier, AutoSyncState>(() {
  return AutoSyncNotifier();
});

class AutoSyncNotifier extends Notifier<AutoSyncState> {
  Timer? _debounceTimer;
  StreamSubscription? _customerSub;
  StreamSubscription? _txnSub;
  StreamSubscription? _connSub;

  bool _isSyncing = false;
  bool _isStarted = false;

  @override
  AutoSyncState build() {
    // We listen to auth state changes to auto-start/stop
    ref.listen(currentUserProvider, (previous, next) {
      final db = ref.read(dbServiceProvider);
      if ((next.value != null || db.isLoggedIn) && !_isStarted) {
        start();
      } else if (next.value == null && !db.isLoggedIn && _isStarted) {
        stop();
      }
    });

    // Handle startup edge cases: if already logged in according to db, force start 
    // even before the auth provider pushes its first data event.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(dbServiceProvider).isLoggedIn && !_isStarted) {
        start();
      }
    });

    return const AutoSyncState();
  }

  /// Called when the app starts or user authenticates
  Future<void> start() async {
    if (_isStarted) return;
    _isStarted = true;

    // Load initial synced at if we have it locally or remotely
    _syncStartupCheck(); // Fire & forget

    // Watch internet connection to trigger retries if offline
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.contains(ConnectivityResult.none)) {
        if (state.status != SyncStatus.offline) {
          state = state.copyWith(status: SyncStatus.offline);
        }
      } else {
        if (state.status == SyncStatus.offline || state.status == SyncStatus.failed) {
          // Trigger a debounce sync just in case there are pending changes
          _onDataChanged();
        }
      }
    });

    final db = ref.read(dbServiceProvider);
    // Watch Hive changes
    _customerSub = db.customersBox.watch().listen((_) => _onDataChanged());
    _txnSub = db.transactionsBox.watch().listen((_) => _onDataChanged());
  }

  void stop() {
    _debounceTimer?.cancel();
    _customerSub?.cancel();
    _txnSub?.cancel();
    _connSub?.cancel();
    _isStarted = false;
    _isSyncing = false;
    state = const AutoSyncState(); // Reset
  }

  Future<void> _syncStartupCheck() async {
    if (_isSyncing) return;
    _isSyncing = true;
    state = state.copyWith(status: SyncStatus.syncing);

    // -----------------------------------------------------------------------
    // CRITICAL: Wait for Firebase Auth tokens to fully settle before reading
    // Firestore. The auth state stream fires as soon as user != null, but the
    // ID token cache can still be propagating — resulting in permission-denied
    // or unauthenticated errors immediately after sign-in.
    // -----------------------------------------------------------------------
    await Future.delayed(const Duration(milliseconds: 800));

    final db = ref.read(dbServiceProvider);
    final backupService = ref.read(firestoreBackupServiceProvider);

    try {
      final backupInfo = await backupService.getBackupInfo();
      int lastCloudTime = 0;
      
      if (backupInfo != null) {
        final lastBackupAt = backupInfo['lastBackupAt'];
        if (lastBackupAt is Timestamp) {
          lastCloudTime = lastBackupAt.millisecondsSinceEpoch;
          state = state.copyWith(lastSyncedAt: lastBackupAt.toDate());
        }
      }

      final int lastLocalTime = db.lastLocalModifiedAt;
      final bool isLocalEmpty =
          db.customersBox.isEmpty && db.transactionsBox.isEmpty;

      // 1. Local Empty Flow (new install or just signed in fresh)
      if (isLocalEmpty) {
        if (lastCloudTime > 0) {
          // Cloud has data → Restore
          if (kDebugMode) debugPrint('[AutoSync] Local empty, restoring from cloud...');
          await backupService.restoreAll(db);
          // CRITICAL: Invalidate all UI providers so screens show restored data
          _invalidateDataProviders();
          state = state.copyWith(
            status: SyncStatus.synced,
            lastSyncedAt: DateTime.now(),
          );
        } else {
          // Local and cloud both empty — nothing to do
          state = state.copyWith(status: SyncStatus.synced);
        }
      }
      // 2. Conflict Flow (Both might have data)
      else {
        // Give 10 seconds leeway for timezone/clock drift before deciding cloud is definitively newer
        if (lastCloudTime > lastLocalTime + 10000) {
          if (kDebugMode) debugPrint('[AutoSync] Cloud newer by ${(lastCloudTime - lastLocalTime) / 1000}s — restoring...');
          await backupService.restoreAll(db);
          // CRITICAL: Invalidate all UI providers so screens show restored data
          _invalidateDataProviders();
          state = state.copyWith(
            status: SyncStatus.synced,
            lastSyncedAt: DateTime.now(),
          );
        } else if (lastLocalTime > lastCloudTime + 10000) {
          if (kDebugMode) debugPrint('[AutoSync] Local newer by ${(lastLocalTime - lastCloudTime) / 1000}s — backing up...');
          await backupService.backupIncremental(db);
          state = state.copyWith(
            status: SyncStatus.synced,
            lastSyncedAt: DateTime.now(),
          );
        } else {
          if (kDebugMode) debugPrint("[AutoSync] In sync, nothing to do.");
          state = state.copyWith(status: SyncStatus.synced);
        }
      }
    } on NotSignedInException {
      // Auth token not yet ready — don't mark as failed, just reset to idle.
      // The Hive watcher will retrigger via _triggerBackup when data changes.
      if (kDebugMode) debugPrint('[AutoSync] Startup check: not signed in yet, skipping.');
      state = state.copyWith(status: SyncStatus.idle);
    } on NoInternetException {
      state = state.copyWith(status: SyncStatus.offline);
    } catch (e) {
      if (kDebugMode) debugPrint('[AutoSync] Error during startup sync: $e');
      state = state.copyWith(status: SyncStatus.failed);
    } finally {
      _isSyncing = false;
    }
  }

  /// Invalidates all data-driven Riverpod providers so UI rebuilds after restore.
  void _invalidateDataProviders() {
    ref.invalidate(customersProvider);
    ref.invalidate(dashboardBalancesProvider);
    if (kDebugMode) debugPrint('[AutoSync] Invalidated UI providers after restore.');
  }

  void _onDataChanged() {
    final db = ref.read(dbServiceProvider);
    if (db.isRestoring) return; // Ignore events triggered by restore

    // Note: We only update local modification time when real user events fire.
    // If the box changed, we note it.
    db.setLastLocalModifiedAt(DateTime.now().millisecondsSinceEpoch);

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 5), () => _triggerBackup());
  }

  Future<void> _triggerBackup() async {
    if (_isSyncing) return;
    _isSyncing = true;
    state = state.copyWith(status: SyncStatus.syncing);

    final db = ref.read(dbServiceProvider);
    final backupService = ref.read(firestoreBackupServiceProvider);

    try {
      if (kDebugMode) debugPrint("[AutoSync] Triggering background backup...");
      await backupService.backupIncremental(db);
      state = state.copyWith(
        status: SyncStatus.synced,
        lastSyncedAt: DateTime.now(),
      );
    } on NoInternetException {
      state = state.copyWith(status: SyncStatus.offline);
    } catch (e) {
      if (kDebugMode) debugPrint("[AutoSync] Error during background backup: $e");
      state = state.copyWith(status: SyncStatus.failed);
    } finally {
      _isSyncing = false;
    }
  }
}
