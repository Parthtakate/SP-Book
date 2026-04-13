import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

/// Represents one independent ledger/shop managed by the user.
/// typeId=3 — first usage of this adapter slot.
class Khatabook {
  final String id;       // UUID; 'default' for the auto-migrated first book
  final String name;     // e.g. "Trimurti Chikki"
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isDeleted;

  const Khatabook({
    required this.id,
    required this.name,
    required this.createdAt,
    this.updatedAt,
    this.isDeleted = false,
  });

  // ── Computed helpers ──────────────────────────────────────────────────────

  /// Two-letter initials for the avatar circle (e.g. "TC" for "Trimurti Chikki").
  String get initials {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '??';
    final words = trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length == 1) {
      return words[0].length >= 2
          ? words[0].substring(0, 2).toUpperCase()
          : words[0][0].toUpperCase();
    }
    return '${words[0][0]}${words[1][0]}'.toUpperCase();
  }

  // ── Immutable copy ────────────────────────────────────────────────────────

  Khatabook copyWith({
    String? name,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return Khatabook(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  // ── Firestore ─────────────────────────────────────────────────────────────

  /// Serialised form stored at users/{uid}/khatabooks/{id}
  Map<String, dynamic> toFirestore() => {
    'id': id,
    'name': name,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': FieldValue.serverTimestamp(),
    'isDeleted': isDeleted,
  };

  factory Khatabook.fromFirestore(Map<String, dynamic> data) => Khatabook(
    id: data['id'] as String,
    name: data['name'] as String? ?? 'Unnamed',
    createdAt: data['createdAt'] is Timestamp
        ? (data['createdAt'] as Timestamp).toDate()
        : DateTime.now(),
    updatedAt: data['updatedAt'] != null
        ? (data['updatedAt'] as Timestamp).toDate()
        : null,
    isDeleted: data['isDeleted'] as bool? ?? false,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Hive TypeAdapter — typeId = 3
// Manual adapter (no code-gen) — same pattern as CustomerAdapter / TransactionModelAdapter.
// Fields are append-only: new fields go at the END of write() and are wrapped
// in try/catch inside read() for backward compatibility.
// ─────────────────────────────────────────────────────────────────────────────

class KhatabookAdapter extends TypeAdapter<Khatabook> {
  @override
  final int typeId = 3;

  @override
  Khatabook read(BinaryReader reader) {
    final id = reader.readString();
    final name = reader.readString();
    final createdAt = DateTime.fromMillisecondsSinceEpoch(reader.readInt());
    final hasUpdatedAt = reader.readBool();
    final updatedAt = hasUpdatedAt
        ? DateTime.fromMillisecondsSinceEpoch(reader.readInt())
        : null;
    final isDeleted = () {
      try { return reader.readBool(); } catch (_) { return false; }
    }();

    return Khatabook(
      id: id,
      name: name,
      createdAt: createdAt,
      updatedAt: updatedAt,
      isDeleted: isDeleted,
    );
  }

  @override
  void write(BinaryWriter writer, Khatabook obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.name);
    writer.writeInt(obj.createdAt.millisecondsSinceEpoch);
    writer.writeBool(obj.updatedAt != null);
    if (obj.updatedAt != null) {
      writer.writeInt(obj.updatedAt!.millisecondsSinceEpoch);
    }
    writer.writeBool(obj.isDeleted);
  }
}
