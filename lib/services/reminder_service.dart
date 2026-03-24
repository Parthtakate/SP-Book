import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../models/reminder.dart';
import '../models/customer.dart';

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

  /// Attempts to fire a smart intent to WhatsApp or SMS
  Future<bool> sendWhatsAppReminder(Customer customer, double balance) async {
    if (customer.phone == null || customer.phone!.isEmpty) {
      return false; // No phone
    }
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final msg =
        'Hi ${customer.name}, your pending balance is ${currencyFormat.format(balance.abs())}. Please clear it when possible. Thank you!';
    final url = Uri.parse(
        'whatsapp://send?phone=${customer.phone}&text=${Uri.encodeComponent(msg)}');

    if (await canLaunchUrl(url)) {
      return await launchUrl(url);
    } else {
      final smsUrl = Uri.parse(
          'sms:${customer.phone}?body=${Uri.encodeComponent(msg)}');
      if (await canLaunchUrl(smsUrl)) {
        return await launchUrl(smsUrl);
      }
    }
    return false;
  }
}
