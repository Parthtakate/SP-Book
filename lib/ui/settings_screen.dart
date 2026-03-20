import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/auth_provider.dart';
import '../providers/backup_provider.dart';
import '../providers/db_provider.dart';
import '../services/firestore_backup_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  // ---------------------------------------------------------------------------
  // Backup
  // ---------------------------------------------------------------------------
  Future<void> _doBackup(BuildContext context, WidgetRef ref) async {
    if (ref.read(isProcessingProvider)) return;
    ref.read(isProcessingProvider.notifier).setProcessing(true);
    ref.read(backupStatusProvider.notifier).updateStatus(BackupStatus.working);

    try {
      final db = ref.read(dbServiceProvider);
      await ref.read(firestoreBackupServiceProvider).backupAll(db);

      // Refresh metadata
      final info =
          await ref.read(firestoreBackupServiceProvider).getBackupInfo();
      ref.read(backupInfoProvider.notifier).setInfo(info);

      ref.read(backupStatusProvider.notifier).updateStatus(BackupStatus.success);
    } on NoInternetException {
      ref.read(backupStatusProvider.notifier).updateStatus(BackupStatus.failedNoInternet);
    } on FirestoreTimeoutException {
      ref.read(backupStatusProvider.notifier).updateStatus(BackupStatus.failedNoInternet);
    } on NotSignedInException {
      ref.read(backupStatusProvider.notifier).updateStatus(BackupStatus.failedPermission);
    } on FirestorePermissionException {
      ref.read(backupStatusProvider.notifier).updateStatus(BackupStatus.failedPermission);
    } catch (e, stack) {
      debugPrint('Backup Error: $e\n$stack');
      ref.read(backupStatusProvider.notifier).updateStatus(BackupStatus.failedUnknown);
    } finally {
      ref.read(isProcessingProvider.notifier).setProcessing(false);
    }
  }

  // ---------------------------------------------------------------------------
  // Restore
  // ---------------------------------------------------------------------------
  Future<void> _doRestore(BuildContext context, WidgetRef ref) async {
    if (ref.read(isProcessingProvider)) return;

    // Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from Cloud?'),
        content: const Text(
          'This will CLEAR all local data and replace it with your cloud backup. '
          'This cannot be undone.\n\nAre you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('RESTORE'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    ref.read(isProcessingProvider.notifier).setProcessing(true);
    ref.read(backupStatusProvider.notifier).updateStatus(BackupStatus.working);

    try {
      final db = ref.read(dbServiceProvider);
      await ref.read(firestoreBackupServiceProvider).restoreAll(db);
      ref.read(backupStatusProvider.notifier).updateStatus(BackupStatus.success);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Restore complete! Your data has been updated.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on NoInternetException {
      ref.read(backupStatusProvider.notifier).updateStatus(BackupStatus.failedNoInternet);
    } on FirestoreTimeoutException {
      ref.read(backupStatusProvider.notifier).updateStatus(BackupStatus.failedNoInternet);
    } on FirestorePermissionException {
      ref.read(backupStatusProvider.notifier).updateStatus(BackupStatus.failedPermission);
    } catch (e, stack) {
      debugPrint('Restore Error: $e\n$stack');
      ref.read(backupStatusProvider.notifier).updateStatus(BackupStatus.failedUnknown);
    } finally {
      ref.read(isProcessingProvider.notifier).setProcessing(false);
    }
  }

  // ---------------------------------------------------------------------------
  // Sign In / Out
  // ---------------------------------------------------------------------------
  Future<void> _signIn(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
      // Load existing backup info after sign in
      _loadBackupInfo(ref);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign-in failed. Please try again.')),
        );
      }
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    await ref.read(authServiceProvider).signOut();
    ref.read(backupStatusProvider.notifier).updateStatus(BackupStatus.idle);
    ref.read(backupInfoProvider.notifier).setInfo(null);
  }

  Future<void> _loadBackupInfo(WidgetRef ref) async {
    try {
      final info =
          await ref.read(firestoreBackupServiceProvider).getBackupInfo();
      ref.read(backupInfoProvider.notifier).setInfo(info);
    } catch (_) {
      // No internet or not signed in — silently ignore on load
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final status = ref.watch(backupStatusProvider);
    final isProcessing = ref.watch(isProcessingProvider);
    final backupInfo = ref.watch(backupInfoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Backup'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        children: [
          // ---- Account section
          _sectionHeader(context, '☁️ Google Account'),
          userAsync.when(
            loading: () =>
                const ListTile(title: Text('Loading...')),
            error: (err, stack) =>
                const ListTile(title: Text('Error loading account.')),
            data: (User? user) {
              if (user == null) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.login),
                    label: const Text('Sign in with Google'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      side: BorderSide(color: Colors.grey.shade300),
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: () => _signIn(context, ref),
                  ),
                );
              }
              return ListTile(
                leading: user.photoURL != null
                    ? CircleAvatar(
                        backgroundImage: NetworkImage(user.photoURL!))
                    : CircleAvatar(
                        child: Text(
                            user.displayName?.substring(0, 1).toUpperCase() ??
                                '?')),
                title: Text(user.displayName ?? 'Unknown',
                    style:
                        const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(user.email ?? ''),
                trailing: TextButton(
                  onPressed: () => _signOut(context, ref),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Sign Out'),
                ),
              );
            },
          ),

          const Divider(),

          // ---- Backup / Restore (only shown when signed in)
          userAsync.maybeWhen(
            data: (user) => user != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionHeader(context, '📦 Cloud Backup'),

                      // -- Last backup info
                      if (backupInfo != null)
                        _buildBackupInfoTile(context, backupInfo)
                      else
                        const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 16.0, vertical: 4.0),
                          child: Text(
                            'No backup found for this account.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),

                      const SizedBox(height: 12),

                      // -- Status widget
                      _buildStatusWidget(context, status),

                      const SizedBox(height: 12),

                      // -- Action buttons
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: isProcessing
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white))
                                    : const Icon(Icons.cloud_upload),
                                label: Text(isProcessing
                                    ? 'Working...'
                                    : 'Backup to Cloud'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      Theme.of(context).colorScheme.primary,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(50),
                                ),
                                onPressed: isProcessing
                                    ? null
                                    : () => _doBackup(context, ref),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.cloud_download),
                                label: const Text('Restore from Cloud'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  minimumSize: const Size.fromHeight(50),
                                ),
                                onPressed: isProcessing
                                    ? null
                                    : () => _doRestore(context, ref),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      // -- Firestore rules reminder
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 8.0),
                        child: Row(
                          children: [
                            const Icon(Icons.lock,
                                size: 14, color: Colors.green),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Your data is secured with your Google account.',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helper Widgets
  // ---------------------------------------------------------------------------

  Widget _sectionHeader(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildBackupInfoTile(
      BuildContext context, Map<String, dynamic> info) {
    final ts = info['lastBackupAt'];
    String timeStr = 'Unknown';
    if (ts != null) {
      final dt = (ts as dynamic).toDate() as DateTime;
      timeStr = DateFormat('dd MMM yyyy, hh:mm a').format(dt);
    }
    final customers = info['totalCustomers'] ?? 0;
    final transactions = info['totalTransactions'] ?? 0;
    final device = info['device'] ?? 'Unknown';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Card(
        elevation: 0,
        color: Colors.grey.shade100,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Last backup: $timeStr',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '$customers customers · $transactions transactions · $device',
                style:
                    TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusWidget(BuildContext context, BackupStatus status) {
    if (status == BackupStatus.idle) return const SizedBox.shrink();

    late IconData icon;
    late Color color;
    late String message;

    switch (status) {
      case BackupStatus.working:
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 10),
              Text('Backing up to cloud...'),
            ],
          ),
        );
      case BackupStatus.success:
        icon = Icons.check_circle;
        color = Colors.green;
        message = 'Backup successful!';
      case BackupStatus.failedNoInternet:
        icon = Icons.wifi_off;
        color = Colors.orange;
        message = 'No internet connection. Check and retry.';
      case BackupStatus.failedPermission:
        icon = Icons.lock_person;
        color = Colors.red;
        message = 'Login expired. Please sign in again.';
      case BackupStatus.failedUnknown:
        icon = Icons.error_outline;
        color = Colors.red;
        message = 'Something went wrong. Tap to retry.';
      case BackupStatus.idle:
        return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
