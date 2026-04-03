import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/auth_provider.dart';
import '../providers/auto_sync_provider.dart';
import '../providers/customer_provider.dart';
import '../providers/db_provider.dart';
import '../providers/transaction_provider.dart';
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
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Backup / Restore / Auth
  // ---------------------------------------------------------------------------
  Future<void> _signIn() async {
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
      await ref.read(dbServiceProvider).setLoggedIn(true);
      // AutoSyncService picks this up and does a startup conflict check
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign-in failed. Please try again.')),
        );
      }
    }
  }

  Future<void> _signOut() async {
    // Show loading indicator to the user while we trigger a final backup
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Syncing data before signing out...'),
          duration: Duration(seconds: 3),
        ),
      );
    }

    // Trigger one final backup to ensure cloud is up to date before leaving.
    // We intentionally do NOT clear local data — Hive is the persistent cache
    // and will restore correctly on the next sign-in via the startup sync check.
    try {
      final db = ref.read(dbServiceProvider);
      final backupService = ref.read(firestoreBackupServiceProvider);
      await backupService.backupAll(db);
    } catch (_) {
      // Best-effort: even if this fails, we still sign out safely.
    }

    final db = ref.read(dbServiceProvider);
    await ref.read(authServiceProvider).signOut();
    
    // Clear local data so user is fully logged out and data refreshes on next login
    await db.clearAll();
    await db.setOnboardingCompleted(false);
    await db.setLoggedIn(false);
    await db.setLastLocalModifiedAt(0);

    // Invalidate UI providers
    ref.invalidate(customersProvider);
    ref.invalidate(dashboardBalancesProvider);
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
    final autoSyncState = ref.watch(autoSyncProvider);
    final customers = ref.watch(customersProvider);
    final balances = ref.watch(dashboardBalancesProvider);
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // Softer, more modern background (Tailwind slate-100)
      body: FadeTransition(
        opacity: _fadeAnim,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ---- Premium Gradient SliverAppBar
            SliverAppBar(
              expandedHeight: 240,
              pinned: true,
              stretch: true,
              backgroundColor: const Color(0xFF0F172A), // Deep modern dark blue
              foregroundColor: Colors.white,
              flexibleSpace: FlexibleSpaceBar(
                stretchModes: const [StretchMode.zoomBackground, StretchMode.blurBackground],
                background: _ProfileHeader(userAsync: userAsync),
              ),
              actions: [
                userAsync.when(
                  data: (u) => u != null
                      ? IconButton(
                          icon: const Icon(Icons.logout_rounded, color: Colors.white),
                          tooltip: 'Sign Out',
                          onPressed: () => _signOut(),
                        )
                      : const SizedBox.shrink(),
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
              ],
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ---- Stats Row
                    _SectionLabel('Your Overview'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: 'Customers',
                            value: '${customers.length}',
                            icon: Icons.people_alt_rounded,
                            color: const Color(0xFF3B82F6), // Blue
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            label: 'To Receive',
                            value: currency.format(balances['toReceive'] ?? 0),
                            icon: Icons.south_west_rounded,
                            color: const Color(0xFF10B981), // Emerald
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            label: 'To Pay',
                            value: currency.format(balances['toPay'] ?? 0),
                            icon: Icons.north_east_rounded,
                            color: const Color(0xFFEF4444), // Red
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),

                    // ---- Account & Backup Card
                    _SectionLabel('Data & Sync'),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          userAsync.when(
                            loading: () => const Padding(
                              padding: EdgeInsets.all(24.0),
                              child: Center(
                                child: CircularProgressIndicator.adaptive(),
                              ),
                            ),
                            error: (error, stackTrace) =>
                                const Text('Error loading account.'),
                            data: (User? user) {
                              if (user == null) {
                                return _ActionCard(
                                  icon: Icons.g_mobiledata_rounded,
                                  iconColor: const Color(0xFF3B82F6),
                                  title: 'Sign in with Google',
                                  subtitle: 'Enable cloud backup & sync',
                                  onTap: _signIn,
                                );
                              }
                              // We modified AutoSyncStatusCard to be borderless
                              return Padding(
                                padding: const EdgeInsets.all(4.0),
                                child: _AutoSyncStatusCard(syncState: autoSyncState),
                              );
                            },
                          ),
                          const Divider(height: 1, indent: 64),
                          _ActionCard(
                            icon: Icons.picture_as_pdf_rounded,
                            iconColor: const Color(0xFFEF4444),
                            title: 'Export Full Report',
                            subtitle: 'Download your ledger as a PDF file',
                            onTap: () => _exportFullPdf(context),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ---- About Section
                    _SectionLabel('About Khata App'),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _ActionCard(
                            icon: Icons.star_rounded,
                            iconColor: const Color(0xFFF59E0B),
                            title: 'Rate Us',
                            subtitle: 'Love the app? Leave a review',
                            onTap: () {
                               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks for your support!')));
                            },
                          ),
                          const Divider(height: 1, indent: 64),
                          _ActionCard(
                            icon: Icons.share_rounded,
                            iconColor: const Color(0xFF10B981),
                            title: 'Share Khata App',
                            subtitle: 'Recommend us to your merchant friends',
                            onTap: () {
                               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Share feature coming soon!')));
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),
                    Center(
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.lock_outline_rounded,
                                size: 14,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'End-to-End Secured by Google Firebase',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Version 1.0.0',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
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

class _ProfileHeader extends ConsumerWidget {
  final AsyncValue<User?> userAsync;

  const _ProfileHeader({required this.userAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A), // Removed gradient, went with solid deep dark blue for modern minimalist edge
        image: DecorationImage(
          image: NetworkImage('https://www.transparenttextures.com/patterns/cubes.png'),
          opacity: 0.1,
          repeat: ImageRepeat.repeat,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
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
                  'Guest Mode',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Tap "Sign in with Google" below to sync',
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: const BoxDecoration(
            color: Colors.transparent, // Let master card handle background
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

// Removed _GradientButton

// Removed _BackupInfoCard

class _AutoSyncStatusCard extends StatelessWidget {
  final AutoSyncState syncState;

  const _AutoSyncStatusCard({required this.syncState});

  @override
  Widget build(BuildContext context) {
    String timeStr = 'Never';
    if (syncState.lastSyncedAt != null) {
      timeStr = DateFormat('dd MMM, hh:mm a').format(syncState.lastSyncedAt!);
    }

    late IconData icon;
    late Color color;
    late String statusText;
    bool showSpinner = false;

    switch (syncState.status) {
      case SyncStatus.idle:
      case SyncStatus.synced:
        icon = Icons.cloud_done_rounded;
        color = Colors.green.shade600;
        statusText = 'Up to date';
        break;
      case SyncStatus.syncing:
        icon = Icons.cloud_sync_rounded;
        color = const Color(0xFF005CEE);
        statusText = 'Syncing...';
        showSpinner = true;
        break;
      case SyncStatus.offline:
        icon = Icons.cloud_off_rounded;
        color = Colors.orange;
        statusText = 'Offline (waiting)';
        break;
      case SyncStatus.failed:
        icon = Icons.error_outline_rounded;
        color = Colors.red;
        statusText = 'Sync failed';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.transparent, // Let parent card handle color/borders
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (showSpinner)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              else
                Icon(icon, color: color, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                     const Text(
                       'Auto-Sync Enabled',
                       style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                     ),
                     const SizedBox(height: 2),
                     Text(
                       'Status: $statusText',
                       style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500),
                     ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Text(
            'Last synced: $timeStr',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
