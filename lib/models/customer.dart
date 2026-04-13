import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

/// Matches Khatabook's three contact categories.
enum ContactType { customer, supplier, staff }

class Customer {
  final String id;
  final String name;
  final String? phone;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isDeleted;
  final ContactType contactType;

  const Customer({
    required this.id,
    required this.name,
    this.phone,
    required this.createdAt,
    this.updatedAt,
    this.isDeleted = false,
    this.contactType = ContactType.customer,
  });

  Customer copyWith({
    String? name,
    String? phone,
    DateTime? updatedAt,
    bool? isDeleted,
    ContactType? contactType,
  }) {
    return Customer(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      contactType: contactType ?? this.contactType,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'name': name,
    'phone': phone,
    // Use the actual stored createdAt date — NOT serverTimestamp().
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': FieldValue.serverTimestamp(),
    'isDeleted': isDeleted,
    'contactType': contactType.name,
  };

  factory Customer.fromFirestore(Map<String, dynamic> data) => Customer(
    id: data['id'] as String,
    name: data['name'] as String,
    phone: data['phone'] as String?,
    createdAt: (data['createdAt'] as Timestamp).toDate(),
    updatedAt: data['updatedAt'] != null
        ? (data['updatedAt'] as Timestamp).toDate()
        : null,
    isDeleted: data['isDeleted'] as bool? ?? false,
    contactType: _parseContactType(data['contactType'] as String?),
  );

  /// Safe parser — old Firestore docs without 'contactType' default to customer.
  static ContactType _parseContactType(String? raw) {
    if (raw == null) return ContactType.customer;
    try {
      return ContactType.values.byName(raw);
    } catch (_) {
      return ContactType.customer;
    }
  }
}

class CustomerAdapter extends TypeAdapter<Customer> {
  @override
  final int typeId = 0; // Unchanged — no migration needed, we append the field.

  @override
  Customer read(BinaryReader reader) {
    final id = reader.readString();
    final name = reader.readString();
    final phone = reader.read();
    final createdAt = DateTime.fromMillisecondsSinceEpoch(reader.readInt());
    final hasUpdatedAt = reader.readBool();
    final updatedAt = hasUpdatedAt
        ? DateTime.fromMillisecondsSinceEpoch(reader.readInt())
        : null;
    // isDeleted was also appended — same try/catch safety pattern.
    final isDeleted = () {
      try {
        return reader.readBool();
      } catch (_) {
        return false;
      }
    }();
    // contactType is the newest field — old records won't have these bytes.
    // The try/catch gracefully defaults old records to ContactType.customer.
    final contactType = () {
      try {
        final raw = reader.readString();
        return ContactType.values.byName(raw);
      } catch (_) {
        return ContactType.customer;
      }
    }();
    return Customer(
      id: id,
      name: name,
      phone: phone,
      createdAt: createdAt,
      updatedAt: updatedAt,
      isDeleted: isDeleted,
      contactType: contactType,
    );
  }

  @override
  void write(BinaryWriter writer, Customer obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.name);
    writer.write(obj.phone);
    writer.writeInt(obj.createdAt.millisecondsSinceEpoch);
    writer.writeBool(obj.updatedAt != null);
    if (obj.updatedAt != null) {
      writer.writeInt(obj.updatedAt!.millisecondsSinceEpoch);
    }
    writer.writeBool(obj.isDeleted);
    writer.writeString(obj.contactType.name); // Appended last — backward compat
  }
}
