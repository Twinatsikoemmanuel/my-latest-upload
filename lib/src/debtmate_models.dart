import 'package:cloud_firestore/cloud_firestore.dart';

DateTime dateValue(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return DateTime.fromMillisecondsSinceEpoch(0);
}

double numberValue(Object? value) => (value as num?)?.toDouble() ?? 0;

class BusinessUser {
  const BusinessUser({
    required this.uid,
    required this.name,
    required this.role,
    required this.businessId,
    this.businessName = '',
    this.customerId,
    this.email = '',
    this.phone = '',
  });

  final String uid;
  final String name;
  final String role;
  final String businessId;
  final String businessName;
  final String? customerId;
  final String email;
  final String phone;

  bool get isCustomer => role == 'customer';
  bool get isOwner => role == 'owner';

  factory BusinessUser.fromMap(String uid, Map<String, dynamic> map) =>
      BusinessUser(
        uid: uid,
        name: map['name'] as String? ?? 'User',
        role: map['role'] as String? ?? 'customer',
        businessId: map['businessId'] as String? ?? '',
        businessName: map['businessName'] as String? ?? '',
        customerId: map['customerId'] as String?,
        email: map['email'] as String? ?? '',
        phone: map['phone'] as String? ?? '',
      );
}

class CustomerRecord {
  const CustomerRecord({
    required this.id,
    required this.name,
    required this.phone,
    this.email = '',
    this.address = '',
    this.notes = '',
    this.portalUserId = '',
  });

  final String id;
  final String name;
  final String phone;
  final String email;
  final String address;
  final String notes;
  final String portalUserId;

  factory CustomerRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? <String, dynamic>{};
    return CustomerRecord(
      id: doc.id,
      name: map['name'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      email: map['email'] as String? ?? '',
      address: map['address'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
      portalUserId: map['portalUserId'] as String? ?? '',
    );
  }
}

class DebtRecord {
  const DebtRecord({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.itemDescription,
    required this.quantity,
    required this.totalAmount,
    required this.amountPaid,
    required this.transactionDate,
    required this.dueDate,
    this.terms = '',
    this.notes = '',
  });

  final String id;
  final String customerId;
  final String customerName;
  final String itemDescription;
  final double quantity;
  final double totalAmount;
  final double amountPaid;
  final DateTime transactionDate;
  final DateTime dueDate;
  final String terms;
  final String notes;

  double get balance => (totalAmount - amountPaid).clamp(0, totalAmount);
  bool get isPaid => balance <= 0.005;
  DateTime get dueDay => DateTime(dueDate.year, dueDate.month, dueDate.day);
  DateTime get today {
    final date = DateTime.now();
    return DateTime(date.year, date.month, date.day);
  }

  bool get isOverdue => !isPaid && dueDay.isBefore(today);
  int get daysOverdue => isOverdue ? today.difference(dueDay).inDays : 0;
  String get status => isPaid
      ? 'Paid'
      : isOverdue
      ? 'Overdue'
      : amountPaid > 0
      ? 'Partial'
      : 'Open';

  factory DebtRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? <String, dynamic>{};
    return DebtRecord(
      id: doc.id,
      customerId: map['customerId'] as String? ?? '',
      customerName: map['customerName'] as String? ?? '',
      itemDescription: map['itemDescription'] as String? ?? '',
      quantity: numberValue(map['quantity']),
      totalAmount: numberValue(map['totalAmount']),
      amountPaid: numberValue(map['amountPaid']),
      transactionDate: dateValue(map['transactionDate']),
      dueDate: dateValue(map['dueDate']),
      terms: map['terms'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
    );
  }
}

class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.debtId,
    required this.customerId,
    required this.customerName,
    required this.amount,
    required this.method,
    required this.date,
    this.reference = '',
    this.notes = '',
  });

  final String id;
  final String debtId;
  final String customerId;
  final String customerName;
  final double amount;
  final String method;
  final DateTime date;
  final String reference;
  final String notes;

  factory PaymentRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? <String, dynamic>{};
    return PaymentRecord(
      id: doc.id,
      debtId: map['debtId'] as String? ?? '',
      customerId: map['customerId'] as String? ?? '',
      customerName: map['customerName'] as String? ?? '',
      amount: numberValue(map['amount']),
      method: map['method'] as String? ?? '',
      date: dateValue(map['date']),
      reference: map['reference'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
    );
  }
}

String riskCategory(Iterable<DebtRecord> debts) {
  final records = debts.toList();
  final overdue = records
      .where((debt) => debt.isOverdue && debt.balance > 0)
      .toList();
  if (overdue.any((debt) => debt.daysOverdue >= 30) || overdue.length >= 3) {
    return 'High';
  }
  if (overdue.isNotEmpty) return 'Moderate';
  return 'Low';
}
