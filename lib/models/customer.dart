import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

class Customer {
  final String id;
  final String name;
  final String? phone;
  final DateTime createdAt;
  // V3 — appended field for cloud sync conflict resolution (nullable for backward compat)
  final DateTime? updatedAt;

  Customer({
    required this.id,
    required this.name,
    this.phone,
    required this.createdAt,
    this.updatedAt,
  });

  Customer copyWith({
    String? name,
    String? phone,
    DateTime? updatedAt,
  }) {
    return Customer(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'name': name,
    'phone': phone,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  factory Customer.fromFirestore(Map<String, dynamic> data) => Customer(
    id: data['id'] as String,
    name: data['name'] as String,
    phone: data['phone'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(data['createdAt'] as int),
    updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
  );
}

// ignore: avoid_classes_with_only_static_members
class CustomerAdapter extends TypeAdapter<Customer> {
  @override
  final int typeId = 0;

  @override
  Customer read(BinaryReader reader) {
    final id = reader.readString();
    final name = reader.readString();
    final dynamic rawPhone = reader.read();
    final String? phone = rawPhone is String ? rawPhone : null;
    final createdAt = DateTime.fromMillisecondsSinceEpoch(reader.readInt());
    // V3: appended field — null-presence flag for backward compat
    DateTime? updatedAt;
    try {
      final hasUpdatedAt = reader.readBool();
      if (hasUpdatedAt) {
        updatedAt = DateTime.fromMillisecondsSinceEpoch(reader.readInt());
      }
    } catch (_) {
      // Old data — no updatedAt field, leave as null
    }
    return Customer(
      id: id,
      name: name,
      phone: phone,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  @override
  void write(BinaryWriter writer, Customer obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.name);
    writer.write(obj.phone);
    writer.writeInt(obj.createdAt.millisecondsSinceEpoch);
    // V3: appended — null-presence flag
    writer.writeBool(obj.updatedAt != null);
    if (obj.updatedAt != null) {
      writer.writeInt(obj.updatedAt!.millisecondsSinceEpoch);
    }
  }
}
