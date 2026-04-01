import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/customer.dart';
import '../models/transaction.dart';

class FirestoreSyncService {
  FirestoreSyncService(this.ref);

  final Ref ref;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  CollectionReference _customersRef(String uid) =>
      _firestore.collection('users').doc(uid).collection('customers');

  CollectionReference _transactionsRef(String uid) =>
      _firestore.collection('users').doc(uid).collection('transactions');

  Future<void> syncCustomerUpsert(Customer customer) async {
    final uid = _uid;
    if (uid == null) return;
    await _customersRef(uid).doc(customer.id).set(
      {
        ...customer.toFirestore(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> syncCustomerDelete({
    required String customerId,
    required List<String> transactionIds,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    
    final batch = _firestore.batch();
    batch.update(_customersRef(uid).doc(customerId), {
      'isDeleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    for (final txnId in transactionIds) {
      batch.update(_transactionsRef(uid).doc(txnId), {
        'isDeleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> syncTransactionUpsert(TransactionModel txn) async {
    final uid = _uid;
    if (uid == null) return;
    await _transactionsRef(uid).doc(txn.id).set(
      {
        ...txn.toFirestore(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> syncTransactionDelete(String txnId) async {
    final uid = _uid;
    if (uid == null) return;
    await _transactionsRef(uid).doc(txnId).update({
      'isDeleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

final firestoreSyncServiceProvider = Provider<FirestoreSyncService>((ref) {
  return FirestoreSyncService(ref);
});
