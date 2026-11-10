import '../core/app_log.dart';
import '../logic/schedule.dart';
import 'app_state.dart';
import 'models.dart';

/// Loads a realistic demo shop (customers, phones, sales, payments) so a new
/// user can explore the app. Dates are relative to today so the dashboard
/// always has something due today, overdue and upcoming.
Future<void> loadSampleData(AppState app) async {
  final t = app.today;
  DateTime m(int months, [int day = 0]) {
    final d = addMonths(t, months);
    return day == 0 ? d : DateTime(d.year, d.month, day);
  }

  Future<int> cust(String name, String phone, String cnic, String address,
          String notes) =>
      app.saveCustomer(Customer(
          name: name, phone: phone, cnic: cnic, address: address, notes: notes));

  Future<int> item(String name, String brand, String model, String imei,
          int cost, int price) =>
      app.saveItem(Item(
          name: name,
          brand: brand,
          model: model,
          imei: imei,
          purchaseCost: cost,
          sellingPrice: price,
          description: 'Box + charger, PTA approved'));

  final ali = await cust('Ali Raza', '0300-1234567', '35202-1234567-1',
      'Shop 4, Main Bazaar', 'Works at shop in main bazaar, reliable');
  final sana = await cust('Sana Bibi', '0321-7654321', '35201-7654321-2',
      'House 12, Block C, Model Town', 'Teacher, pays by JazzCash');
  final usman = await cust('Usman Ghani', '0333-5550001', '',
      'Near Jamia Masjid', 'Sometimes late, call before due date');
  final hamza = await cust('Hamza Iqbal', '0345-9988776', '35202-9988776-5',
      'Street 7, Gulberg', '');
  final ayesha = await cust('Ayesha Khan', '0312-4455667', '', 'DHA Phase 5', '');

  final i1 = await item('iPhone 13 128GB', 'Apple', 'Midnight / 128GB',
      '356789104512345', 140000, 165000);
  final i2 = await item('Samsung Galaxy A54', 'Samsung', 'Awesome Graphite / 8+256',
      '354433221100998', 92000, 110000);
  final i3 = await item('Infinix Hot 40', 'Infinix', 'Starlit Black / 8+128',
      '861234509876543', 36000, 45000);
  final i4 = await item('Vivo Y22', 'Vivo', 'Metaverse Green / 4+64',
      '869001122334455', 30000, 38000);
  await item('Oppo A78', 'Oppo', 'Glowing Black / 8+128', '862211009988776',
      52000, 62000);
  await item('Redmi Note 13', 'Xiaomi', 'Mint Green / 8+256', '868877665544332',
      55000, 66000);

  // Ali: iPhone, started 3 months ago, pays on time.
  final s1 = await app.createSale(Sale(
    customerId: ali,
    itemId: i1,
    saleDate: m(-3),
    totalPrice: 165000,
    advanceAmount: 45000,
    monthlyAmount: 10000,
    totalInstallments: 12,
    firstDueDate: m(-2),
    notes: 'Customer promised to pay before due date every month',
  ));
  // Sana: Samsung, one installment due today.
  final s2 = await app.createSale(Sale(
    customerId: sana,
    itemId: i2,
    saleDate: m(-2),
    totalPrice: 110000,
    advanceAmount: 30000,
    advanceMethod: 'JazzCash',
    monthlyAmount: 8000,
    totalInstallments: 10,
    firstDueDate: m(-1),
  ));
  // Usman: Infinix, overdue + a skipped month.
  final s3 = await app.createSale(Sale(
    customerId: usman,
    itemId: i3,
    saleDate: m(-4, 5),
    totalPrice: 45000,
    advanceAmount: 15000,
    monthlyAmount: 5000,
    totalInstallments: 6,
    firstDueDate: m(-3, 5),
  ));
  // Hamza: Vivo, due in a few days.
  final s4 = await app.createSale(Sale(
    customerId: hamza,
    itemId: i4,
    saleDate: t.subtract(const Duration(days: 26)),
    totalPrice: 38000,
    advanceAmount: 8000,
    advanceMethod: 'Easypaisa',
    monthlyAmount: 5000,
    totalInstallments: 6,
    firstDueDate: t.add(const Duration(days: 4)),
  ));
  // Ayesha: small completed plan.
  final i5 = await item('Nokia 105', 'Nokia', 'Blue', '351111222233334', 4000, 6000);
  final s5 = await app.createSale(Sale(
    customerId: ayesha,
    itemId: i5,
    saleDate: m(-3),
    totalPrice: 6000,
    advanceAmount: 2000,
    monthlyAmount: 2000,
    totalInstallments: 2,
    firstDueDate: m(-2),
  ));

  Future<void> payInst(int saleId, int number, int amount, DateTime date,
      String method) async {
    final inst = app.installmentsBySale[saleId]!.firstWhere((i) => i.number == number);
    final s = app.sale(saleId)!;
    await app.addPayment(Payment(
      saleId: saleId,
      installmentId: inst.id,
      customerId: s.customerId,
      amount: amount,
      paymentDate: date,
      method: method,
    ));
  }

  final s1i = app.installmentsBySale[s1]!;
  await payInst(s1, 1, 10000, s1i[0].dueDate.subtract(const Duration(days: 2)), 'Cash');
  await payInst(s1, 2, 10000, s1i[1].dueDate, 'Bank Transfer');

  final s2i = app.installmentsBySale[s2]!;
  await payInst(s2, 1, 8000, s2i[0].dueDate, 'JazzCash');
  // Make Sana's 2nd installment due today for the demo.
  await app.db.update('installments', {'due_date': dbDate(t)},
      where: 'id = ?', whereArgs: [s2i[1].id]);

  final s3i = app.installmentsBySale[s3]!;
  await payInst(s3, 1, 5000, s3i[0].dueDate.add(const Duration(days: 3)), 'Cash');
  await app.setSkipped(s3i[1].id, true, reason: 'Out of city');
  await payInst(s3, 3, 3000, s3i[2].dueDate.add(const Duration(days: 1)), 'Easypaisa');
  await payInst(s3, 3, 2000, t, 'Cash'); // rest of the partial, collected today

  final s5i = app.installmentsBySale[s5]!;
  await payInst(s5, 1, 2000, s5i[0].dueDate, 'Cash');
  await payInst(s5, 2, 2000, s5i[1].dueDate, 'Cash');

  await app.addSaleNote(s4, 'Guarantor: brother, Bilal Iqbal 0300-1112223');
  await app.load();
  AppLog.info('Sample data loaded');
}
