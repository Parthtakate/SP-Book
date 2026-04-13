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
  final String khatabookId; // which ledger this contact belongs to

  const Customer({
    required this.id,
    required this.name,
    this.phone,
    required this.createdAt,
    this.updatedAt,
    this.isDeleted = false,
    this.contactType = ContactType.customer,
    this.khatabookId = 'default',
  });

  /// True when this contact belongs to the original/default ledger.
  bool get isInDefaultBook => khatabookId == 'default';

  Customer copyWith({
    String? name,
    String? phone,
    DateTime? updatedAt,
    bool? isDeleted,
    ContactType? contactType,
    String? khatabookId,
  }) {
    return Customer(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      contactType: contactType ?? this.contactType,
      khatabookId: khatabookId ?? this.khatabookId,
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
    'khatabookId': khatabookId,
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
    khatabookId: data['khatabookId'] as String? ?? 'default',
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
    // contactType — appended in a previous version.
    final contactType = () {
      try {
        final raw = reader.readString();
        return ContactType.values.byName(raw);
      } catch (_) {
        return ContactType.customer;
      }
    }();
    // khatabookId — newest field; old records without it default to 'default'.
    final khatabookId = () {
      try { return reader.readString(); } catch (_) { return 'default'; }
    }();
    return Customer(
      id: id,
      name: name,
      phone: phone,
      createdAt: createdAt,
      updatedAt: updatedAt,
      isDeleted: isDeleted,
      contactType: contactType,
      khatabookId: khatabookId,
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
    writer.writeString(obj.contactType.name); // Appended — backward compat
    writer.writeString(obj.khatabookId);      // Appended last — backward compat
  }
}
