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
  final DateTime? updatedAt;
  final bool isDeleted;

  const ReminderModel({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.dueDate,
    this.note = '',
    required this.createdAt,
    this.updatedAt,
    this.isDeleted = false,
  });

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'customerId': customerId,
    'customerName': customerName,
    'dueDate': dueDate.millisecondsSinceEpoch,
    'note': note,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
    'isDeleted': isDeleted,
  };

  static DateTime _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.now(); // Fallback for absolute resilience
  }

  factory ReminderModel.fromFirestore(Map<String, dynamic> data) =>
      ReminderModel(
        id: data['id'] as String,
        customerId: data['customerId'] as String,
        customerName: data['customerName'] as String? ?? '',
        dueDate: _parseDate(data['dueDate']),
        note: data['note'] as String? ?? '',
        createdAt: _parseDate(data['createdAt']),
        updatedAt: data['updatedAt'] != null ? _parseDate(data['updatedAt']) : null,
        isDeleted: data['isDeleted'] as bool? ?? false,
      );

  ReminderModel copyWith({
    DateTime? dueDate,
    String? note,
    DateTime? updatedAt,
    bool? isDeleted,
  }) =>
      ReminderModel(
        id: id,
        customerId: customerId,
        customerName: customerName,
        dueDate: dueDate ?? this.dueDate,
        note: note ?? this.note,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        isDeleted: isDeleted ?? this.isDeleted,
      );
}
