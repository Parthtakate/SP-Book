import 'package:hive/hive.dart';

class Customer {
  final String id;
  final String name;
  final String? phone;
  final DateTime createdAt;

  Customer({
    required this.id,
    required this.name,
    this.phone,
    required this.createdAt,
  });

  Customer copyWith({
    String? name,
    String? phone,
  }) {
    return Customer(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      createdAt: createdAt,
    );
  }
}

class CustomerAdapter extends TypeAdapter<Customer> {
  @override
  final int typeId = 0;

  @override
  Customer read(BinaryReader reader) {
    return Customer(
      id: reader.readString(),
      name: reader.readString(),
      phone: reader.read() as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
    );
  }

  @override
  void write(BinaryWriter writer, Customer obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.name);
    writer.write(obj.phone);
    writer.writeInt(obj.createdAt.millisecondsSinceEpoch);
  }
}
