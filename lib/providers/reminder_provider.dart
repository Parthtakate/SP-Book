import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/reminder.dart';
import '../services/reminder_service.dart';
import 'auth_provider.dart';

/// Provides a [ReminderService] only when a user is authenticated.
/// Returns null when no user is logged in — callers must handle this.
final reminderServiceProvider = Provider<ReminderService?>((ref) {
  final userAsync = ref.watch(currentUserProvider);
  final user = userAsync.value;
  if (user == null) return null;

  return ReminderService(
    firestore: FirebaseFirestore.instance,
    userId: user.uid,
  );
});

/// Streams reminders for a given [customerId].
/// Emits an empty list when the user is not authenticated or has no reminders.
final reminderProvider =
    StreamProvider.family<List<ReminderModel>, String>((ref, customerId) {
  final service = ref.watch(reminderServiceProvider);
  if (service == null) return const Stream.empty();
  return service.remindersForCustomer(customerId);
});

/// Streams all reminders for the current user (used by a notifications page or badge).
final allRemindersProvider =
    StreamProvider<List<ReminderModel>>((ref) {
  final service = ref.watch(reminderServiceProvider);
  if (service == null) return const Stream.empty();
  return service.allReminders();
});
