import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../core/app_log.dart';
import '../core/format.dart';
import '../logic/schedule.dart';
import 'models.dart';
import 'photo_store.dart';

/// One open (or historical) installment with everything a list row needs.
class DueEntry {
  final Sale sale;
  final Customer customer;
  final Item? item;
  final InstallmentState inst;
  DueEntry(this.sale, this.customer, this.item, this.inst);
  String get itemName => item?.name ?? 'Item';
}

enum CustomerStatus { good, late, skipped, completed, none }

String customerStatusLabel(CustomerStatus s) {
  switch (s) {
    case CustomerStatus.good:
      return 'Good';
    case CustomerStatus.late:
      return 'Late';
    case CustomerStatus.skipped:
      return 'Skipped';
    case CustomerStatus.completed:
      return 'Completed';
    case CustomerStatus.none:
      return 'No sales';
  }
}

class CustomerSummary {
  final int activeSales;
  final int totalPurchase;
  final int totalPaid;
  final int pending;
  final InstallmentState? nextDue;
  final CustomerStatus status;
  CustomerSummary(this.activeSales, this.totalPurchase, this.totalPaid,
      this.pending, this.nextDue, this.status);
}

const defaultPaymentMethods = [
  'Cash',
  'Bank Transfer',
  'JazzCash',
  'Easypaisa',
  'Cheque',
  'Other',
];

/// The single source of truth for the UI. Everything is loaded into memory
/// from SQLite (a shop's data is small) and every derived number is
/// recomputed after each change, so totals update everywhere at once.
class AppState extends ChangeNotifier {
  final Database db;
  final PhotoStore photos;
  final DateTime Function() clock;

  AppState(this.db, this.photos, {DateTime Function()? clock})
      : clock = clock ?? DateTime.now;

  List<Customer> customers = [];
  List<Item> items = [];
  List<Sale> sales = [];
  Map<int, List<Installment>> installmentsBySale = {};
  List<Payment> payments = [];
  Map<int, List<PaymentEdit>> editsByPayment = {};
  Map<int, List<SecurityDoc>> docsBySale = {};
  Map<int, List<SaleNote>> notesBySale = {};
  Map<String, String> settings = {};
  Map<int, SaleComputation> comp = {};

  final Map<int, Customer> _customerById = {};
  final Map<int, Item> _itemById = {};
  final Map<int, Sale> _saleById = {};

  DateTime get today => dateOnly(clock());

  Customer? customer(int id) => _customerById[id];
  Item? item(int? id) => id == null ? null : _itemById[id];
  Sale? sale(int id) => _saleById[id];

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  Future<void> load() async {
    final sw = Stopwatch()..start();
    customers = (await db.query('customers', orderBy: 'name COLLATE NOCASE'))
        .map(Customer.fromMap)
        .toList();
    items = (await db.query('items', orderBy: 'created_at DESC'))
        .map(Item.fromMap)
        .toList();
    sales = (await db.query('sales', orderBy: 'sale_date DESC, id DESC'))
        .map(Sale.fromMap)
        .toList();
    installmentsBySale = {};
    for (final m in await db.query('installments', orderBy: 'installment_number')) {
      final i = Installment.fromMap(m);
      installmentsBySale.putIfAbsent(i.saleId, () => []).add(i);
    }
    payments = (await db.query('payments', orderBy: 'payment_date DESC, id DESC'))
        .map(Payment.fromMap)
        .toList();
    editsByPayment = {};
    for (final m in await db.query('payment_edits', orderBy: 'edited_at DESC')) {
      final e = PaymentEdit.fromMap(m);
      editsByPayment.putIfAbsent(e.paymentId, () => []).add(e);
    }
    docsBySale = {};
    for (final m in await db.query('security_documents', orderBy: 'created_at')) {
      final d = SecurityDoc.fromMap(m);
      docsBySale.putIfAbsent(d.saleId, () => []).add(d);
    }
    notesBySale = {};
    for (final m in await db.query('sale_notes', orderBy: 'created_at DESC')) {
      final n = SaleNote.fromMap(m);
      notesBySale.putIfAbsent(n.saleId, () => []).add(n);
    }
    settings = {
      for (final m in await db.query('settings'))
        m['key'] as String: (m['value'] as String?) ?? ''
    };
    currencySymbol = currency;
    _index();
    _recompute();
    AppLog.info('Loaded ${customers.length} customers, ${sales.length} sales, '
        '${payments.length} payments in ${sw.elapsedMilliseconds}ms');
    notifyListeners();
  }

  void _index() {
    _customerById
      ..clear()
      ..addEntries(customers.map((c) => MapEntry(c.id!, c)));
    _itemById
      ..clear()
      ..addEntries(items.map((i) => MapEntry(i.id!, i)));
    _saleById
      ..clear()
      ..addEntries(sales.map((s) => MapEntry(s.id!, s)));
  }

  void _recompute() {
    final paysBySale = <int, List<PaymentInput>>{};
    for (final p in payments) {
      paysBySale.putIfAbsent(p.saleId, () => []).add(p.toInput());
    }
    final t = today;
    comp = {
      for (final s in sales)
        s.id!: computeSale(
          total: s.totalPrice,
          installments: (installmentsBySale[s.id] ?? const [])
              .map((i) => i.toInput())
              .toList(),
          payments: paysBySale[s.id] ?? const [],
          today: t,
          cancelled: s.cancelled,
        )
    };
  }

  /// Writes derived installment fields back to the table so the raw database
  /// (and .db backups) match the spec's data model.
  Future<void> _syncSaleCache(int saleId) async {
    final c = comp[saleId];
    final s = _saleById[saleId];
    if (c == null || s == null) return;
    final batch = db.batch();
    for (final st in c.installments) {
      batch.update(
        'installments',
        {
          'paid_amount': st.paid,
          'status': st.status.name,
          'paid_date': st.paidDate == null ? null : dbDate(st.paidDate!),
          'payment_method': st.method,
        },
        where: 'id = ?',
        whereArgs: [st.id],
      );
    }
    batch.update('sales', {'status': s.cancelled ? 'cancelled' : c.status.name},
        where: 'id = ?', whereArgs: [saleId]);
    await batch.commit(noResult: true);
  }

  Future<void> _reloadAndSync(Iterable<int> saleIds) async {
    await load();
    for (final id in saleIds) {
      await _syncSaleCache(id);
    }
  }

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  String setting(String key, [String fallback = '']) {
    final v = settings[key];
    return v == null || v.isEmpty ? fallback : v;
  }

  String get shopName => setting('shop_name', 'My Shop');
  String get ownerName => setting('owner_name');
  String get shopPhone => setting('shop_phone');
  String get shopAddress => setting('shop_address');
  String get currency => setting('currency', 'Rs.');
  String get themeMode => setting('theme', 'system');
  String get reminderTemplate => setting('wa_template', defaultReminderTemplate);
  int get defaultDueDay => int.tryParse(setting('default_due_day', '0')) ?? 0;
  int get reminderDaysBefore =>
      int.tryParse(setting('reminder_days_before', '1')) ?? 1;
  bool get onboarded => setting('onboarded') == '1';
  bool get hasPin => setting('pin_hash').isNotEmpty;
  bool get showProfit => setting('show_profit') == '1';

  List<String> get paymentMethods {
    final raw = settings['payment_methods'];
    if (raw == null || raw.isEmpty) return defaultPaymentMethods;
    try {
      final l = (jsonDecode(raw) as List).cast<String>();
      return l.isEmpty ? defaultPaymentMethods : l;
    } catch (_) {
      return defaultPaymentMethods;
    }
  }

  Future<void> setSetting(String key, String value) async {
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
    settings[key] = value;
    if (key == 'currency') currencySymbol = currency;
    notifyListeners();
  }

  Future<void> setSettings(Map<String, String> values) async {
    final b = db.batch();
    values.forEach((k, v) => b.insert('settings', {'key': k, 'value': v},
        conflictAlgorithm: ConflictAlgorithm.replace));
    await b.commit(noResult: true);
    settings.addAll(values);
    currencySymbol = currency;
    notifyListeners();
  }

  Future<void> setPaymentMethods(List<String> methods) =>
      setSetting('payment_methods', jsonEncode(methods));

  static String hashPin(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  Future<void> setPin(String? pin) async {
    if (pin == null || pin.isEmpty) {
      await setSettings({'pin_hash': '', 'pin_salt': ''});
      AppLog.info('PIN lock removed');
      return;
    }
    final salt = DateTime.now().microsecondsSinceEpoch.toString();
    await setSettings({'pin_hash': hashPin(pin, salt), 'pin_salt': salt});
    AppLog.info('PIN lock set');
  }

  bool checkPin(String pin) =>
      hasPin && hashPin(pin, setting('pin_salt')) == setting('pin_hash');

  // ---------------------------------------------------------------------------
  // Customers
  // ---------------------------------------------------------------------------

  Future<int> saveCustomer(Customer c) async {
    int id;
    if (c.id == null) {
      id = await db.insert('customers', c.toMap());
      AppLog.info('Customer added #$id');
    } else {
      id = c.id!;
      await db.update('customers', c.toMap(), where: 'id = ?', whereArgs: [id]);
      AppLog.info('Customer updated #$id');
    }
    await load();
    return id;
  }

  Future<void> deleteCustomer(int id) async {
    final saleIds = sales.where((s) => s.customerId == id).map((s) => s.id!).toList();
    await db.transaction((tx) async {
      for (final sid in saleIds) {
        await _releaseItemFor(tx, sid);
      }
      await tx.delete('customers', where: 'id = ?', whereArgs: [id]);
    });
    await photos.delete(customer(id)?.photo);
    AppLog.info('Customer deleted #$id with ${saleIds.length} sales');
    await load();
  }

  List<Sale> salesFor(int customerId) =>
      sales.where((s) => s.customerId == customerId).toList();

  CustomerSummary customerSummary(int customerId) {
    final ss = salesFor(customerId);
    int active = 0, purchase = 0, paid = 0, pending = 0;
    InstallmentState? next;
    bool late = false, skipped = false;
    for (final s in ss) {
      final c = comp[s.id]!;
      if (s.cancelled) continue;
      purchase += s.totalPrice;
      paid += c.totalPaid;
      pending += c.remaining;
      if (c.status != SaleStatus.completed) active++;
      final n = c.nextDue;
      if (n != null && (next == null || n.dueDate.isBefore(next.dueDate))) next = n;
      if (c.overdue.isNotEmpty) late = true;
      if (c.hasSkippedOpen) skipped = true;
    }
    CustomerStatus st;
    if (ss.isEmpty) {
      st = CustomerStatus.none;
    } else if (late) {
      st = CustomerStatus.late;
    } else if (skipped) {
      st = CustomerStatus.skipped;
    } else if (active == 0) {
      st = CustomerStatus.completed;
    } else {
      st = CustomerStatus.good;
    }
    return CustomerSummary(active, purchase, paid, pending, next, st);
  }

  // ---------------------------------------------------------------------------
  // Items
  // ---------------------------------------------------------------------------

  Future<int> saveItem(Item i) async {
    int id;
    if (i.id == null) {
      id = await db.insert('items', i.toMap());
      AppLog.info('Item added #$id');
    } else {
      id = i.id!;
      await db.update('items', i.toMap(), where: 'id = ?', whereArgs: [id]);
      AppLog.info('Item updated #$id');
    }
    await load();
    return id;
  }

  Future<void> deleteItem(int id) async {
    final it = item(id);
    await db.delete('items', where: 'id = ?', whereArgs: [id]);
    for (final ph in it?.photos ?? const <String>[]) {
      await photos.delete(ph);
    }
    AppLog.info('Item deleted #$id');
    await load();
  }

  List<Sale> salesForItem(int itemId) =>
      sales.where((s) => s.itemId == itemId).toList();

  // ---------------------------------------------------------------------------
  // Sales
  // ---------------------------------------------------------------------------

  /// Creates the sale, its full installment schedule, the advance payment and
  /// security documents in one transaction.
  Future<int> createSale(Sale s, {List<SecurityDoc> docs = const []}) async {
    final schedule = generateSchedule(
      total: s.totalPrice,
      advance: s.advanceAmount,
      installmentAmount: s.monthlyAmount,
      count: s.totalInstallments,
      firstDue: s.firstDueDate,
      frequency: s.frequency,
      customDays: s.customDays,
    );
    late int saleId;
    await db.transaction((tx) async {
      saleId = await tx.insert('sales', s.toMap());
      final now = nowStamp();
      for (final si in schedule) {
        await tx.insert('installments', {
          'sale_id': saleId,
          'installment_number': si.number,
          'due_date': dbDate(si.dueDate),
          'amount': si.amount,
          'created_at': now,
        });
      }
      if (s.advanceAmount > 0) {
        await tx.insert(
            'payments',
            Payment(
              saleId: saleId,
              customerId: s.customerId,
              amount: s.advanceAmount,
              paymentDate: s.saleDate,
              method: s.advanceMethod,
              isAdvance: true,
              note: 'Advance / down payment',
            ).toMap());
      }
      for (final d in docs) {
        final m = d.toMap()..['sale_id'] = saleId;
        await tx.insert('security_documents', m);
      }
      if (s.itemId != null) {
        await tx.update('items', {'status': 'sold'},
            where: 'id = ?', whereArgs: [s.itemId]);
      }
    });
    AppLog.info('Sale created #$saleId: total ${s.totalPrice}, advance '
        '${s.advanceAmount}, ${schedule.length} installments');
    await _reloadAndSync([saleId]);
    return saleId;
  }

  bool canEditPlan(int saleId) =>
      !payments.any((p) => p.saleId == saleId && !p.isAdvance);

  /// Replaces the plan of a sale that has no installment payments yet
  /// (regenerates the schedule and the advance payment).
  Future<void> updateSalePlan(Sale s) async {
    if (!canEditPlan(s.id!)) {
      throw PlanError('This sale already has installment payments. '
          'Edit or delete those payments first.');
    }
    final schedule = generateSchedule(
      total: s.totalPrice,
      advance: s.advanceAmount,
      installmentAmount: s.monthlyAmount,
      count: s.totalInstallments,
      firstDue: s.firstDueDate,
      frequency: s.frequency,
      customDays: s.customDays,
    );
    final old = sale(s.id!)!;
    await db.transaction((tx) async {
      await tx.update('sales', s.toMap(), where: 'id = ?', whereArgs: [s.id]);
      await tx.delete('installments', where: 'sale_id = ?', whereArgs: [s.id]);
      await tx.delete('payments',
          where: 'sale_id = ? AND is_advance = 1', whereArgs: [s.id]);
      final now = nowStamp();
      for (final si in schedule) {
        await tx.insert('installments', {
          'sale_id': s.id,
          'installment_number': si.number,
          'due_date': dbDate(si.dueDate),
          'amount': si.amount,
          'created_at': now,
        });
      }
      if (s.advanceAmount > 0) {
        await tx.insert(
            'payments',
            Payment(
              saleId: s.id!,
              customerId: s.customerId,
              amount: s.advanceAmount,
              paymentDate: s.saleDate,
              method: s.advanceMethod,
              isAdvance: true,
              note: 'Advance / down payment',
            ).toMap());
      }
      if (old.itemId != s.itemId) {
        if (old.itemId != null) {
          await tx.update('items', {'status': 'available'},
              where: 'id = ?', whereArgs: [old.itemId]);
        }
        if (s.itemId != null) {
          await tx.update('items', {'status': 'sold'},
              where: 'id = ?', whereArgs: [s.itemId]);
        }
      }
    });
    AppLog.info('Sale plan updated #${s.id}');
    await _reloadAndSync([s.id!]);
  }

  Future<void> updateSaleNotes(int saleId, String? notes) async {
    await db.update('sales', {'notes': notes},
        where: 'id = ?', whereArgs: [saleId]);
    await load();
  }

  Future<void> setSaleCancelled(int saleId, bool cancelled) async {
    await db.update('sales', {'status': cancelled ? 'cancelled' : 'active'},
        where: 'id = ?', whereArgs: [saleId]);
    AppLog.info('Sale #$saleId ${cancelled ? 'cancelled' : 're-activated'}');
    await _reloadAndSync([saleId]);
  }

  Future<void> _releaseItemFor(DatabaseExecutor tx, int saleId) async {
    final s = sale(saleId);
    if (s?.itemId != null) {
      await tx.update('items', {'status': 'available'},
          where: 'id = ?', whereArgs: [s!.itemId]);
    }
  }

  Future<void> deleteSale(int saleId) async {
    final docs = docsBySale[saleId] ?? const [];
    final receipts = payments
        .where((p) => p.saleId == saleId)
        .map((p) => p.receiptPhoto)
        .toList();
    await db.transaction((tx) async {
      await _releaseItemFor(tx, saleId);
      await tx.delete('sales', where: 'id = ?', whereArgs: [saleId]);
    });
    for (final d in docs) {
      await photos.delete(d.photo);
    }
    for (final r in receipts) {
      await photos.delete(r);
    }
    AppLog.info('Sale deleted #$saleId');
    await load();
  }

  Future<void> addSaleNote(int saleId, String note) async {
    await db.insert('sale_notes',
        {'sale_id': saleId, 'note': note, 'created_at': nowStamp()});
    await load();
  }

  Future<void> deleteSaleNote(int noteId) async {
    await db.delete('sale_notes', where: 'id = ?', whereArgs: [noteId]);
    await load();
  }

  // ---------------------------------------------------------------------------
  // Installments & payments
  // ---------------------------------------------------------------------------

  Future<void> setSkipped(int installmentId, bool skipped, {String? reason}) async {
    final row = await db.query('installments',
        columns: ['sale_id'], where: 'id = ?', whereArgs: [installmentId]);
    if (row.isEmpty) return;
    await db.update(
        'installments', {'skipped': skipped ? 1 : 0, 'skip_reason': skipped ? reason : null},
        where: 'id = ?', whereArgs: [installmentId]);
    AppLog.info('Installment #$installmentId ${skipped ? 'skipped' : 'un-skipped'}');
    await _reloadAndSync([row.first['sale_id'] as int]);
  }

  Installment? installment(int id) {
    for (final l in installmentsBySale.values) {
      for (final i in l) {
        if (i.id == id) return i;
      }
    }
    return null;
  }

  InstallmentState? installmentState(int saleId, int installmentId) {
    for (final st in comp[saleId]?.installments ?? const <InstallmentState>[]) {
      if (st.id == installmentId) return st;
    }
    return null;
  }

  Future<int> addPayment(Payment p) async {
    if (p.amount <= 0) throw ArgumentError('Amount must be more than 0');
    final id = await db.insert('payments', p.toMap());
    AppLog.info('Payment #$id: ${p.amount} via ${p.method} for sale #${p.saleId}'
        '${p.installmentId == null ? '' : ' installment #${p.installmentId}'}');
    await _reloadAndSync([p.saleId]);
    return id;
  }

  /// Saves an edited payment and records what changed (audit log).
  Future<void> editPayment(Payment old, Payment updated) async {
    final changes = <String, List<Object?>>{};
    void diff(String k, Object? a, Object? b) {
      if (a != b) changes[k] = [a, b];
    }

    diff('amount', old.amount, updated.amount);
    diff('date', dbDate(old.paymentDate), dbDate(updated.paymentDate));
    diff('method', old.method, updated.method);
    diff('note', old.note, updated.note);
    diff('transaction_id', old.transactionId, updated.transactionId);
    diff('bank_name', old.bankName, updated.bankName);
    diff('cheque_number', old.chequeNumber, updated.chequeNumber);
    diff('installment', old.installmentId, updated.installmentId);
    if (changes.isEmpty) return;
    final now = nowStamp();
    await db.transaction((tx) async {
      final m = updated.toMap()..['edited_at'] = now;
      await tx.update('payments', m, where: 'id = ?', whereArgs: [old.id]);
      await tx.insert('payment_edits',
          {'payment_id': old.id, 'changes': jsonEncode(changes), 'edited_at': now});
      if (old.isAdvance && old.amount != updated.amount) {
        // Keep sales.advance_amount in step with the edited advance payment.
        final s = sale(old.saleId)!;
        final newAdvance = s.advanceAmount - old.amount + updated.amount;
        await tx.update('sales', {'advance_amount': newAdvance},
            where: 'id = ?', whereArgs: [s.id]);
      }
    });
    AppLog.info('Payment #${old.id} edited: ${jsonEncode(changes)}');
    await _reloadAndSync([old.saleId]);
  }

  Future<void> deletePayment(Payment p) async {
    await db.delete('payments', where: 'id = ?', whereArgs: [p.id]);
    if (p.isAdvance) {
      final s = sale(p.saleId)!;
      await db.update('sales', {'advance_amount': s.advanceAmount - p.amount},
          where: 'id = ?', whereArgs: [s.id]);
    }
    await photos.delete(p.receiptPhoto);
    AppLog.info('Payment #${p.id} deleted (${p.amount})');
    await _reloadAndSync([p.saleId]);
  }

  List<Payment> paymentsForSale(int saleId) =>
      payments.where((p) => p.saleId == saleId).toList();

  List<Payment> paymentsForCustomer(int customerId) =>
      payments.where((p) => p.customerId == customerId).toList();

  // ---------------------------------------------------------------------------
  // Security documents
  // ---------------------------------------------------------------------------

  Future<void> addSecurityDoc(SecurityDoc d) async {
    await db.insert('security_documents', d.toMap());
    AppLog.info('Security doc (${d.type}) added to sale #${d.saleId}');
    await load();
  }

  Future<void> deleteSecurityDoc(SecurityDoc d) async {
    await db.delete('security_documents', where: 'id = ?', whereArgs: [d.id]);
    await photos.delete(d.photo);
    AppLog.info('Security doc #${d.id} deleted from sale #${d.saleId}');
    await load();
  }

  // ---------------------------------------------------------------------------
  // Derived views (dashboard, lists, reports)
  // ---------------------------------------------------------------------------

  /// Every installment of every non-cancelled sale.
  List<DueEntry> allInstallments() {
    final out = <DueEntry>[];
    for (final s in sales) {
      if (s.cancelled) continue;
      final c = customer(s.customerId);
      if (c == null) continue;
      for (final st in comp[s.id]!.installments) {
        out.add(DueEntry(s, c, item(s.itemId), st));
      }
    }
    return out;
  }

  /// Open, not skipped installments sorted by due date.
  List<DueEntry> openDue() {
    final l = allInstallments()
        .where((e) => e.inst.isOpen && !e.inst.skipped)
        .toList()
      ..sort((a, b) => a.inst.dueDate.compareTo(b.inst.dueDate));
    return l;
  }

  List<DueEntry> dueToday() =>
      openDue().where((e) => e.inst.dueDate == today).toList();

  List<DueEntry> dueNextDays(int days) {
    final end = today.add(Duration(days: days));
    return openDue()
        .where((e) => e.inst.dueDate.isAfter(today) && !e.inst.dueDate.isAfter(end))
        .toList();
  }

  List<DueEntry> overdue() {
    final l = openDue().where((e) => e.inst.dueDate.isBefore(today)).toList();
    return l;
  }

  List<DueEntry> skippedOpen() => allInstallments()
      .where((e) => e.inst.skipped && e.inst.isOpen)
      .toList();

  bool _inMonth(DateTime d, DateTime month) =>
      d.year == month.year && d.month == month.month;

  List<DueEntry> dueInMonth(DateTime month) => allInstallments()
      .where((e) => _inMonth(e.inst.dueDate, month))
      .toList()
    ..sort((a, b) => a.inst.dueDate.compareTo(b.inst.dueDate));

  int expectedInMonth(DateTime month) =>
      dueInMonth(month).fold(0, (a, e) => a + e.inst.amount);

  int collectedInMonth(DateTime month) => payments
      .where((p) => _inMonth(p.paymentDate, month))
      .fold(0, (a, p) => a + p.amount);

  Map<String, int> collectedByMethod(DateTime month) {
    final m = <String, int>{};
    for (final p in payments.where((p) => _inMonth(p.paymentDate, month))) {
      m[p.method] = (m[p.method] ?? 0) + p.amount;
    }
    return m;
  }

  int pendingInMonth(DateTime month) =>
      dueInMonth(month).fold(0, (a, e) => a + e.inst.remaining);

  /// Remaining on everything due up to the end of this month (incl. overdue).
  int pendingAndOverdueNow() {
    final end = DateTime(today.year, today.month + 1, 0);
    return openDue()
        .where((e) => !e.inst.dueDate.isAfter(end))
        .fold(0, (a, e) => a + e.inst.remaining);
  }

  int totalOutstanding() => sales
      .where((s) => !s.cancelled)
      .fold(0, (a, s) => a + comp[s.id]!.remaining);

  int totalSalesValue() =>
      sales.where((s) => !s.cancelled).fold(0, (a, s) => a + s.totalPrice);

  int totalCollected() => payments
      .where((p) => !(sale(p.saleId)?.cancelled ?? false))
      .fold(0, (a, p) => a + p.amount);

  int totalProfit() {
    var profit = 0;
    for (final s in sales.where((s) => !s.cancelled)) {
      final it = item(s.itemId);
      if (it == null || it.purchaseCost <= 0) continue;
      profit += s.totalPrice - it.purchaseCost;
    }
    return profit;
  }

  Set<DateTime> dueDatesInMonth(DateTime month) => dueInMonth(month)
      .where((e) => e.inst.isOpen && !e.inst.skipped)
      .map((e) => dateOnly(e.inst.dueDate))
      .toSet();

  // ---------------------------------------------------------------------------
  // Reminder text
  // ---------------------------------------------------------------------------

  String reminderText(DueEntry e) => fillTemplate(
        reminderTemplate,
        name: e.customer.name,
        amount: money(e.inst.remaining),
        item: e.itemName,
        date: fmtDate(e.inst.dueDate),
        shop: shopName,
      );

  // ---------------------------------------------------------------------------
  // Danger zone
  // ---------------------------------------------------------------------------

  Future<void> wipeAll({bool keepSettings = true}) async {
    await db.transaction((tx) async {
      for (final t in [
        'payment_edits',
        'payments',
        'installments',
        'security_documents',
        'sale_notes',
        'sales',
        'items',
        'customers',
      ]) {
        await tx.delete(t);
      }
      if (!keepSettings) await tx.delete('settings');
    });
    if (await photos.dir.exists()) {
      await photos.dir.delete(recursive: true);
    }
    AppLog.warn('All data deleted (keepSettings=$keepSettings)');
    await load();
  }
}
