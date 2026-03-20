import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/reminder.dart';

/// Write-only service for the `reminders` Firestore collection.
/// Path: reminders/{userId}/{reminderId}
///
/// Responsibilities:
///   - Add reminders (write)
///   - Stream reminders per customer (read)
///
/// Strictly follows the existing service pattern in this codebase:
/// one class, injected dependencies, no provider/UI knowledge.
class ReminderService {
  final FirebaseFirestore _firestore;
  final String userId;

  ReminderService({required FirebaseFirestore firestore, required this.userId})
      : _firestore = firestore;

  CollectionReference<Map<String, dynamic>> get _remindersCol =>
      _firestore.collection('reminders').doc(userId).collection('items');

  /// Writes a reminder document. Idempotent — uses [reminder.id] as the doc ID.
  Future<void> addReminder(ReminderModel reminder) async {
    await _remindersCol.doc(reminder.id).set(reminder.toFirestore());
  }

  /// Streams all reminders for a specific [customerId], ordered by dueDate asc.
  Stream<List<ReminderModel>> remindersForCustomer(String customerId) {
    return _remindersCol
        .where('customerId', isEqualTo: customerId)
        .orderBy('dueDate')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ReminderModel.fromFirestore(doc.data()))
              .toList(),
        );
  }

  /// Streams ALL reminders for this user, ordered by dueDate asc.
  Stream<List<ReminderModel>> allReminders() {
    return _remindersCol
        .orderBy('dueDate')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ReminderModel.fromFirestore(doc.data()))
              .toList(),
        );
  }
}
