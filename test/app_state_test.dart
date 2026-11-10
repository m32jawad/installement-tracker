import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:installment_tracker/core/format.dart';
import 'package:installment_tracker/data/app_state.dart';
import 'package:installment_tracker/data/backup.dart';
import 'package:installment_tracker/data/database.dart';
import 'package:installment_tracker/data/models.dart';
import 'package:installment_tracker/data/photo_store.dart';
import 'package:installment_tracker/data/sample_data.dart';
import 'package:installment_tracker/logic/schedule.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Repository tests against a real SQLite database (sqflite_common_ffi).
void main() {
  sqfliteFfiInit();
  late Directory tmp;
  late AppState app;
  final today = DateTime(2026, 11, 10);

  Future<AppState> open(String dbPath) async {
    final db = await openAppDatabase(dbPath, factory: databaseFactoryFfi);
    final a = AppState(db, PhotoStore(Directory('${tmp.path}/photos')), clock: () => today);
    await a.load();
    return a;
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('it_test');
    app = await open('${tmp.path}/test.db');
  });

  tearDown(() async {
    await app.db.close();
    await tmp.delete(recursive: true);
  });

  Future<(int, int, int)> seedSpecExample() async {
    final c = await app.saveCustomer(Customer(name: 'Customer A', phone: '0300-1234567'));
    final i = await app.saveItem(Item(name: 'Mobile Phone ABC', purchaseCost: 65000, sellingPrice: 80000));
    final s = await app.createSale(Sale(
      customerId: c,
      itemId: i,
      saleDate: DateTime(2026, 9, 10),
      totalPrice: 80000,
      advanceAmount: 20000,
      monthlyAmount: 5000,
      totalInstallments: 12,
      firstDueDate: DateTime(2026, 10, 10),
    ));
    return (c, i, s);
  }

  Installment inst(int saleId, int n) => app.installmentsBySale[saleId]!.firstWhere((x) => x.number == n);

  Future<int> pay(int saleId, int n, int amount, DateTime d, {bool extraToNext = true}) {
    final s = app.sale(saleId)!;
    return app.addPayment(Payment(
      saleId: saleId,
      installmentId: inst(saleId, n).id,
      customerId: s.customerId,
      amount: amount,
      paymentDate: d,
      method: 'Cash',
      applyExtraToNext: extraToNext,
    ));
  }

  test('creating a sale builds the schedule, records the advance and marks the item sold', () async {
    final (c, i, s) = await seedSpecExample();
    expect(app.installmentsBySale[s]!.length, 12);
    expect(app.installmentsBySale[s]!.last.dueDate, DateTime(2027, 9, 10));
    final advance = app.paymentsForSale(s).single;
    expect(advance.isAdvance, isTrue);
    expect(advance.amount, 20000);
    expect(app.item(i)!.status, 'sold');
    expect(app.comp[s]!.remaining, 60000);
    // 10 Oct installment is a month overdue on 10 Nov, 10 Nov is due today.
    expect(app.overdue().length, 1);
    expect(app.dueToday().single.inst.number, 2);
    expect(app.customerSummary(c).status, CustomerStatus.late);
    expect(app.totalProfit(), 15000);
  });

  test('Scenario 1 persisted: skip + double payment, cached columns written back', () async {
    final (_, _, s) = await seedSpecExample();
    await pay(s, 1, 5000, DateTime(2026, 10, 10));
    await pay(s, 2, 5000, DateTime(2026, 11, 10));
    await app.setSkipped(inst(s, 3).id, true, reason: 'Out of city');
    await pay(s, 4, 10000, DateTime(2026, 11, 10));
    final st = {for (final i in app.comp[s]!.installments) i.number: i.status};
    expect(st[3], InstStatus.skipped);
    expect(st[4], InstStatus.paid);
    expect(st[5], InstStatus.paid);
    expect(app.comp[s]!.remaining, 40000);
    final row = (await app.db.query('installments', where: 'id = ?', whereArgs: [inst(s, 5).id])).single;
    expect(row['status'], 'paid');
    expect(row['paid_amount'], 5000);
    expect(app.installment(inst(s, 3).id)!.skipReason, 'Out of city');
    // Un-skip brings it back as collectable.
    await app.setSkipped(inst(s, 3).id, false);
    expect(app.comp[s]!.nextDue!.number, 3);
  });

  test('Scenario 4: editing a payment updates every total and keeps an audit log', () async {
    final (c, _, s) = await seedSpecExample();
    final pid = await pay(s, 1, 5000, DateTime(2026, 10, 10));
    final before = app.payments.firstWhere((p) => p.id == pid);
    expect(app.customerSummary(c).totalPaid, 25000);

    await app.editPayment(
        before,
        Payment(
          id: pid,
          saleId: s,
          installmentId: before.installmentId,
          customerId: c,
          amount: 3000,
          paymentDate: before.paymentDate,
          method: 'JazzCash',
          createdAt: before.createdAt,
        ));
    final after = app.payments.firstWhere((p) => p.id == pid);
    expect(after.editedAt, isNotNull);
    expect(app.editsByPayment[pid]!.single.changes, contains('"amount":[5000,3000]'));
    expect(app.customerSummary(c).totalPaid, 23000);
    expect(app.comp[s]!.installments.first.status, InstStatus.partial);
    expect(app.totalOutstanding(), 57000);

    // Editing the advance keeps sales.advance_amount in step.
    final adv = app.paymentsForSale(s).firstWhere((p) => p.isAdvance);
    await app.editPayment(
        adv,
        Payment(
          id: adv.id,
          saleId: s,
          customerId: c,
          amount: 25000,
          paymentDate: adv.paymentDate,
          method: adv.method,
          isAdvance: true,
          createdAt: adv.createdAt,
        ));
    expect(app.sale(s)!.advanceAmount, 25000);
    expect(app.comp[s]!.totalPaid, 28000);
  });

  test('Scenario 5: a cheque photo appears under the sale security documents', () async {
    final (_, _, s) = await seedSpecExample();
    final src = File('${tmp.path}/cheque.jpg')..writeAsBytesSync([1, 2, 3]);
    final name = await app.photos.importFile(src.path);
    await app.addSecurityDoc(
        SecurityDoc(saleId: s, type: 'cheque', photo: name, chequeNumber: '001234', bankName: 'HBL'));
    final docs = app.docsBySale[s]!;
    expect(docs.single.typeLabel, 'Cheque');
    expect(docs.single.chequeNumber, '001234');
    expect(app.photos.file(name).existsSync(), isTrue);
    await app.deleteSecurityDoc(docs.single);
    expect(app.docsBySale[s], isNull);
    expect(app.photos.file(name).existsSync(), isFalse);
  });

  test('plan can be edited only before installment payments; delete frees the item', () async {
    final (_, i, s) = await seedSpecExample();
    expect(app.canEditPlan(s), isTrue);
    final old = app.sale(s)!;
    await app.updateSalePlan(Sale(
      id: s,
      customerId: old.customerId,
      itemId: old.itemId,
      saleDate: old.saleDate,
      totalPrice: 80000,
      advanceAmount: 30000,
      monthlyAmount: 10000,
      totalInstallments: 5,
      firstDueDate: old.firstDueDate,
      createdAt: old.createdAt,
    ));
    expect(app.installmentsBySale[s]!.length, 5);
    expect(app.paymentsForSale(s).single.amount, 30000);

    await pay(s, 1, 10000, DateTime(2026, 10, 10));
    expect(app.canEditPlan(s), isFalse);
    expect(() => app.updateSalePlan(app.sale(s)!), throwsA(isA<PlanError>()));

    await app.deleteSale(s);
    expect(app.sale(s), isNull);
    expect(app.payments, isEmpty);
    expect(app.item(i)!.status, 'available');
  });

  test('partial payment then delete payment restores the installment', () async {
    final (_, _, s) = await seedSpecExample();
    await pay(s, 1, 3000, DateTime(2026, 10, 12));
    expect(app.comp[s]!.installments.first.remaining, 2000);
    final p = app.paymentsForSale(s).firstWhere((p) => !p.isAdvance);
    await app.deletePayment(p);
    expect(app.comp[s]!.installments.first.paid, 0);
  });

  test('cancelled sales drop out of dues and outstanding', () async {
    final (_, _, s) = await seedSpecExample();
    expect(app.totalOutstanding(), 60000);
    await app.setSaleCancelled(s, true);
    expect(app.totalOutstanding(), 0);
    expect(app.openDue(), isEmpty);
    expect(app.comp[s]!.status, SaleStatus.cancelled);
  });

  test('PIN is stored hashed and checked', () async {
    await app.setPin('4321');
    expect(app.hasPin, isTrue);
    expect(app.setting('pin_hash'), isNot(contains('4321')));
    expect(app.checkPin('4321'), isTrue);
    expect(app.checkPin('1234'), isFalse);
    await app.setPin(null);
    expect(app.hasPin, isFalse);
  });

  test('sample data loads and fills every dashboard section', () async {
    await loadSampleData(app);
    expect(app.customers.length, 5);
    expect(app.sales.length, 5);
    expect(app.dueToday(), isNotEmpty);
    expect(app.overdue(), isNotEmpty);
    expect(app.skippedOpen(), isNotEmpty);
    expect(app.sales.where((s) => app.comp[s.id]!.status == SaleStatus.completed), isNotEmpty);
    expect(app.collectedInMonth(today), greaterThanOrEqualTo(0));
  });

  test('backup zip round-trips database and photos; junk files are rejected', () async {
    await seedSpecExample();
    final src = File('${tmp.path}/cnic.jpg')..writeAsBytesSync(List.filled(64, 7));
    final photo = await app.photos.importFile(src.path);
    final s = app.sales.first.id!;
    await app.addSecurityDoc(SecurityDoc(saleId: s, type: 'cnic_front', photo: photo));

    final out = await Directory('${tmp.path}/out').create();
    final service = BackupService(app.db.path, app.photos.dir);
    final zip = await service.createBackup(app.db, out);

    await app.wipeAll();
    expect(app.sales, isEmpty);
    expect(app.photos.file(photo).existsSync(), isFalse);

    await app.db.close();
    await service.restoreBackup(await zip.readAsBytes());
    app = await open('${tmp.path}/test.db');
    expect(app.sales.length, 1);
    expect(app.installmentsBySale[app.sales.first.id]!.length, 12);
    expect(app.docsBySale.values.single.single.photo, photo);
    expect(app.photos.file(photo).existsSync(), isTrue);

    expect(() => service.restoreBackup([1, 2, 3, 4]), throwsA(anything));
  });

  group('format helpers', () {
    test('WhatsApp numbers', () {
      expect(toWhatsAppNumber('0300-1234567'), '923001234567');
      expect(toWhatsAppNumber('+92 300 1234567'), '923001234567');
      expect(toWhatsAppNumber('3001234567'), '923001234567');
    });
    test('search matches names and digits ignoring dashes', () {
      expect(matchesQuery('ali', ['Ali Raza']), isTrue);
      expect(matchesQuery('03001234', ['0300-1234567']), isTrue);
      expect(matchesQuery('3520212345671', ['35202-1234567-1']), isTrue);
      expect(matchesQuery('xyz', ['Ali Raza', '0300']), isFalse);
    });
    test('amount parsing and reminder template', () {
      expect(parseAmount('5,000'), 5000);
      expect(parseAmount(''), isNull);
      final t = fillTemplate(defaultReminderTemplate,
          name: 'Customer A', amount: 'Rs. 5,000', item: 'iPhone', date: '10 Nov 2026', shop: 'Shop');
      expect(t, startsWith('Assalam-o-Alaikum Customer A, your installment of Rs. 5,000 for iPhone is due on 10 Nov 2026'));
    });
  });
}
