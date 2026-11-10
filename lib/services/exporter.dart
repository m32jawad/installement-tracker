import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../core/app_log.dart';
import '../core/format.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/schedule.dart';

const _green = PdfColor.fromInt(0xFF0F7A55);

Future<Directory> exportDir() async {
  final d = Directory('${(await getTemporaryDirectory()).path}/exports');
  if (!await d.exists()) await d.create(recursive: true);
  return d;
}

Future<void> shareFile(File f, String text) async {
  await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: text));
}

String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');

pw.Widget _header(AppState app, String title, String subtitle) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(app.shopName,
            style: pw.TextStyle(
                fontSize: 20, fontWeight: pw.FontWeight.bold, color: _green)),
        if (app.shopAddress.isNotEmpty || app.shopPhone.isNotEmpty)
          pw.Text([app.shopAddress, app.shopPhone].where((s) => s.isNotEmpty).join('  |  '),
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        pw.SizedBox(height: 10),
        pw.Text(title, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.Text(subtitle, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.Divider(color: _green),
      ],
    );

pw.Widget _kv(String k, String v) => pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(4)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(k, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        pw.Text(v, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      ]),
    );

pw.Widget _table(List<String> headers, List<List<String>> rows) => pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerStyle: pw.TextStyle(
          fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: _green),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
    );

Future<File> _savePdf(pw.Document doc, String name) async {
  final f = File('${(await exportDir()).path}/$name.pdf');
  await f.writeAsBytes(await doc.save());
  AppLog.info('PDF exported: ${f.path}');
  return f;
}

/// Monthly report PDF (spec 3.7).
Future<File> monthlyReportPdf(AppState app, DateTime month) async {
  final entries = app.dueInMonth(month);
  final byMethod = app.collectedByMethod(month);
  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    build: (_) => [
      _header(app, 'Monthly Report - ${fmtMonth(month)}',
          'Generated ${fmtDate(DateTime.now())}'),
      pw.Row(children: [
        pw.Expanded(child: _kv('Collected', money(app.collectedInMonth(month)))),
        pw.SizedBox(width: 6),
        pw.Expanded(child: _kv('Expected', money(app.expectedInMonth(month)))),
        pw.SizedBox(width: 6),
        pw.Expanded(child: _kv('Pending / Missed', money(app.pendingInMonth(month)))),
      ]),
      pw.SizedBox(height: 12),
      if (byMethod.isNotEmpty) ...[
        pw.Text('Collected by method',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        _table(['Method', 'Amount'],
            byMethod.entries.map((e) => [e.key, money(e.value)]).toList()),
        pw.SizedBox(height: 12),
      ],
      pw.Text('Installments due in ${fmtMonth(month)}',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      _table(
        ['Due', 'Customer', 'Phone', 'Item', '#', 'Amount', 'Paid', 'Status'],
        entries
            .map((e) => [
                  fmtDate(e.inst.dueDate),
                  e.customer.name,
                  e.customer.phone,
                  e.itemName,
                  '${e.inst.number}',
                  money(e.inst.amount),
                  money(e.inst.paid),
                  instStatusLabel(e.inst.status),
                ])
            .toList(),
      ),
    ],
  ));
  return _savePdf(doc, 'Monthly_Report_${_safe(fmtMonth(month))}');
}

/// Customer ledger PDF: every sale, schedule and payment for one customer.
Future<File> customerLedgerPdf(AppState app, Customer c) async {
  final sum = app.customerSummary(c.id!);
  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    build: (_) => [
      _header(app, 'Customer Ledger - ${c.name}',
          [c.phone, if (c.cnic != null) 'CNIC ${c.cnic}', if (c.address != null) c.address!]
              .join('  |  ')),
      pw.Row(children: [
        pw.Expanded(child: _kv('Total Purchase', money(sum.totalPurchase))),
        pw.SizedBox(width: 6),
        pw.Expanded(child: _kv('Total Paid', money(sum.totalPaid))),
        pw.SizedBox(width: 6),
        pw.Expanded(child: _kv('Pending', money(sum.pending))),
      ]),
      for (final s in app.salesFor(c.id!)) ...[
        pw.SizedBox(height: 14),
        pw.Text(
            '${app.item(s.itemId)?.name ?? 'Item'} - sold ${fmtDate(s.saleDate)} - '
            '${money(s.totalPrice)} (${saleStatusLabel(app.comp[s.id]!.status)})',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        _table(
          ['#', 'Due', 'Amount', 'Paid', 'Paid on', 'Method', 'Status'],
          app.comp[s.id]!.installments
              .map((i) => [
                    '${i.number}',
                    fmtDate(i.dueDate),
                    money(i.amount),
                    money(i.paid),
                    i.paidDate == null ? '-' : fmtDate(i.paidDate!),
                    i.method ?? '-',
                    instStatusLabel(i.status),
                  ])
              .toList(),
        ),
        pw.SizedBox(height: 6),
        _table(
          ['Payment date', 'Type', 'Amount', 'Method', 'Note'],
          app.paymentsForSale(s.id!).reversed
              .map((p) => [
                    fmtDate(p.paymentDate),
                    p.isAdvance ? 'Advance' : _instLabel(app, p),
                    money(p.amount),
                    p.method,
                    p.note ?? '',
                  ])
              .toList(),
        ),
      ],
    ],
  ));
  return _savePdf(doc, 'Ledger_${_safe(c.name)}');
}

String _instLabel(AppState app, Payment p) {
  if (p.installmentId == null) return 'Payment';
  final i = app.installment(p.installmentId!);
  return i == null ? 'Payment' : 'Installment ${i.number}';
}

String _csvCell(Object? v) {
  final s = v?.toString() ?? '';
  if (s.contains(RegExp(r'[",\n]'))) return '"${s.replaceAll('"', '""')}"';
  return s;
}

String toCsv(List<String> headers, List<List<Object?>> rows) => [
      headers.map(_csvCell).join(','),
      ...rows.map((r) => r.map(_csvCell).join(',')),
    ].join('\n');

/// Customer ledger as CSV (opens in Excel).
Future<File> customerLedgerCsv(AppState app, Customer c) async {
  final rows = <List<Object?>>[];
  for (final s in app.salesFor(c.id!)) {
    final itemName = app.item(s.itemId)?.name ?? '';
    for (final i in app.comp[s.id]!.installments) {
      rows.add([
        itemName,
        i.number,
        dbDate(i.dueDate),
        i.amount,
        i.paid,
        i.paidDate == null ? '' : dbDate(i.paidDate!),
        i.method ?? '',
        instStatusLabel(i.status),
      ]);
    }
  }
  final f = File('${(await exportDir()).path}/Ledger_${_safe(c.name)}.csv');
  await f.writeAsString(toCsv(
      ['Item', 'Installment', 'Due date', 'Amount', 'Paid', 'Paid date', 'Method', 'Status'],
      rows));
  return f;
}

/// Every table as CSV files in one folder, returned as a list of files.
Future<List<File>> exportAllCsv(AppState app) async {
  final dir = await exportDir();
  Future<File> write(String name, List<String> h, List<List<Object?>> rows) async {
    final f = File('${dir.path}/$name.csv');
    await f.writeAsString(toCsv(h, rows));
    return f;
  }

  final files = <File>[
    await write(
        'customers',
        ['id', 'name', 'phone', 'alt_phone', 'cnic', 'address', 'guarantor_name', 'guarantor_phone', 'notes'],
        app.customers
            .map((c) => [c.id, c.name, c.phone, c.altPhone, c.cnic, c.address, c.guarantorName, c.guarantorPhone, c.notes])
            .toList()),
    await write(
        'items',
        ['id', 'name', 'category', 'brand', 'model', 'imei', 'purchase_cost', 'selling_price', 'status'],
        app.items
            .map((i) => [i.id, i.name, i.category, i.brand, i.model, i.imei, i.purchaseCost, i.sellingPrice, i.status])
            .toList()),
    await write(
        'sales',
        ['id', 'customer', 'item', 'sale_date', 'total', 'advance', 'installment', 'count', 'frequency', 'paid', 'remaining', 'status'],
        app.sales.map((s) {
          final c = app.comp[s.id]!;
          return [
            s.id,
            app.customer(s.customerId)?.name,
            app.item(s.itemId)?.name,
            dbDate(s.saleDate),
            s.totalPrice,
            s.advanceAmount,
            s.monthlyAmount,
            s.totalInstallments,
            s.frequency.name,
            c.totalPaid,
            c.remaining,
            c.status.name,
          ];
        }).toList()),
    await write(
        'installments',
        ['sale_id', 'customer', 'number', 'due_date', 'amount', 'paid', 'status', 'paid_date', 'method'],
        app.allInstallments()
            .map((e) => [
                  e.sale.id,
                  e.customer.name,
                  e.inst.number,
                  dbDate(e.inst.dueDate),
                  e.inst.amount,
                  e.inst.paid,
                  e.inst.status.name,
                  e.inst.paidDate == null ? '' : dbDate(e.inst.paidDate!),
                  e.inst.method ?? '',
                ])
            .toList()),
    await write(
        'payments',
        ['id', 'date', 'customer', 'sale_id', 'type', 'amount', 'method', 'transaction_id', 'note', 'edited'],
        app.payments
            .map((p) => [
                  p.id,
                  dbDate(p.paymentDate),
                  app.customer(p.customerId)?.name,
                  p.saleId,
                  p.isAdvance ? 'Advance' : _instLabel(app, p),
                  p.amount,
                  p.method,
                  p.transactionId,
                  p.note,
                  p.editedAt == null ? '' : 'yes',
                ])
            .toList()),
  ];
  AppLog.info('CSV export: ${files.length} files');
  return files;
}
