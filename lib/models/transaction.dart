import 'package:hive/hive.dart';

class TransactionModel {
  final String id;
  final String customerId;
  final double amount;
  final bool isGot; // true: You Got (money received), false: You Gave (money given)
  final String note;
  final DateTime date;
  final String? imagePath;

  TransactionModel({
    required this.id,
    required this.customerId,
    required this.amount,
    required this.isGot,
    this.note = '',
    required this.date,
    this.imagePath,
  });
}

class TransactionModelAdapter extends TypeAdapter<TransactionModel> {
  @override
  final int typeId = 1;

  @override
  TransactionModel read(BinaryReader reader) {
    return TransactionModel(
      id: reader.readString(),
      customerId: reader.readString(),
      amount: reader.readDouble(),
      isGot: reader.readBool(),
      note: reader.readString(),
      date: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
      imagePath: reader.readBool() ? reader.readString() : null,
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
  }
}
