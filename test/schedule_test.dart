import 'package:flutter_test/flutter_test.dart';
import 'package:installment_tracker/logic/schedule.dart';

void main() {
  group('generateSchedule', () {
    test('spec example: 80,000 total, 20,000 advance, 5,000 monthly', () {
      final s = generateSchedule(
        total: 80000,
        advance: 20000,
        installmentAmount: 5000,
        firstDue: DateTime(2026, 10, 10),
      );
      expect(s.length, 12);
      expect(s.first.dueDate, DateTime(2026, 10, 10));
      expect(s[1].dueDate, DateTime(2026, 11, 10));
      expect(s.last.dueDate, DateTime(2027, 9, 10));
      expect(s.fold<int>(0, (a, i) => a + i.amount), 60000);
      expect(s.every((i) => i.amount == 5000), isTrue);
    });

    test('last installment absorbs the remainder', () {
      final s = generateSchedule(
          total: 50000, advance: 3000, installmentAmount: 5000, firstDue: DateTime(2026, 1, 1));
      expect(s.length, 10); // 47,000 / 5,000 -> 9 x 5,000 + 2,000
      expect(s.last.amount, 2000);
      expect(s.fold<int>(0, (a, i) => a + i.amount), 47000);
    });

    test('month-end dates clamp instead of overflowing', () {
      final s = generateSchedule(
          total: 4000, advance: 0, installmentAmount: 1000, firstDue: DateTime(2027, 1, 31));
      expect(s.map((i) => i.dueDate).toList(), [
        DateTime(2027, 1, 31),
        DateTime(2027, 2, 28),
        DateTime(2027, 3, 31),
        DateTime(2027, 4, 30),
      ]);
    });

    test('weekly, bi-weekly and custom frequencies', () {
      final first = DateTime(2026, 11, 1);
      DateTime second(Frequency f) => generateSchedule(
              total: 2000,
              advance: 0,
              installmentAmount: 1000,
              firstDue: first,
              frequency: f,
              customDays: 10)[1]
          .dueDate;
      expect(second(Frequency.weekly), DateTime(2026, 11, 8));
      expect(second(Frequency.biweekly), DateTime(2026, 11, 15));
      expect(second(Frequency.custom), DateTime(2026, 11, 11));
    });

    test('manual count that does not fit is rejected', () {
      expect(
          () => generateSchedule(
              total: 10000, advance: 0, installmentAmount: 5000, count: 3, firstDue: DateTime(2026)),
          throwsA(isA<PlanError>()));
    });

    test('advance larger than total is rejected; full advance -> no schedule', () {
      expect(
          () => generateSchedule(
              total: 1000, advance: 2000, installmentAmount: 100, firstDue: DateTime(2026)),
          throwsA(isA<PlanError>()));
      expect(
          generateSchedule(total: 1000, advance: 1000, installmentAmount: 100, firstDue: DateTime(2026)),
          isEmpty);
    });
  });

  group('computeSale (spec section 9 scenarios)', () {
    // 80,000 phone, 20,000 advance, 12 x 5,000 starting 10 Oct 2026.
    final sched = generateSchedule(
        total: 80000, advance: 20000, installmentAmount: 5000, firstDue: DateTime(2026, 10, 10));
    final insts = [
      for (final s in sched)
        InstallmentInput(id: s.number, number: s.number, dueDate: s.dueDate, amount: s.amount)
    ];
    final advance =
        PaymentInput(id: 1, amount: 20000, date: DateTime(2026, 9, 10), isAdvance: true);

    test('fresh sale: 25% paid, next due is installment 1', () {
      final c = computeSale(
          total: 80000, installments: insts, payments: [advance], today: DateTime(2026, 9, 10));
      expect(c.totalPaid, 20000);
      expect(c.remaining, 60000);
      expect(c.progress, 0.25);
      expect(c.nextDue!.number, 1);
      expect(c.status, SaleStatus.active);
    });

    test('Scenario 1: pay 2, skip 3rd, pay 4th double', () {
      final skipped = [
        for (final i in insts)
          i.number == 3
              ? InstallmentInput(
                  id: i.id, number: i.number, dueDate: i.dueDate, amount: i.amount, skipped: true)
              : i
      ];
      final c = computeSale(
        total: 80000,
        installments: skipped,
        payments: [
          advance,
          PaymentInput(id: 2, installmentId: 1, amount: 5000, date: DateTime(2026, 10, 10)),
          PaymentInput(id: 3, installmentId: 2, amount: 5000, date: DateTime(2026, 11, 10)),
          PaymentInput(
              id: 4, installmentId: 4, amount: 10000, date: DateTime(2027, 1, 10), applyExtraToNext: true),
        ],
        today: DateTime(2027, 1, 11),
      );
      final st = {for (final i in c.installments) i.number: i.status};
      expect(st[1], InstStatus.paid);
      expect(st[2], InstStatus.paid);
      expect(st[3], InstStatus.skipped);
      expect(st[4], InstStatus.paid);
      expect(st[5], InstStatus.paid); // the double payment covered the next one
      expect(c.totalPaid, 40000);
      expect(c.remaining, 40000); // skipped 5,000 is still owed
      expect(c.nextDue!.number, 6);
      expect(c.overdue, isEmpty); // skipped is grey, not red
      expect(c.status, SaleStatus.active);
    });

    test('Scenario 2: partial payment 3,000 of 5,000 leaves 2,000 due', () {
      final c = computeSale(
        total: 80000,
        installments: insts,
        payments: [
          advance,
          PaymentInput(id: 2, installmentId: 1, amount: 3000, date: DateTime(2026, 10, 10)),
        ],
        today: DateTime(2026, 10, 10),
      );
      final i1 = c.installments.first;
      expect(i1.status, InstStatus.partial);
      expect(i1.remaining, 2000);
      expect(c.nextDue!.number, 1);
      expect(c.remaining, 57000);
    });

    test('Scenario 3: paying early marks Paid, next due moves to the following month', () {
      final c = computeSale(
        total: 80000,
        installments: insts,
        payments: [
          advance,
          PaymentInput(id: 2, installmentId: 1, amount: 5000, date: DateTime(2026, 10, 10)),
          PaymentInput(id: 3, installmentId: 2, amount: 5000, date: DateTime(2026, 11, 5)),
        ],
        today: DateTime(2026, 11, 5),
      );
      expect(c.installments[1].status, InstStatus.paid);
      expect(c.nextDue!.dueDate, DateTime(2026, 12, 10));
    });

    test('Scenario 4: editing a payment amount recalculates every total', () {
      List<PaymentInput> pays(int amt) => [
            advance,
            PaymentInput(id: 2, installmentId: 1, amount: amt, date: DateTime(2026, 10, 10)),
          ];
      final before = computeSale(
          total: 80000, installments: insts, payments: pays(5000), today: DateTime(2026, 10, 11));
      final after = computeSale(
          total: 80000, installments: insts, payments: pays(4000), today: DateTime(2026, 10, 11));
      expect(before.totalPaid, 25000);
      expect(after.totalPaid, 24000);
      expect(after.remaining, 56000);
      expect(after.installments.first.status, InstStatus.partial);
      expect(after.status, SaleStatus.overdue); // 1,000 still open past due date
    });

    test('unpaid installment past due becomes Overdue with days late', () {
      final c = computeSale(
          total: 80000, installments: insts, payments: [advance], today: DateTime(2026, 10, 22));
      expect(c.installments.first.status, InstStatus.overdue);
      expect(c.installments.first.daysLate(DateTime(2026, 10, 22)), 12);
      expect(c.status, SaleStatus.overdue);
      expect(c.overdue.length, 1);
    });

    test('extra kept as advance becomes sale credit, not next installment', () {
      final c = computeSale(
        total: 80000,
        installments: insts,
        payments: [
          advance,
          PaymentInput(
              id: 2, installmentId: 1, amount: 7000, date: DateTime(2026, 10, 10), applyExtraToNext: false),
        ],
        today: DateTime(2026, 10, 10),
      );
      expect(c.installments[0].status, InstStatus.paid);
      expect(c.installments[1].paid, 0);
      expect(c.credit, 2000);
      expect(c.totalPaid, 27000);
      expect(c.remaining, 53000);
    });

    test('payment without an installment fills the oldest open one first', () {
      final c = computeSale(
        total: 80000,
        installments: insts,
        payments: [advance, PaymentInput(id: 2, amount: 7500, date: DateTime(2026, 11, 20))],
        today: DateTime(2026, 11, 20),
      );
      expect(c.installments[0].status, InstStatus.paid);
      expect(c.installments[1].status, InstStatus.partial);
      expect(c.installments[1].remaining, 2500);
    });

    test('everything paid -> Completed; cancelled overrides', () {
      final c = computeSale(
        total: 80000,
        installments: insts,
        payments: [advance, PaymentInput(id: 2, amount: 60000, date: DateTime(2026, 10, 1))],
        today: DateTime(2026, 10, 1),
      );
      expect(c.status, SaleStatus.completed);
      expect(c.remaining, 0);
      expect(c.nextDue, isNull);
      final x = computeSale(
          total: 80000, installments: insts, payments: [advance], today: DateTime(2027), cancelled: true);
      expect(x.status, SaleStatus.cancelled);
    });
  });
}
