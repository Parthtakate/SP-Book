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
import 'khatabook_provider.dart';
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
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}

final firestoreBackupServiceProvider = Provider<FirestoreBackupService>((ref) {
  return FirestoreBackupService();
});

// ── isRestoringProvider: single source of truth ──
// DbService reads this via an injected callback (no Riverpod import needed there).
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

  // ── Single unified sync lock (fixes overlapping mutex flags) ──
  bool _syncLock = false;

  bool _hasStarted = false;

  // ── Fix 5: Track whether the startup sync has completed ──
  // If connectivity returns while startup sync hasn't finished yet,
  // we re-run _syncStartupCheck instead of _onDataChanged.
  bool _startupSyncCompleted = false;

  String get _ts => DateTime.now().toIso8601String();

  @override
  AutoSyncState build() {
    // Wire up isRestoring into DbService so it doesn't need to import Riverpod
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _injectRestoringCallback();
    });

    // Listen to auth state changes to auto-start/stop
    ref.listen(currentUserProvider, (previous, next) {
      debugPrint('[AUTH][$_ts] currentUserProvider changed: '
          'previous=${previous?.value?.uid}, next=${next.value?.uid}');
      final db = ref.read(dbServiceProvider);
      if ((next.value != null || db.isLoggedIn) && !_hasStarted) {
        debugPrint('[AUTH][$_ts] Auth user available — calling start()');
        start();
      } else if (next.value == null && !db.isLoggedIn && _hasStarted) {
        debugPrint('[AUTH][$_ts] Auth user null — calling stop()');
        stop();
      }
    });

    // Handle startup edge cases: db says logged in but auth event hasn't fired yet
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      final dbLoggedIn = ref.read(dbServiceProvider).isLoggedIn;
      debugPrint('[SYNC][$_ts] postFrameCallback: '
          'FirebaseAuth.currentUser=${firebaseUser?.uid}, '
          'db.isLoggedIn=$dbLoggedIn, _hasStarted=$_hasStarted');
      if (dbLoggedIn && !_hasStarted) {
        debugPrint('[SYNC][$_ts] postFrameCallback triggering start()');
        start();
      }
    });

    return const AutoSyncState();
  }

  /// Inject a Riverpod-aware isRestoring getter into DbService.
  void _injectRestoringCallback() {
    final db = ref.read(dbServiceProvider);
    db.injectRestoringCallback(() => ref.read(isRestoringProvider));
  }

  /// Called when the app starts or user authenticates.
  void start() {
    if (_hasStarted) return;
    _hasStarted = true;
    _startupSyncCompleted = false;

    final firebaseUser = FirebaseAuth.instance.currentUser;
    debugPrint('[SYNC][$_ts] ========== start() called ==========');
    debugPrint('[SYNC][$_ts] FirebaseAuth.currentUser: uid=${firebaseUser?.uid}');

    _syncStartupCheck(); // Fire & forget

    // ── Fix 5: Connectivity listener — distinguish startup vs ongoing sync ──
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.contains(ConnectivityResult.none)) {
        if (state.status != SyncStatus.offline) {
          debugPrint('[SYNC][$_ts] Connectivity: went OFFLINE');
          state = state.copyWith(status: SyncStatus.offline);
        }
      } else {
        if (state.status == SyncStatus.offline || state.status == SyncStatus.failed) {
          debugPrint('[SYNC][$_ts] Connectivity: back ONLINE');
          if (!_startupSyncCompleted) {
            // Startup sync was interrupted by being offline — retry it
            debugPrint('[SYNC][$_ts] Startup not complete — re-running _syncStartupCheck()');
            _syncStartupCheck();
          } else {
            // Normal reconnect — just push any pending local changes
            debugPrint('[SYNC][$_ts] Startup complete — running _onDataChanged()');
            _onDataChanged();
          }
        }
      }
    });

    final db = ref.read(dbServiceProvider);
    _customerSub = db.customersBox.watch().listen((_) => _onDataChanged());
    _txnSub = db.transactionsBox.watch().listen((_) => _onDataChanged());
    // Also watch khatabooks box so backup triggers when a new book is created
    db.khatabooksBox.watch().listen((_) => _onDataChanged());
  }

  void stop() {
    _debounceTimer?.cancel();
    _customerSub?.cancel();
    _txnSub?.cancel();
    _connSub?.cancel();
    _hasStarted = false;
    _syncLock = false;
    _startupSyncCompleted = false;
    state = const AutoSyncState();
  }

  /// Forces a fresh startup cycle (e.g., after sign-in from settings screen).
  void restart() {
    stop();
    start();
  }

  Future<void> _runBackgroundSync() async {
    if (_syncLock) {
      debugPrint('[SYNC][$_ts] _runBackgroundSync() SKIPPED — lock held');
      return;
    }
    _syncLock = true;
    debugPrint('[SYNC][$_ts] >>>>>> _runBackgroundSync() STARTED');

    ref.read(isRestoringProvider.notifier).setState(true);

    try {
      debugPrint('[SYNC][$_ts] Waiting 800ms for auth tokens to settle...');
      await Future.delayed(const Duration(milliseconds: 800));

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
      state = state.copyWith(status: SyncStatus.failed);
    } finally {
      ref.read(isRestoringProvider.notifier).setState(false);
      _syncLock = false;
    }
  }

  Future<void> _syncStartupCheck() async {
    if (_syncLock) {
      debugPrint('[SYNC][$_ts] _syncStartupCheck() SKIPPED — lock held');
      return;
    }
    _syncLock = true;
    state = state.copyWith(status: SyncStatus.syncing);

    final db = ref.read(dbServiceProvider);
    final backupService = ref.read(firestoreBackupServiceProvider);

    debugPrint('[SYNC][$_ts] ====== _syncStartupCheck() STARTED ======');

    try {
      // ── Fix 6: If encryption key was lost, force a cloud restore immediately ──
      if (db.encryptionKeyLost) {
        debugPrint('[SYNC][$_ts] Encryption key lost — forcing full cloud restore');
        _syncLock = false; // release before calling _runBackgroundSync
        await _runBackgroundSync();
        _startupSyncCompleted = true;
        return;
      }

      final bool isLocalEmpty =
          db.customersBox.isEmpty && db.transactionsBox.isEmpty;

      debugPrint('[SYNC][$_ts] isLocalEmpty=$isLocalEmpty, '
          'customers=${db.customersBox.length}, transactions=${db.transactionsBox.length}');

      // 1. Local Empty Flow — new install or cleared device
      if (isLocalEmpty) {
        debugPrint('[SYNC][$_ts] Local empty — dispatching _runBackgroundSync()');
        _syncLock = false;
        unawaited(_runBackgroundSync());
      }
      // 2. Conflict resolution — use Firestore server timestamps, NOT device clock
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

        // ── Fix 1: Use server-acknowledged timestamp instead of device clock ──
        // lastAcknowledgedServerTime is a Firestore-issued timestamp stored locally
        // after the last successful backup — immune to device clock manipulation.
        final int lastAcknowledgedTime = db.lastAcknowledgedServerTime;

        // Fall back to lastLocalModifiedAt if we've never stored a server time
        final int comparisonTime = lastAcknowledgedTime > 0
            ? lastAcknowledgedTime
            : db.lastLocalModifiedAt;

        debugPrint('[SYNC][$_ts] Conflict comparison: '
            'lastCloudTime=$lastCloudTime, '
            'lastAcknowledgedTime=$lastAcknowledgedTime, '
            'comparisonTime=$comparisonTime, '
            'diff=${lastCloudTime - comparisonTime}ms');

        // 10-second leeway absorbs minor network latency
        if (lastCloudTime > comparisonTime + 10000) {
          debugPrint('[SYNC][$_ts] Cloud newer by '
              '${(lastCloudTime - comparisonTime) / 1000}s — restoring (merge)...');
          _syncLock = false;
          unawaited(_runBackgroundSync());
          state = state.copyWith(status: SyncStatus.synced, lastSyncedAt: DateTime.now());
        } else if (comparisonTime > lastCloudTime + 10000) {
          debugPrint('[SYNC][$_ts] Local newer by '
              '${(comparisonTime - lastCloudTime) / 1000}s — backing up...');
          _syncLock = false;
          await backupService.backupIncremental(db);
          state = state.copyWith(status: SyncStatus.synced, lastSyncedAt: DateTime.now());
        } else {
          debugPrint('[SYNC][$_ts] In sync (within 10s leeway), nothing to do.');
          state = state.copyWith(status: SyncStatus.synced);
        }
      }

      _startupSyncCompleted = true;

    } on NotSignedInException {
      debugPrint('[ERROR][$_ts] _syncStartupCheck: NotSignedInException — auth not ready yet');
      state = state.copyWith(status: SyncStatus.idle);
    } on NoInternetException {
      debugPrint('[SYNC][$_ts] _syncStartupCheck: NoInternetException — going offline');
      state = state.copyWith(status: SyncStatus.offline);
      // NOTE: _startupSyncCompleted stays false — will retry on reconnect
    } catch (e, stackTrace) {
      debugPrint('[ERROR][$_ts] _syncStartupCheck FAILED with error: $e');
      debugPrint('[ERROR][$_ts] Stack trace:\n$stackTrace');
      state = state.copyWith(status: SyncStatus.failed);
    } finally {
      if (_syncLock) _syncLock = false;
      debugPrint('[SYNC][$_ts] ====== _syncStartupCheck() ENDED ======');
    }
  }

  /// Invalidates all data-driven providers so the UI rebuilds after a restore.
  void _invalidateDataProviders() {
    ref.invalidate(customersProvider);
    ref.invalidate(customerBalanceMapProvider);
    ref.invalidate(dashboardBalancesProvider);
    ref.invalidate(khatabooksProvider);        // ← NEW: refresh book list
    ref.invalidate(activeKhatabookIdProvider); // ← NEW: re-read persisted book
    if (kDebugMode) debugPrint('[AutoSync] Invalidated UI providers after restore.');
  }

  void _onDataChanged() {
    if (ref.read(isRestoringProvider)) return; // Ignore events triggered by restore

    final db = ref.read(dbServiceProvider);
    db.setLastLocalModifiedAt(DateTime.now().millisecondsSinceEpoch);

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 5), () => _triggerBackup());
  }

  Future<void> _triggerBackup() async {
    if (_syncLock) return;
    _syncLock = true;
    state = state.copyWith(status: SyncStatus.syncing);

    final db = ref.read(dbServiceProvider);
    final backupService = ref.read(firestoreBackupServiceProvider);

    try {
      debugPrint('[SYNC][$_ts] _triggerBackup() started — '
          'FirebaseAuth.currentUser=${FirebaseAuth.instance.currentUser?.uid}');
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
      _syncLock = false;
    }
  }
}
