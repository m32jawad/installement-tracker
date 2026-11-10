import 'dart:convert';

import '../logic/schedule.dart';

String? _s(Object? v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

int _i(Object? v) => v == null ? 0 : (v is int ? v : (v as num).toInt());

DateTime parseDate(Object? v) => DateTime.parse(v as String);
DateTime? parseDateOrNull(Object? v) =>
    v == null || (v as String).isEmpty ? null : DateTime.parse(v);
String dbDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String nowStamp() => DateTime.now().toIso8601String();

class Customer {
  final int? id;
  final String name;
  final String phone;
  final String? altPhone;
  final String? cnic;
  final String? address;
  final String? photo;
  final String? guarantorName;
  final String? guarantorPhone;
  final String? notes;
  final DateTime createdAt;

  Customer({
    this.id,
    required this.name,
    required this.phone,
    this.altPhone,
    this.cnic,
    this.address,
    this.photo,
    this.guarantorName,
    this.guarantorPhone,
    this.notes,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Customer.fromMap(Map<String, Object?> m) => Customer(
        id: m['id'] as int,
        name: m['name'] as String,
        phone: m['phone'] as String,
        altPhone: _s(m['alt_phone']),
        cnic: _s(m['cnic']),
        address: _s(m['address']),
        photo: _s(m['photo']),
        guarantorName: _s(m['guarantor_name']),
        guarantorPhone: _s(m['guarantor_phone']),
        notes: _s(m['notes']),
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'phone': phone,
        'alt_phone': altPhone,
        'cnic': cnic,
        'address': address,
        'photo': photo,
        'guarantor_name': guarantorName,
        'guarantor_phone': guarantorPhone,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': nowStamp(),
      };
}

class Item {
  final int? id;
  final String name;
  final String category;
  final String? brand;
  final String? model;
  final String? imei;
  final String? description;
  final int purchaseCost;
  final int sellingPrice;
  final List<String> photos;
  final String status; // available / sold / reserved
  final DateTime createdAt;

  Item({
    this.id,
    required this.name,
    this.category = 'Mobile Phone',
    this.brand,
    this.model,
    this.imei,
    this.description,
    this.purchaseCost = 0,
    this.sellingPrice = 0,
    this.photos = const [],
    this.status = 'available',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Item.fromMap(Map<String, Object?> m) => Item(
        id: m['id'] as int,
        name: m['name'] as String,
        category: (m['category'] as String?) ?? 'Mobile Phone',
        brand: _s(m['brand']),
        model: _s(m['model']),
        imei: _s(m['imei']),
        description: _s(m['description']),
        purchaseCost: _i(m['purchase_cost']),
        sellingPrice: _i(m['selling_price']),
        photos: m['photos'] == null
            ? const []
            : (jsonDecode(m['photos'] as String) as List).cast<String>(),
        status: (m['status'] as String?) ?? 'available',
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'category': category,
        'brand': brand,
        'model': model,
        'imei': imei,
        'description': description,
        'purchase_cost': purchaseCost,
        'selling_price': sellingPrice,
        'photos': jsonEncode(photos),
        'status': status,
        'created_at': createdAt.toIso8601String(),
      };

  Item copyWith({String? status}) => Item(
        id: id,
        name: name,
        category: category,
        brand: brand,
        model: model,
        imei: imei,
        description: description,
        purchaseCost: purchaseCost,
        sellingPrice: sellingPrice,
        photos: photos,
        status: status ?? this.status,
        createdAt: createdAt,
      );

  String get subtitle => [brand, model].whereType<String>().join(' · ');
}

class Sale {
  final int? id;
  final int customerId;
  final int? itemId;
  final DateTime saleDate;
  final int totalPrice;
  final int advanceAmount;
  final String advanceMethod;
  final int monthlyAmount;
  final int totalInstallments;
  final Frequency frequency;
  final int customDays;
  final DateTime firstDueDate;
  final bool cancelled;
  final String? notes;
  final DateTime createdAt;

  Sale({
    this.id,
    required this.customerId,
    this.itemId,
    required this.saleDate,
    required this.totalPrice,
    required this.advanceAmount,
    this.advanceMethod = 'Cash',
    required this.monthlyAmount,
    required this.totalInstallments,
    this.frequency = Frequency.monthly,
    this.customDays = 30,
    required this.firstDueDate,
    this.cancelled = false,
    this.notes,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Sale.fromMap(Map<String, Object?> m) => Sale(
        id: m['id'] as int,
        customerId: m['customer_id'] as int,
        itemId: m['item_id'] as int?,
        saleDate: parseDate(m['sale_date']),
        totalPrice: _i(m['total_price']),
        advanceAmount: _i(m['advance_amount']),
        advanceMethod: (m['advance_method'] as String?) ?? 'Cash',
        monthlyAmount: _i(m['monthly_amount']),
        totalInstallments: _i(m['total_installments']),
        frequency: frequencyFromName(m['frequency'] as String?),
        customDays: _i(m['custom_days']) == 0 ? 30 : _i(m['custom_days']),
        firstDueDate: parseDate(m['first_due_date']),
        cancelled: m['status'] == 'cancelled',
        notes: _s(m['notes']),
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  Map<String, Object?> toMap({String? computedStatus}) => {
        if (id != null) 'id': id,
        'customer_id': customerId,
        'item_id': itemId,
        'sale_date': dbDate(saleDate),
        'total_price': totalPrice,
        'advance_amount': advanceAmount,
        'advance_method': advanceMethod,
        'advance_date': dbDate(saleDate),
        'monthly_amount': monthlyAmount,
        'total_installments': totalInstallments,
        'frequency': frequency.name,
        'custom_days': customDays,
        'first_due_date': dbDate(firstDueDate),
        'status': cancelled ? 'cancelled' : (computedStatus ?? 'active'),
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
      };
}

class Installment {
  final int id;
  final int saleId;
  final int number;
  final DateTime dueDate;
  final int amount;
  final bool skipped;
  final String? skipReason;

  Installment({
    required this.id,
    required this.saleId,
    required this.number,
    required this.dueDate,
    required this.amount,
    this.skipped = false,
    this.skipReason,
  });

  factory Installment.fromMap(Map<String, Object?> m) => Installment(
        id: m['id'] as int,
        saleId: m['sale_id'] as int,
        number: _i(m['installment_number']),
        dueDate: parseDate(m['due_date']),
        amount: _i(m['amount']),
        skipped: _i(m['skipped']) == 1,
        skipReason: _s(m['skip_reason']),
      );

  InstallmentInput toInput() => InstallmentInput(
      id: id, number: number, dueDate: dueDate, amount: amount, skipped: skipped);
}

class Payment {
  final int? id;
  final int saleId;
  final int? installmentId;
  final int customerId;
  final int amount;
  final DateTime paymentDate;
  final String method;
  final String? transactionId;
  final String? bankName;
  final String? chequeNumber;
  final String? receiptPhoto;
  final String? note;
  final bool isAdvance;
  final bool applyExtraToNext;
  final DateTime createdAt;
  final DateTime? editedAt;

  Payment({
    this.id,
    required this.saleId,
    this.installmentId,
    required this.customerId,
    required this.amount,
    required this.paymentDate,
    required this.method,
    this.transactionId,
    this.bankName,
    this.chequeNumber,
    this.receiptPhoto,
    this.note,
    this.isAdvance = false,
    this.applyExtraToNext = true,
    DateTime? createdAt,
    this.editedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Payment.fromMap(Map<String, Object?> m) => Payment(
        id: m['id'] as int,
        saleId: m['sale_id'] as int,
        installmentId: m['installment_id'] as int?,
        customerId: m['customer_id'] as int,
        amount: _i(m['amount']),
        paymentDate: parseDate(m['payment_date']),
        method: (m['method'] as String?) ?? 'Cash',
        transactionId: _s(m['transaction_id']),
        bankName: _s(m['bank_name']),
        chequeNumber: _s(m['cheque_number']),
        receiptPhoto: _s(m['receipt_photo']),
        note: _s(m['note']),
        isAdvance: _i(m['is_advance']) == 1,
        applyExtraToNext: _i(m['apply_extra']) == 1,
        createdAt: DateTime.parse(m['created_at'] as String),
        editedAt: parseDateTimeOrNull(m['edited_at']),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'sale_id': saleId,
        'installment_id': installmentId,
        'customer_id': customerId,
        'amount': amount,
        'payment_date': dbDate(paymentDate),
        'method': method,
        'transaction_id': transactionId,
        'bank_name': bankName,
        'cheque_number': chequeNumber,
        'receipt_photo': receiptPhoto,
        'note': note,
        'is_advance': isAdvance ? 1 : 0,
        'apply_extra': applyExtraToNext ? 1 : 0,
        'created_by': 'owner',
        'created_at': createdAt.toIso8601String(),
        'edited_at': editedAt?.toIso8601String(),
      };

  PaymentInput toInput() => PaymentInput(
        id: id!,
        installmentId: installmentId,
        amount: amount,
        date: paymentDate,
        method: method,
        isAdvance: isAdvance,
        applyExtraToNext: applyExtraToNext,
      );
}

DateTime? parseDateTimeOrNull(Object? v) =>
    v == null || (v as String).isEmpty ? null : DateTime.parse(v);

class PaymentEdit {
  final int id;
  final int paymentId;
  final String changes;
  final DateTime editedAt;
  PaymentEdit(this.id, this.paymentId, this.changes, this.editedAt);
  factory PaymentEdit.fromMap(Map<String, Object?> m) => PaymentEdit(
      m['id'] as int,
      m['payment_id'] as int,
      m['changes'] as String,
      DateTime.parse(m['edited_at'] as String));
}

const securityDocTypes = <String, String>{
  'cnic_front': 'CNIC Front',
  'cnic_back': 'CNIC Back',
  'cheque': 'Cheque',
  'guarantor_cnic': 'Guarantor CNIC',
  'agreement': 'Agreement / Stamp Paper',
  'customer_with_item': 'Customer Photo with Item',
  'other': 'Other Document',
};

class SecurityDoc {
  final int? id;
  final int saleId;
  final String type;
  final String photo;
  final String? note;
  final String? chequeNumber;
  final String? bankName;
  final String? chequeDate;
  final DateTime createdAt;

  SecurityDoc({
    this.id,
    required this.saleId,
    required this.type,
    required this.photo,
    this.note,
    this.chequeNumber,
    this.bankName,
    this.chequeDate,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String get typeLabel => securityDocTypes[type] ?? type;

  factory SecurityDoc.fromMap(Map<String, Object?> m) => SecurityDoc(
        id: m['id'] as int,
        saleId: m['sale_id'] as int,
        type: m['type'] as String,
        photo: m['photo_url'] as String,
        note: _s(m['note']),
        chequeNumber: _s(m['cheque_number']),
        bankName: _s(m['bank_name']),
        chequeDate: _s(m['cheque_date']),
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'sale_id': saleId,
        'type': type,
        'photo_url': photo,
        'note': note,
        'cheque_number': chequeNumber,
        'bank_name': bankName,
        'cheque_date': chequeDate,
        'created_at': createdAt.toIso8601String(),
      };
}

class SaleNote {
  final int id;
  final int saleId;
  final String note;
  final DateTime createdAt;
  SaleNote(this.id, this.saleId, this.note, this.createdAt);
  factory SaleNote.fromMap(Map<String, Object?> m) => SaleNote(m['id'] as int,
      m['sale_id'] as int, m['note'] as String, DateTime.parse(m['created_at'] as String));
}
