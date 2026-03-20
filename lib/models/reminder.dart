import 'package:cloud_firestore/cloud_firestore.dart';

/// Immutable reminder model stored in Firestore `reminders/{userId}/{reminderId}`.
/// Loosely coupled to customers — references by ID only, no FK enforcement.
class ReminderModel {
  final String id;
  final String customerId;
  final String customerName;
  final DateTime dueDate;
  final String note;
  final DateTime createdAt;

  const ReminderModel({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.dueDate,
    this.note = '',
    required this.createdAt,
  });

  Map<String, dynamic> toFirestore() => {
        'id': id,
        'customerId': customerId,
        'customerName': customerName,
        'dueDate': dueDate.millisecondsSinceEpoch,
        'note': note,
        'createdAt': FieldValue.serverTimestamp(),
      };

  factory ReminderModel.fromFirestore(Map<String, dynamic> data) =>
      ReminderModel(
        id: data['id'] as String,
        customerId: data['customerId'] as String,
        customerName: data['customerName'] as String? ?? '',
        dueDate:
            DateTime.fromMillisecondsSinceEpoch(data['dueDate'] as int),
        note: data['note'] as String? ?? '',
        createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  ReminderModel copyWith({
    DateTime? dueDate,
    String? note,
  }) =>
      ReminderModel(
        id: id,
        customerId: customerId,
        customerName: customerName,
        dueDate: dueDate ?? this.dueDate,
        note: note ?? this.note,
        createdAt: createdAt,
      );
}
