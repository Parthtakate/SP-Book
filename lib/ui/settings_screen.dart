import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/auth_provider.dart';
import '../providers/backup_provider.dart';
import '../providers/customer_provider.dart';
import '../providers/db_provider.dart';
import '../providers/transaction_provider.dart';
import '../services/firestore_backup_service.dart';
import '../services/pdf_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
    _loadBackupInfo();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Backup / Restore / Auth
  // ---------------------------------------------------------------------------
  Future<void> _doBackup(BuildContext context) async {
    if (ref.read(isProcessingProvider)) return;
    ref.read(isProcessingProvider.notifier).setProcessing(true);
    ref.read(backupStatusProvider.notifier).updateStatus(BackupStatus.working);

    try {
      final db = ref.read(dbServiceProvider);
      await ref.read(firestoreBackupServiceProvider).backupAll(db);
      final info = await ref
          .read(firestoreBackupServiceProvider)
          .getBackupInfo();
      ref.read(backupInfoProvider.notifier).setInfo(info);
      ref
          .read(backupStatusProvider.notifier)
          .updateStatus(BackupStatus.success);
    } on NoInternetException {
      ref
          .read(backupStatusProvider.notifier)
          .updateStatus(BackupStatus.failedNoInternet);
    } on FirestoreTimeoutException {
      ref
          .read(backupStatusProvider.notifier)
          .updateStatus(BackupStatus.failedTimeout);
    } on NotSignedInException {
      ref
          .read(backupStatusProvider.notifier)
          .updateStatus(BackupStatus.failedPermission);
    } on FirestorePermissionException {
      ref
          .read(backupStatusProvider.notifier)
          .updateStatus(BackupStatus.failedPermission);
    } catch (e, stack) {
      if (kDebugMode) debugPrint('Backup Error: $e\n$stack');
      ref
          .read(backupStatusProvider.notifier)
          .updateStatus(BackupStatus.failedUnknown);
    } finally {
      ref.read(isProcessingProvider.notifier).setProcessing(false);
    }
  }

  Future<void> _doRestore(BuildContext context) async {
    if (ref.read(isProcessingProvider)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Restore from Cloud?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'This will CLEAR all local data and replace it with your cloud backup. Cannot be undone.',
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

      // `restoreAll()` writes directly into Hive. Riverpod lists are driven
      // by provider signals (`customersProvider` state and
      // `anyTransactionChangeProvider`). Without explicitly invalidating /
      // notifying, the UI may only refresh after a full app restart.
      ref.invalidate(customersProvider);
      ref.read(anyTransactionChangeProvider.notifier).notifyChanged();

      ref
          .read(backupStatusProvider.notifier)
          .updateStatus(BackupStatus.success);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Restore complete!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on NoInternetException {
      ref
          .read(backupStatusProvider.notifier)
          .updateStatus(BackupStatus.failedNoInternet);
    } on FirestoreTimeoutException {
      ref
          .read(backupStatusProvider.notifier)
          .updateStatus(BackupStatus.failedTimeout);
    } on FirestorePermissionException {
      ref
          .read(backupStatusProvider.notifier)
          .updateStatus(BackupStatus.failedPermission);
    } catch (e, stack) {
      if (kDebugMode) debugPrint('Restore Error: $e\n$stack');
      ref
          .read(backupStatusProvider.notifier)
          .updateStatus(BackupStatus.failedUnknown);
    } finally {
      ref.read(isProcessingProvider.notifier).setProcessing(false);
    }
  }

  Future<void> _signIn() async {
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
      _loadBackupInfo();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign-in failed. Please try again.')),
        );
      }
    }
  }

  Future<void> _signOut() async {
    await ref.read(authServiceProvider).signOut();

    // Clear local encrypted Hive data so the next sign-in starts fresh.
    final db = ref.read(dbServiceProvider);
    await db.clearAll();

    // Reset onboarding flag so the login screen shows again for new users.
    await db.setOnboardingCompleted(false);

    // Force-refresh provider-driven UI lists/counters.
    ref.invalidate(customersProvider);
    ref.read(anyTransactionChangeProvider.notifier).notifyChanged();

    ref.read(backupStatusProvider.notifier).updateStatus(BackupStatus.idle);
    ref.read(backupInfoProvider.notifier).setInfo(null);
  }

  Future<void> _loadBackupInfo() async {
    try {
      final info = await ref
          .read(firestoreBackupServiceProvider)
          .getBackupInfo();
      ref.read(backupInfoProvider.notifier).setInfo(info);
    } catch (_) {}
  }

  Future<void> _exportFullPdf(BuildContext context) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Generating Full Report PDF...')),
      );
      final db = ref.read(dbServiceProvider);
      final customers = db.getAllCustomers();
      final balances = ref.read(dashboardBalancesProvider);
      final txnsByCustomer = {
        for (final c in customers) c.id: db.getTransactionsForCustomer(c.id),
      };
      await PdfService.generateAndShareFullReport(
        customers: customers,
        transactionsByCustomer: txnsByCustomer,
        totalToReceive: balances['toReceive'] ?? 0,
        totalToPay: balances['toPay'] ?? 0,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error generating report. Please try again.'),
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final status = ref.watch(backupStatusProvider);
    final isProcessing = ref.watch(isProcessingProvider);
    final backupInfo = ref.watch(backupInfoProvider);
    final customers = ref.watch(customersProvider);
    final balances = ref.watch(dashboardBalancesProvider);
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: CustomScrollView(
          slivers: [
            // ---- Gradient SliverAppBar
            SliverAppBar(
              expandedHeight: 220,
              pinned: true,
              backgroundColor: const Color(0xFF005CEE),
              foregroundColor: Colors.white,
              flexibleSpace: FlexibleSpaceBar(
                background: _ProfileHeader(userAsync: userAsync),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.logout_rounded),
                  tooltip: 'Sign Out',
                  onPressed: () => userAsync.when(
                    data: (u) {
                      if (u != null) _signOut();
                    },
                    loading: () {},
                    error: (error, stackTrace) {},
                  ),
                ),
              ],
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ---- Stats Row
                    _SectionLabel('Overview'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: 'Customers',
                            value: '${customers.length}',
                            icon: Icons.people_alt_rounded,
                            color: const Color(0xFF005CEE),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            label: 'To Receive',
                            value: currency.format(balances['toReceive'] ?? 0),
                            icon: Icons.arrow_downward_rounded,
                            color: const Color(0xFF2E7D32),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            label: 'To Pay',
                            value: currency.format(balances['toPay'] ?? 0),
                            icon: Icons.arrow_upward_rounded,
                            color: const Color(0xFFC62828),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // ---- Export PDF
                    _SectionLabel('Export'),
                    const SizedBox(height: 10),
                    _ActionCard(
                      icon: Icons.picture_as_pdf_rounded,
                      iconColor: Colors.red.shade600,
                      title: 'Export Full Report',
                      subtitle: 'All customers & transactions as PDF',
                      onTap: () => _exportFullPdf(context),
                    ),

                    const SizedBox(height: 24),

                    // ---- Cloud Backup (only when signed in)
                    _SectionLabel('Cloud Sync'),
                    const SizedBox(height: 10),

                    userAsync.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator.adaptive(),
                      ),
                      error: (error, stackTrace) =>
                          const Text('Error loading account.'),
                      data: (User? user) {
                        if (user == null) {
                          return _ActionCard(
                            icon: Icons.login_rounded,
                            iconColor: const Color(0xFF005CEE),
                            title: 'Sign in with Google',
                            subtitle: 'Enable cloud backup for your data',
                            onTap: _signIn,
                          );
                        }
                        return Column(
                          children: [
                            // Backup info card
                            if (backupInfo != null)
                              _BackupInfoCard(info: backupInfo)
                            else
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(
                                  'No backup found for this account.',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 13,
                                  ),
                                ),
                              ),

                            // Status
                            _StatusWidget(status: status, onReconnect: _signIn),
                            if (status != BackupStatus.idle)
                              const SizedBox(height: 10),

                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.blue.shade50),
                              ),
                              child: Column(
                                children: [
                                  _GradientButton(
                                    label: isProcessing
                                        ? 'Working...'
                                        : 'Update to Cloud',
                                    icon: isProcessing
                                        ? null
                                        : Icons.cloud_upload_rounded,
                                    isLoading: isProcessing,
                                    onTap: isProcessing
                                        ? null
                                        : () => _doBackup(context),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Uploads latest local data to your Google account.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  OutlinedButton.icon(
                                    icon: const Icon(
                                      Icons.cloud_download_rounded,
                                    ),
                                    label: const Text('Restore from Cloud'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                      side: const BorderSide(color: Colors.red),
                                      minimumSize: const Size.fromHeight(50),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: isProcessing
                                        ? null
                                        : () => _doRestore(context),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.lock_outline,
                          size: 13,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Your data is end-to-end secured with Google.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile Header (inside SliverAppBar)
// ---------------------------------------------------------------------------

class _ProfileHeader extends StatelessWidget {
  final AsyncValue<User?> userAsync;

  const _ProfileHeader({required this.userAsync});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF003DA0), Color(0xFF005CEE), Color(0xFF1A7CFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
      child: userAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (error, stackTrace) => const SizedBox.shrink(),
        data: (User? user) {
          if (user == null) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_outline,
                    color: Colors.white70,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Guest User',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Sign in to enable cloud backup',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
            );
          }

          return Row(
            children: [
              // Avatar
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 36,
                  backgroundImage: user.photoURL != null
                      ? NetworkImage(user.photoURL!)
                      : null,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  child: user.photoURL == null
                      ? Text(
                          (user.displayName != null &&
                                  user.displayName!.isNotEmpty)
                              ? user.displayName!.substring(0, 1).toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontSize: 28,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      user.displayName ?? 'Unknown',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user.email ?? '',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.verified_rounded,
                            size: 13,
                            color: Colors.white70,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Google Account',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small helper widgets
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
        color: Colors.grey.shade500,
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.grey,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isLoading;
  final VoidCallback? onTap;

  const _GradientButton({
    required this.label,
    required this.isLoading,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Material(
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: onTap == null
                    ? [Colors.grey.shade300, Colors.grey.shade300]
                    : [const Color(0xFF005CEE), const Color(0xFF1A7CFF)],
              ),
            ),
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null)
                          Icon(icon, color: Colors.white, size: 18),
                        if (icon != null) const SizedBox(width: 8),
                        Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BackupInfoCard extends StatelessWidget {
  final Map<String, dynamic> info;
  const _BackupInfoCard({required this.info});

  @override
  Widget build(BuildContext context) {
    final ts = info['lastBackupAt'];
    String timeStr = 'Unknown';
    if (ts != null) {
      final DateTime dt;
      if (ts is DateTime) {
        dt = ts;
      } else {
        dt = (ts as Timestamp).toDate();
      }
      timeStr = DateFormat('dd MMM yyyy, hh:mm a').format(dt);
    }
    final customers = info['totalCustomers'] ?? 0;
    final transactions = info['totalTransactions'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_rounded,
            color: Colors.green.shade600,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Last backup: $timeStr',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$customers customers · $transactions transactions',
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusWidget extends StatelessWidget {
  final BackupStatus status;
  final VoidCallback? onReconnect;
  const _StatusWidget({required this.status, this.onReconnect});

  @override
  Widget build(BuildContext context) {
    if (status == BackupStatus.idle) return const SizedBox.shrink();
    if (status == BackupStatus.working) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('Backing up to cloud...'),
          ],
        ),
      );
    }

    late IconData icon;
    late Color color;
    late String message;

    switch (status) {
      case BackupStatus.success:
        icon = Icons.check_circle_rounded;
        color = Colors.green;
        message = 'Backup successful!';
      case BackupStatus.failedTimeout:
        icon = Icons.timer_off_rounded;
        color = Colors.orange;
        message = 'Connection timed out. Please try again.';
      case BackupStatus.failedNoInternet:
        icon = Icons.wifi_off_rounded;
        color = Colors.orange;
        message = 'No internet connection. Check and retry.';
      case BackupStatus.failedPermission:
        icon = Icons.lock_person_rounded;
        color = Colors.red;
        message = 'Session issue detected. Reconnect Google and retry.';
      case BackupStatus.failedUnknown:
        icon = Icons.error_outline_rounded;
        color = Colors.red;
        message = 'Something went wrong. Please retry.';
      default:
        return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          if (status == BackupStatus.failedPermission &&
              onReconnect != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onReconnect,
              icon: const Icon(Icons.login_rounded, size: 18),
              label: const Text('Reconnect Google'),
            ),
          ],
        ],
      ),
    );
  }
}
