import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

class TransactionModel {
  final String id;
  final String customerId;
  final double amount;
  final bool isGot; // true: You Got (money received), false: You Gave (money given)
  final String note;
  final DateTime date;
  final String? imagePath;
  // V3 — appended field for cloud sync conflict resolution (nullable for backward compat)
  final DateTime? updatedAt;

  TransactionModel({
    required this.id,
    required this.customerId,
    required this.amount,
    required this.isGot,
    this.note = '',
    required this.date,
    this.imagePath,
    this.updatedAt,
  });

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'customerId': customerId,
    'amount': amount,
    'isGot': isGot,
    'note': note,
    'date': date.millisecondsSinceEpoch,
    // 'imagePath': intentionally excluded, local device paths break upon cloud restore on new devices
    'updatedAt': FieldValue.serverTimestamp(),
  };

  factory TransactionModel.fromFirestore(Map<String, dynamic> data) =>
      TransactionModel(
        id: data['id'] as String,
        customerId: data['customerId'] as String,
        amount: (data['amount'] as num).toDouble(),
        isGot: data['isGot'] as bool,
        note: data['note'] as String? ?? '',
        date: DateTime.fromMillisecondsSinceEpoch(data['date'] as int),
        imagePath: data['imagePath'] as String?,
        updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      );
}

class TransactionModelAdapter extends TypeAdapter<TransactionModel> {
  @override
  final int typeId = 1;

  @override
  TransactionModel read(BinaryReader reader) {
    final id = reader.readString();
    final customerId = reader.readString();
    final amount = reader.readDouble();
    final isGot = reader.readBool();
    final note = reader.readString();
    final date = DateTime.fromMillisecondsSinceEpoch(reader.readInt());
    final hasImage = reader.readBool();
    final imagePath = hasImage ? reader.readString() : null;
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
    return TransactionModel(
      id: id,
      customerId: customerId,
      amount: amount,
      isGot: isGot,
      note: note,
      date: date,
      imagePath: imagePath,
      updatedAt: updatedAt,
    );
  }

  @override
  void write(BinaryWriter writer, TransactionModel obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.customerId);
    writer.writeDouble(obj.amount);
    writer.writeBool(obj.isGot);
    writer.writeString(obj.note);
    writer.writeInt(obj.date.millisecondsSinceEpoch);
    writer.writeBool(obj.imagePath != null);
    if (obj.imagePath != null) {
      writer.writeString(obj.imagePath!);
    }
    // V3: appended — null-presence flag
    writer.writeBool(obj.updatedAt != null);
    if (obj.updatedAt != null) {
      writer.writeInt(obj.updatedAt!.millisecondsSinceEpoch);
    }
  }
}
