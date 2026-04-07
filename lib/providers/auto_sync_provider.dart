import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

class IsRestoringNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void setState(bool value) => state = value;
}

final isRestoringProvider = NotifierProvider<IsRestoringNotifier, bool>(() {
  return IsRestoringNotifier();
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
  bool _hasStarted = false;
  bool _isSyncRunning = false;

  String get _ts => DateTime.now().toIso8601String();

  @override
  AutoSyncState build() {
    // We listen to auth state changes to auto-start/stop
    ref.listen(currentUserProvider, (previous, next) {
      debugPrint('[AUTH][$_ts] currentUserProvider changed: previous=${previous?.value?.uid}, next=${next.value?.uid}');
      final db = ref.read(dbServiceProvider);
      if ((next.value != null || db.isLoggedIn) && !_hasStarted) {
        debugPrint('[AUTH][$_ts] Auth user available or db.isLoggedIn — calling start()');
        start();
      } else if (next.value == null && !db.isLoggedIn && _hasStarted) {
        debugPrint('[AUTH][$_ts] Auth user is null and db not logged in — calling stop()');
        stop();
      }
    });

    // Handle startup edge cases: if already logged in according to db, force start 
    // even before the auth provider pushes its first data event.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      final dbLoggedIn = ref.read(dbServiceProvider).isLoggedIn;
      debugPrint('[SYNC][$_ts] postFrameCallback: FirebaseAuth.currentUser=${firebaseUser?.uid}, db.isLoggedIn=$dbLoggedIn, _hasStarted=$_hasStarted');
      if (dbLoggedIn && !_hasStarted) {
        debugPrint('[SYNC][$_ts] postFrameCallback triggering start() (db says logged in, auth may still be null)');
        start();
      }
    });

    return const AutoSyncState();
  }

  /// Called when the app starts or user authenticates
  void start() {
    if (_hasStarted) return;
    _hasStarted = true;

    final firebaseUser = FirebaseAuth.instance.currentUser;
    debugPrint('[SYNC][$_ts] ========== start() called ==========');
    debugPrint('[SYNC][$_ts] FirebaseAuth.currentUser at start(): uid=${firebaseUser?.uid}, email=${firebaseUser?.email}');
    debugPrint('[SYNC][$_ts] Token state: isAnonymous=${firebaseUser?.isAnonymous}, emailVerified=${firebaseUser?.emailVerified}');

    // Load initial synced at if we have it locally or remotely
    _syncStartupCheck(); // Fire & forget

    // Watch internet connection to trigger retries if offline
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.contains(ConnectivityResult.none)) {
        if (state.status != SyncStatus.offline) {
          debugPrint('[SYNC][$_ts] Connectivity: went OFFLINE');
          state = state.copyWith(status: SyncStatus.offline);
        }
      } else {
        if (state.status == SyncStatus.offline || state.status == SyncStatus.failed) {
          debugPrint('[SYNC][$_ts] Connectivity: back ONLINE — triggering data change check');
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
    _hasStarted = false;
    _isSyncing = false;
    _isSyncRunning = false;
    state = const AutoSyncState(); // Reset
  }

  Future<void> _runBackgroundSync() async {
    if (_isSyncRunning) {
      debugPrint('[SYNC][$_ts] _runBackgroundSync() SKIPPED — already running');
      return;
    }
    _isSyncRunning = true;
    debugPrint('[SYNC][$_ts] >>>>>> _runBackgroundSync() STARTED');

    try {
      ref.read(isRestoringProvider.notifier).setState(true);

      // Allows Firebase auth tokens to settle harmlessly in the bg
      debugPrint('[SYNC][$_ts] Waiting 800ms for auth tokens to settle...');
      await Future.delayed(const Duration(milliseconds: 800));

      final userAfterDelay = FirebaseAuth.instance.currentUser;
      debugPrint('[AUTH][$_ts] FirebaseAuth.currentUser AFTER 800ms delay: uid=${userAfterDelay?.uid}');

      final backupService = ref.read(firestoreBackupServiceProvider);
      final db = ref.read(dbServiceProvider);

      debugPrint('[SYNC][$_ts] Calling getBackupInfo()...');
      final backupInfo = await backupService.getBackupInfo();
      debugPrint('[SYNC][$_ts] getBackupInfo() returned: $backupInfo');

      debugPrint('[SYNC][$_ts] Calling restoreAll()...');
      await backupService.restoreAll(db);
      debugPrint('[SYNC][$_ts] restoreAll() completed successfully');

      _invalidateDataProviders();

      if (backupInfo != null && backupInfo['lastBackupAt'] is Timestamp) {
        state = state.copyWith(
          status: SyncStatus.synced,
          lastSyncedAt: (backupInfo['lastBackupAt'] as Timestamp).toDate(),
        );
      } else {
        state = state.copyWith(status: SyncStatus.synced);
      }
      debugPrint('[SYNC][$_ts] >>>>>> _runBackgroundSync() FINISHED — status=synced');

    } catch (e, stackTrace) {
      debugPrint('[ERROR][$_ts] >>>>>> _runBackgroundSync() FAILED');
      debugPrint('[ERROR][$_ts] Error: $e');
      debugPrint('[ERROR][$_ts] Stack trace:\n$stackTrace');
      debugPrint('[ERROR][$_ts] FirebaseAuth.currentUser at failure: uid=${FirebaseAuth.instance.currentUser?.uid}');
      state = state.copyWith(status: SyncStatus.failed);
    } finally {
      ref.read(isRestoringProvider.notifier).setState(false);
      _isSyncRunning = false;
    }
  }

  Future<void> _syncStartupCheck() async {
    if (_isSyncing) {
      debugPrint('[SYNC][$_ts] _syncStartupCheck() SKIPPED — already syncing');
      return;
    }
    _isSyncing = true;
    state = state.copyWith(status: SyncStatus.syncing);

    final firebaseUser = FirebaseAuth.instance.currentUser;
    debugPrint('[SYNC][$_ts] ====== _syncStartupCheck() STARTED ======');
    debugPrint('[AUTH][$_ts] FirebaseAuth.currentUser at _syncStartupCheck: uid=${firebaseUser?.uid}');

    final db = ref.read(dbServiceProvider);
    final backupService = ref.read(firestoreBackupServiceProvider);

    try {
      final int lastLocalTime = db.lastLocalModifiedAt;
      final bool isLocalEmpty =
          db.customersBox.isEmpty && db.transactionsBox.isEmpty;

      debugPrint('[SYNC][$_ts] isLocalEmpty=$isLocalEmpty, lastLocalTime=$lastLocalTime, customers=${db.customersBox.length}, transactions=${db.transactionsBox.length}');

      // 1. Local Empty Flow (new install or just signed in fresh)
      if (isLocalEmpty) {
        debugPrint('[SYNC][$_ts] Local empty — dispatching _runBackgroundSync()');
        unawaited(_runBackgroundSync());
      }
      // 2. Conflict Flow (Both might have data)
      else {
        debugPrint('[SYNC][$_ts] Local has data — calling getBackupInfo() for conflict check...');
        final backupInfo = await backupService.getBackupInfo();
        debugPrint('[SYNC][$_ts] getBackupInfo() returned: $backupInfo');
        int lastCloudTime = 0;
        
        if (backupInfo != null) {
          final lastBackupAt = backupInfo['lastBackupAt'];
          if (lastBackupAt is Timestamp) {
            lastCloudTime = lastBackupAt.millisecondsSinceEpoch;
            state = state.copyWith(lastSyncedAt: lastBackupAt.toDate());
          }
        }

        debugPrint('[SYNC][$_ts] Conflict comparison: lastCloudTime=$lastCloudTime, lastLocalTime=$lastLocalTime, diff=${lastCloudTime - lastLocalTime}ms');

        // Give 10 seconds leeway for timezone/clock drift before deciding cloud is definitively newer
        if (lastCloudTime > lastLocalTime + 10000) {
          debugPrint('[SYNC][$_ts] Cloud newer by ${(lastCloudTime - lastLocalTime) / 1000}s — restoring...');
          unawaited(_runBackgroundSync());
          state = state.copyWith(
            status: SyncStatus.synced,
            lastSyncedAt: DateTime.now(),
          );
        } else if (lastLocalTime > lastCloudTime + 10000) {
          debugPrint('[SYNC][$_ts] Local newer by ${(lastLocalTime - lastCloudTime) / 1000}s — backing up...');
          await backupService.backupIncremental(db);
          state = state.copyWith(
            status: SyncStatus.synced,
            lastSyncedAt: DateTime.now(),
          );
        } else {
          debugPrint('[SYNC][$_ts] In sync (within 10s leeway), nothing to do.');
          state = state.copyWith(status: SyncStatus.synced);
        }
      }
    } on NotSignedInException {
      // Auth token not yet ready — don't mark as failed, just reset to idle.
      debugPrint('[ERROR][$_ts] _syncStartupCheck: NotSignedInException — auth token NOT ready yet');
      debugPrint('[AUTH][$_ts] FirebaseAuth.currentUser at NotSignedIn: uid=${FirebaseAuth.instance.currentUser?.uid}');
      state = state.copyWith(status: SyncStatus.idle);
    } on NoInternetException {
      debugPrint('[SYNC][$_ts] _syncStartupCheck: NoInternetException — going offline');
      state = state.copyWith(status: SyncStatus.offline);
    } catch (e, stackTrace) {
      debugPrint('[ERROR][$_ts] _syncStartupCheck FAILED with error: $e');
      debugPrint('[ERROR][$_ts] Stack trace:\n$stackTrace');
      debugPrint('[AUTH][$_ts] FirebaseAuth.currentUser at failure: uid=${FirebaseAuth.instance.currentUser?.uid}');
      state = state.copyWith(status: SyncStatus.failed);
    } finally {
      _isSyncing = false;
      debugPrint('[SYNC][$_ts] ====== _syncStartupCheck() ENDED ======');
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
      debugPrint('[SYNC][$_ts] _triggerBackup() started — FirebaseAuth.currentUser=${FirebaseAuth.instance.currentUser?.uid}');
      await backupService.backupIncremental(db);
      debugPrint('[SYNC][$_ts] _triggerBackup() completed successfully');
      state = state.copyWith(
        status: SyncStatus.synced,
        lastSyncedAt: DateTime.now(),
      );
    } on NoInternetException {
      debugPrint('[SYNC][$_ts] _triggerBackup(): NoInternetException');
      state = state.copyWith(status: SyncStatus.offline);
    } catch (e, stackTrace) {
      debugPrint('[ERROR][$_ts] _triggerBackup() FAILED: $e');
      debugPrint('[ERROR][$_ts] Stack trace:\n$stackTrace');
      state = state.copyWith(status: SyncStatus.failed);
    } finally {
      _isSyncing = false;
    }
  }
}
