import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

class Customer {
  final String id;
  final String name;
  final String? phone;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isDeleted;

  const Customer({
    required this.id,
    required this.name,
    this.phone,
    required this.createdAt,
    this.updatedAt,
    this.isDeleted = false,
  });

  Customer copyWith({
    String? name,
    String? phone,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return Customer(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'name': name,
    'phone': phone,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
    'isDeleted': isDeleted,
  };

  factory Customer.fromFirestore(Map<String, dynamic> data) => Customer(
    id: data['id'] as String,
    name: data['name'] as String,
    phone: data['phone'] as String?,
    createdAt: (data['createdAt'] as Timestamp).toDate(),
    updatedAt: data['updatedAt'] != null ? (data['updatedAt'] as Timestamp).toDate() : null,
    isDeleted: data['isDeleted'] as bool? ?? false,
  );
}

class CustomerAdapter extends TypeAdapter<Customer> {
  @override
  final int typeId = 0;

  @override
  Customer read(BinaryReader reader) {
    return Customer(
      id: reader.readString(),
      name: reader.readString(),
      phone: reader.read(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
      updatedAt: reader.readBool() ? DateTime.fromMillisecondsSinceEpoch(reader.readInt()) : null,
      isDeleted: reader.readBool(),
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
  }
}
