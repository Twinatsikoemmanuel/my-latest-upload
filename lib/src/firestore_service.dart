import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'debtmate_models.dart';

class FirestoreService {
  FirestoreService(this.db);

  final FirebaseFirestore db;

  CollectionReference<Map<String, dynamic>> get _users =>
      db.collection('users');
  CollectionReference<Map<String, dynamic>> get _businesses =>
      db.collection('businesses');
  CollectionReference<Map<String, dynamic>> get _customers =>
      db.collection('customers');
  CollectionReference<Map<String, dynamic>> get _debts =>
      db.collection('debts');
  CollectionReference<Map<String, dynamic>> get _payments =>
      db.collection('payments');
  CollectionReference<Map<String, dynamic>> get _followUps =>
      db.collection('followUps');
  CollectionReference<Map<String, dynamic>> get _reminders =>
      db.collection('reminders');

  Stream<BusinessUser?> watchProfile(String uid) => _users
      .doc(uid)
      .snapshots()
      .map((doc) => doc.exists ? BusinessUser.fromMap(uid, doc.data()!) : null);

  Future<void> createOwnerProfile({
    required User authUser,
    required String name,
    required String businessName,
  }) async {
    final batch = db.batch();
    final userRef = _users.doc(authUser.uid);
    final businessRef = _businesses.doc(authUser.uid);
    batch.set(userRef, {
      'name': name,
      'role': 'owner',
      'businessId': authUser.uid,
      'businessName': businessName,
      'email': authUser.email ?? '',
      'phone': authUser.phoneNumber ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(businessRef, {
      'ownerUid': authUser.uid,
      'name': businessName,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> createCustomerProfile({
    required User authUser,
    required String name,
  }) => _users.doc(authUser.uid).set({
    'name': name,
    'role': 'customer',
    'businessId': '',
    'email': authUser.email ?? '',
    'phone': authUser.phoneNumber ?? '',
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> addStaff({
    required BusinessUser owner,
    required String uid,
    required String name,
    required String email,
  }) async {
    await _users.doc(uid.trim()).update({
      'name': name.trim(),
      'role': 'staff',
      'businessId': owner.businessId,
      'businessName': owner.businessName,
      'email': email.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<CustomerRecord>> watchCustomers(String businessId) => _customers
      .where('businessId', isEqualTo: businessId)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.map(CustomerRecord.fromDoc).toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          ),
      );

  Stream<List<DebtRecord>> watchDebts({
    required String businessId,
    String? customerId,
  }) {
    final query = customerId == null
      ? _debts.where('businessId', isEqualTo: businessId)
      : _debts
          .where('businessId', isEqualTo: businessId)
          .where('customerId', isEqualTo: customerId);
    return query.snapshots().map(
      (snapshot) =>
          snapshot.docs.map(DebtRecord.fromDoc).toList()
            ..sort((a, b) => a.dueDate.compareTo(b.dueDate)),
    );
  }

  Stream<List<PaymentRecord>> watchPayments({
    required String businessId,
    String? customerId,
  }) {
    final query = customerId == null
      ? _payments.where('businessId', isEqualTo: businessId)
      : _payments
          .where('businessId', isEqualTo: businessId)
          .where('customerId', isEqualTo: customerId);
    return query.snapshots().map(
      (snapshot) =>
          snapshot.docs.map(PaymentRecord.fromDoc).toList()
            ..sort((a, b) => b.date.compareTo(a.date)),
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchFollowUps(
    String businessId,
  ) => _followUps.where('businessId', isEqualTo: businessId).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> watchReminders(
    String businessId,
  ) => _reminders.where('businessId', isEqualTo: businessId).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> watchNotifications(String uid) =>
      _users
          .doc(uid)
          .collection('notifications')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots();

  Future<void> markNotificationRead(String uid, String notificationId) =>
      _users.doc(uid).collection('notifications').doc(notificationId).update({
        'readAt': FieldValue.serverTimestamp(),
      });

  Future<void> markAllNotificationsRead(
    String uid,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> notifications,
  ) async {
    final batch = db.batch();
    for (final notification in notifications) {
      if (notification.data()['readAt'] == null) {
        batch.update(notification.reference, {
          'readAt': FieldValue.serverTimestamp(),
        });
      }
    }
    await batch.commit();
  }

  Future<void> savePushToken({
    required String uid,
    required String token,
  }) {
    final tokenId = base64Url.encode(utf8.encode(token)).replaceAll('=', '');
    final device = _users.doc(uid).collection('devices').doc(tokenId);
    return device.set({
      'token': token,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> saveCustomer({
    String? id,
    required String businessId,
    required String name,
    required String phone,
    required String email,
    required String address,
    required String notes,
    required String portalUserId,
    required String actorUid,
  }) async {
    final ref = id == null ? _customers.doc() : _customers.doc(id);
    final data = <String, dynamic>{
      'businessId': businessId,
      'name': name.trim(),
      'phone': phone.trim(),
      'email': email.trim(),
      'address': address.trim(),
      'notes': notes.trim(),
      'portalUserId': portalUserId.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (id == null) {
      data['createdAt'] = FieldValue.serverTimestamp();
      data['createdBy'] = actorUid;
      await ref.set(data);
    } else {
      await ref.update(data);
    }
    if (portalUserId.trim().isNotEmpty) {
      final userRef = _users.doc(portalUserId.trim());
      await userRef.update({
        'role': 'customer',
        'businessId': businessId,
        'customerId': ref.id,
        'businessName':
            (await _businesses.doc(businessId).get()).data()?['name'] ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> createDebt({
    required String businessId,
    required String actorUid,
    required CustomerRecord customer,
    required String itemDescription,
    required double quantity,
    required double totalAmount,
    required double initialDeposit,
    required DateTime transactionDate,
    required DateTime dueDate,
    required String terms,
    required String notes,
  }) async {
    if (totalAmount <= 0 ||
        initialDeposit < 0 ||
        initialDeposit > totalAmount) {
      throw ArgumentError(
        'Enter a positive total and a deposit no greater than the total.',
      );
    }
    final debtRef = _debts.doc();
    final batch = db.batch();
    final balance = totalAmount - initialDeposit;
    batch.set(debtRef, {
      'businessId': businessId,
      'customerId': customer.id,
      'customerName': customer.name,
      'itemDescription': itemDescription.trim(),
      'quantity': quantity,
      'totalAmount': totalAmount,
      'amountPaid': initialDeposit,
      'balance': balance,
      'transactionDate': Timestamp.fromDate(transactionDate),
      'dueDate': Timestamp.fromDate(dueDate),
      'terms': terms.trim(),
      'notes': notes.trim(),
      'status': balance <= 0
          ? 'paid'
          : initialDeposit > 0
          ? 'partial'
          : 'open',
      'createdBy': actorUid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (initialDeposit > 0) {
      final paymentRef = _payments.doc();
      batch.set(paymentRef, {
        'businessId': businessId,
        'debtId': debtRef.id,
        'customerId': customer.id,
        'customerName': customer.name,
        'amount': initialDeposit,
        'method': 'Initial deposit',
        'reference': '',
        'notes': 'Recorded with the credit transaction',
        'date': Timestamp.fromDate(transactionDate),
        'createdBy': actorUid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> recordPayment({
    required String debtId,
    required String actorUid,
    required double amount,
    required String method,
    required String reference,
    required String notes,
    required DateTime date,
  }) async {
    if (amount <= 0) throw ArgumentError('Payment must be greater than zero.');
    final debtRef = _debts.doc(debtId);
    final paymentRef = _payments.doc();
    await db.runTransaction((transaction) async {
      final snapshot = await transaction.get(debtRef);
      if (!snapshot.exists) throw StateError('This debt no longer exists.');
      final data = snapshot.data()!;
      final total = numberValue(data['totalAmount']);
      final paid = numberValue(data['amountPaid']);
      final balance = (total - paid).clamp(0, total).toDouble();
      if (amount > balance + 0.005) {
        throw ArgumentError('Payment exceeds the remaining balance.');
      }
      final newPaid = paid + amount;
      final newBalance = (total - newPaid).clamp(0, total).toDouble();
      final dueDate = dateValue(data['dueDate']);
      final now = DateTime.now();
      final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
      final today = DateTime(now.year, now.month, now.day);
      final status = newBalance <= 0
          ? 'paid'
          : dueDay.isBefore(today)
          ? 'overdue'
          : 'partial';
      transaction.update(debtRef, {
        'amountPaid': newPaid,
        'balance': newBalance,
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(paymentRef, {
        'businessId': data['businessId'],
        'debtId': debtId,
        'customerId': data['customerId'],
        'customerName': data['customerName'],
        'amount': amount,
        'method': method,
        'reference': reference.trim(),
        'notes': notes.trim(),
        'date': Timestamp.fromDate(date),
        'createdBy': actorUid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> recordFollowUp({
    required String businessId,
    required String actorUid,
    required DebtRecord debt,
    required String outcome,
    required String notes,
    required DateTime? promisedDate,
    required double? promisedAmount,
    required DateTime? nextFollowUpAt,
  }) => _followUps.add({
    'businessId': businessId,
    'debtId': debt.id,
    'customerId': debt.customerId,
    'customerName': debt.customerName,
    'outcome': outcome,
    'notes': notes.trim(),
    'promisedDate': promisedDate == null
        ? null
        : Timestamp.fromDate(promisedDate),
    'promisedAmount': promisedAmount,
    'nextFollowUpAt': nextFollowUpAt == null
        ? null
        : Timestamp.fromDate(nextFollowUpAt),
    'createdBy': actorUid,
    'createdAt': FieldValue.serverTimestamp(),
  });

  Future<void> generateReminderSuggestions({
    required String businessId,
    required String actorUid,
  }) async {
    final debtSnapshot = await _debts
        .where('businessId', isEqualTo: businessId)
        .get();
    final reminderSnapshot = await _reminders
        .where('businessId', isEqualTo: businessId)
        .get();
    final existingKeys = reminderSnapshot.docs
        .map((doc) => doc.data()['reminderKey'])
        .whereType<String>()
        .toSet();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final batch = db.batch();
    var count = 0;
    for (final doc in debtSnapshot.docs) {
      final data = doc.data();
      final balance = numberValue(data['balance']);
      final dueDate = dateValue(data['dueDate']);
      if (balance <= 0 || dueDate.isAfter(today.add(const Duration(days: 3)))) {
        continue;
      }
      final overdue = dueDate.isBefore(today);
      final dayTag = overdue
          ? 'overdue-${today.year}-${today.month}-${today.day}'
          : 'due-${dueDate.year}-${dueDate.month}-${dueDate.day}';
      final key = '${doc.id}-$dayTag';
      if (existingKeys.contains(key)) continue;
      final reminderRef = _reminders.doc(key);
      batch.set(reminderRef, {
        'businessId': businessId,
        'debtId': doc.id,
        'customerId': data['customerId'],
        'customerName': data['customerName'],
        'phone': '',
        'email': '',
        'channel': 'in-app',
        'status': 'ready',
        'reminderKey': key,
        'message':
            'A balance of ${balance.toStringAsFixed(0)} is ${overdue ? 'overdue' : 'due soon'} for ${data['customerName']}.',
        'createdBy': actorUid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      count++;
    }
    if (count > 0) await batch.commit();
  }

  Future<void> markReminderComposed(String reminderId, String channel) =>
      _reminders.doc(reminderId).update({
        'status': 'composed',
        'channel': channel,
        'composedAt': FieldValue.serverTimestamp(),
      });

  Future<void> recordReminderAction({
    required String businessId,
    required String actorUid,
    required DebtRecord debt,
    required String channel,
    required String phone,
    required String email,
    required String message,
  }) => _reminders.add({
    'businessId': businessId,
    'debtId': debt.id,
    'customerId': debt.customerId,
    'customerName': debt.customerName,
    'phone': phone,
    'email': email,
    'channel': channel,
    'status': 'composer_opened',
    'message': message,
    'createdBy': actorUid,
    'createdAt': FieldValue.serverTimestamp(),
    'composedAt': FieldValue.serverTimestamp(),
  });
}
