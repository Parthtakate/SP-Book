import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

class TransactionModel {
  final String id;
  final String customerId;
  final int amountInPaise;
  final bool isGot; // true: You Got (money received), false: You Gave (money given)
  final String note;
  final DateTime date;
  final String? imagePath;
  final DateTime? updatedAt;
  final bool isDeleted;
  final String khatabookId; // which ledger this transaction belongs to

  const TransactionModel({
    required this.id,
    required this.customerId,
    required this.amountInPaise,
    required this.isGot,
    this.note = '',
    required this.date,
    this.imagePath,
    this.updatedAt,
    this.isDeleted = false,
    this.khatabookId = 'default',
  });

  TransactionModel copyWith({
    int? amountInPaise,
    bool? isGot,
    String? note,
    String? imagePath,
    DateTime? date,
    DateTime? updatedAt,
    bool? isDeleted,
    String? khatabookId,
  }) {
    return TransactionModel(
      id: id,
      customerId: customerId,
      amountInPaise: amountInPaise ?? this.amountInPaise,
      isGot: isGot ?? this.isGot,
      note: note ?? this.note,
      date: date ?? this.date,
      imagePath: imagePath ?? this.imagePath,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      khatabookId: khatabookId ?? this.khatabookId,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'customerId': customerId,
    'amountInPaise': amountInPaise,
    'isGot': isGot,
    'note': note,
    'date': date.millisecondsSinceEpoch,
    'imagePath': imagePath, // Included as null if absent to satisfy rule sync
    'updatedAt': FieldValue.serverTimestamp(),
    'isDeleted': isDeleted,
    'khatabookId': khatabookId,
  };

  factory TransactionModel.fromFirestore(Map<String, dynamic> data) =>
      TransactionModel(
        id: data['id'] as String,
        customerId: data['customerId'] as String,
        amountInPaise: (data['amountInPaise'] ?? 0) as int,
        isGot: data['isGot'] as bool,
        note: data['note'] as String? ?? '',
        date: (data['date'] is Timestamp) ? (data['date'] as Timestamp).toDate() : DateTime.fromMillisecondsSinceEpoch(data['date'] as int),
        imagePath: data['imagePath'] as String?,
        updatedAt: data['updatedAt'] != null ? (data['updatedAt'] as Timestamp).toDate() : null,
        isDeleted: data['isDeleted'] as bool? ?? false,
        khatabookId: data['khatabookId'] as String? ?? 'default',
      );
}

class TransactionModelAdapter extends TypeAdapter<TransactionModel> {
  @override
  final int typeId = 2;

  @override
  TransactionModel read(BinaryReader reader) {
    return TransactionModel(
      id: reader.readString(),
      customerId: reader.readString(),
      amountInPaise: reader.readInt(),
      isGot: reader.readBool(),
      note: reader.readString(),
      date: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
      imagePath: reader.readBool() ? reader.readString() : null,
      updatedAt: reader.readBool() ? DateTime.fromMillisecondsSinceEpoch(reader.readInt()) : null,
      isDeleted: () {
        try { return reader.readBool(); } catch (_) { return false; }
      }(),
      khatabookId: () {
        try { return reader.readString(); } catch (_) { return 'default'; }
      }(),
    );
  }

  @override
  void write(BinaryWriter writer, TransactionModel obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.customerId);
    writer.writeInt(obj.amountInPaise);
    writer.writeBool(obj.isGot);
    writer.writeString(obj.note);
    writer.writeInt(obj.date.millisecondsSinceEpoch);
    writer.writeBool(obj.imagePath != null);
    if (obj.imagePath != null) {
      writer.writeString(obj.imagePath!);
    }
    writer.writeBool(obj.updatedAt != null);
    if (obj.updatedAt != null) {
      writer.writeInt(obj.updatedAt!.millisecondsSinceEpoch);
    }
    writer.writeBool(obj.isDeleted);
    writer.writeString(obj.khatabookId); // Appended last — backward compat
  }
}
