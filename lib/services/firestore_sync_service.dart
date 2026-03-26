import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/customer.dart';
import '../models/transaction.dart';
import '../providers/db_provider.dart';

// Incremental live sync: every local add/edit/delete enqueues a small write
// and then immediately tries to flush the queue to Firestore.
//
// If offline / timed out, the operation remains queued and will be retried
// on next app open and on next local change.
class FirestoreSyncService {
  FirestoreSyncService(this.ref);

  final Ref ref;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isFlushing = false;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Future<void> enqueueAndFlush({
    required String opType,
    required String id,
    Map<String, dynamic>? data,
  }) async {
    await _enqueueOp(
      opType: opType,
      id: id,
      data: data,
    );

    // Best-effort immediate flush; if it fails, the op stays queued.
    await flushPending();
  }

  Future<void> _enqueueOp({
    required String opType,
    required String id,
    Map<String, dynamic>? data,
  }) async {
    final uid = _uid;
    if (uid == null) return; // Guest mode: keep local-only.

    final queueBox = ref.read(dbServiceProvider).syncQueueBox;
    final op = <String, dynamic>{
      'opType': opType,
      'id': id,
      ...(data == null ? const <String, dynamic>{} : {'data': data}),
    };

    await queueBox.add(jsonEncode(op));
  }

  Future<void> flushPending() async {
    final uid = _uid;
    if (uid == null) return;

    if (_isFlushing) return;
    _isFlushing = true;
    try {
      final queueBox = ref.read(dbServiceProvider).syncQueueBox;
      final keys = queueBox.keys.toList();

      for (final key in keys) {
        final raw = queueBox.get(key);
        if (raw == null) {
          await queueBox.delete(key);
          continue;
        }

        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final opType = decoded['opType'] as String;
        final id = decoded['id'] as String;
        final dataDynamic = decoded['data'];
        final Map<String, dynamic>? data = dataDynamic is Map
            ? dataDynamic.map((k, v) => MapEntry(k.toString(), v))
            : null;

        try {
          // Apply with a timeout so we don't block forever.
          await _applyOp(
            uid: uid,
            opType: opType,
            id: id,
            data: data,
          ).timeout(const Duration(seconds: 12));

          // Success -> remove from queue.
          await queueBox.delete(key);
        } catch (_) {
          // Stop at first failure: keep remaining ops for later retry.
          return;
        }
      }
    } finally {
      _isFlushing = false;
    }
  }

  Future<void> _applyOp({
    required String uid,
    required String opType,
    required String id,
    required Map<String, dynamic>? data,
  }) async {
    final userDoc = _firestore.collection('users').doc(uid);

    switch (opType) {
      case 'customer_upsert':
        await userDoc
            .collection('customers')
            .doc(id)
            .set(
              {
                ...?data,
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: false),
            );
        return;

      case 'customer_delete':
        await userDoc.collection('customers').doc(id).delete();
        return;

      case 'txn_upsert':
        await userDoc
            .collection('transactions')
            .doc(id)
            .set(
              {
                ...?data,
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: false),
            );
        return;

      case 'txn_delete':
        await userDoc.collection('transactions').doc(id).delete();
        return;

      default:
        // Unknown op: treat as no-op so the queue doesn't get stuck.
        return;
    }
  }

  Future<void> syncCustomerUpsert(Customer customer) async {
    await enqueueAndFlush(
      opType: 'customer_upsert',
      id: customer.id,
      data: {
        'id': customer.id,
        'name': customer.name,
        'phone': customer.phone,
        'createdAt': customer.createdAt.millisecondsSinceEpoch,
      },
    );
  }

  Future<void> syncCustomerDelete({
    required String customerId,
    required List<String> transactionIds,
  }) async {
    await _enqueueOp(
      opType: 'customer_delete',
      id: customerId,
    );

    // Ensure remote transactions are also removed to prevent orphans.
    for (final txnId in transactionIds) {
      await _enqueueOp(
        opType: 'txn_delete',
        id: txnId,
      );
    }

    await flushPending();
  }

  Future<void> syncTransactionUpsert(TransactionModel txn) async {
    await enqueueAndFlush(
      opType: 'txn_upsert',
      id: txn.id,
      data: {
        'id': txn.id,
        'customerId': txn.customerId,
        'amount': txn.amount,
        'isGot': txn.isGot,
        'note': txn.note,
        'date': txn.date.millisecondsSinceEpoch,
        // Intentionally do NOT sync local `imagePath` (device-specific).
      },
    );
  }

  Future<void> syncTransactionDelete(String txnId) async {
    await enqueueAndFlush(
      opType: 'txn_delete',
      id: txnId,
    );
  }
}

final firestoreSyncServiceProvider = Provider<FirestoreSyncService>((ref) {
  return FirestoreSyncService(ref);
});

