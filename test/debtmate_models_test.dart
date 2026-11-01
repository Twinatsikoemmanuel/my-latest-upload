import 'package:dabtmateapp/src/debtmate_models.dart';
import 'package:flutter_test/flutter_test.dart';

DebtRecord _debt({required DateTime dueDate, double amountPaid = 0}) =>
    DebtRecord(
      id: 'debt-1',
      customerId: 'customer-1',
      customerName: 'Test customer',
      itemDescription: 'Goods',
      quantity: 1,
      totalAmount: 100000,
      amountPaid: amountPaid,
      transactionDate: DateTime(2026, 1, 1),
      dueDate: dueDate,
    );

void main() {
  group('DebtRecord', () {
    test('calculates remaining balance and payment status', () {
      final today = DateTime.now();
      final partial = _debt(
        dueDate: today.add(const Duration(days: 2)),
        amountPaid: 25000,
      );
      final paid = _debt(
        dueDate: today.subtract(const Duration(days: 4)),
        amountPaid: 100000,
      );

      expect(partial.balance, 75000);
      expect(partial.status, 'Partial');
      expect(paid.balance, 0);
      expect(paid.status, 'Paid');
    });

    test('does not mark a record overdue on its due calendar day', () {
      final now = DateTime.now();
      final debt = _debt(dueDate: DateTime(now.year, now.month, now.day));

      expect(debt.isOverdue, isFalse);
      expect(debt.daysOverdue, 0);
    });
  });

  group('riskCategory', () {
    test('uses overdue history to assign low, moderate, and high risk', () {
      final today = DateTime.now();
      final overdue = _debt(dueDate: today.subtract(const Duration(days: 5)));
      final veryOverdue = _debt(
        dueDate: today.subtract(const Duration(days: 35)),
      );

      expect(
        riskCategory([_debt(dueDate: today.add(const Duration(days: 2)))]),
        'Low',
      );
      expect(riskCategory([overdue]), 'Moderate');
      expect(riskCategory([veryOverdue]), 'High');
      expect(riskCategory([overdue, overdue, overdue]), 'High');
    });
  });
}
