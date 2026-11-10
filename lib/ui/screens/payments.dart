import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../lock.dart';
import '../theme.dart';
import '../widgets.dart';
import 'collect_payment.dart';
import 'sales.dart';

enum _Range { all, week, month, lastMonth, custom }

const _rangeLabels = {
  _Range.all: 'All time',
  _Range.week: 'This week',
  _Range.month: 'This month',
  _Range.lastMonth: 'Last month',
  _Range.custom: 'Custom',
};

/// Global payment history / ledger (spec 3.5).
class PaymentsScreen extends StatefulWidget {
  final bool standalone;
  const PaymentsScreen({super.key, this.standalone = false});
  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  String _q = '';
  String? _method;
  _Range _range = _Range.all;
  DateTimeRange? _custom;

  bool _inRange(DateTime d, DateTime today) {
    switch (_range) {
      case _Range.all:
        return true;
      case _Range.week:
        final start = today.subtract(Duration(days: today.weekday - 1));
        return !d.isBefore(start) && !d.isAfter(start.add(const Duration(days: 6)));
      case _Range.month:
        return d.year == today.year && d.month == today.month;
      case _Range.lastMonth:
        final m = DateTime(today.year, today.month - 1);
        return d.year == m.year && d.month == m.month;
      case _Range.custom:
        final r = _custom;
        return r == null || (!d.isBefore(r.start) && !d.isAfter(r.end));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final list = app.payments.where((p) {
      if (_method != null && p.method != _method) return false;
      if (!_inRange(p.paymentDate, app.today)) return false;
      final c = app.customer(p.customerId);
      final s = app.sale(p.saleId);
      return matchesQuery(_q, [c?.name, c?.phone, app.item(s?.itemId)?.name, p.transactionId, p.note]);
    }).toList();
    final total = list.fold<int>(0, (a, p) => a + p.amount);
    final methods = {...app.paymentMethods, ...app.payments.map((p) => p.method)}.toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Payments')),
      body: Column(children: [
        SearchBox(hint: 'Search customer, item, transaction ID', onChanged: (v) => setState(() => _q = v)),
        ChoiceChips<_Range>(
          values: _Range.values,
          selected: _range,
          label: (r) => r == _Range.custom && _custom != null
              ? '${fmtDateShort(_custom!.start)} - ${fmtDateShort(_custom!.end)}'
              : _rangeLabels[r]!,
          onSelected: (r) async {
            if (r == _Range.custom) {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                initialDateRange: _custom,
              );
              if (picked == null) return;
              _custom = picked;
            }
            setState(() => _range = r);
          },
        ),
        ChoiceChips<String?>(
          values: [null, ...methods],
          selected: _method,
          label: (m) => m ?? 'All methods',
          onSelected: (m) => setState(() => _method = m),
        ),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: StatusColors.paid.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Expanded(child: Text('${list.length} payments')),
            Text(money(total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: StatusColors.paid)),
          ]),
        ),
        Expanded(
          child: list.isEmpty
              ? const EmptyState(icon: Icons.payments_outlined, text: 'No payments found')
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, indent: 70),
                  itemBuilder: (_, i) => PaymentTile(list[i]),
                ),
        ),
      ]),
    );
  }
}

/// One payment row (ledger, dashboard, customer timeline).
class PaymentTile extends StatelessWidget {
  final Payment p;
  final bool showCustomer;
  const PaymentTile(this.p, {super.key, this.showCustomer = true});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final c = app.customer(p.customerId);
    final s = app.sale(p.saleId);
    final inst = p.installmentId == null ? null : app.installment(p.installmentId!);
    final what = p.isAdvance ? 'Advance' : (inst == null ? 'Payment' : 'Installment ${inst.number}');
    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: StatusColors.paid.withValues(alpha: 0.15),
        child: const Icon(Icons.south_west_rounded, color: StatusColors.paid, size: 18),
      ),
      title: Text(
        showCustomer ? '${c?.name ?? 'Customer'} paid ${money(p.amount)}' : '$what - ${money(p.amount)}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text([
        if (showCustomer) what,
        'via ${p.method}',
        fmtDate(p.paymentDate),
        if (s != null && showCustomer) app.item(s.itemId)?.name ?? '',
      ].where((x) => x.isNotEmpty).join(' · ')),
      trailing: p.editedAt != null ? const StatusChip('Edited', StatusColors.partial, dense: true) : null,
      onTap: () => showPaymentDetail(context, p.id!),
    );
  }
}

String paymentLabel(AppState app, Payment p) {
  if (p.isAdvance) return 'Advance';
  if (p.installmentId == null) return 'Payment';
  final i = app.installment(p.installmentId!);
  return i == null ? 'Payment' : 'Installment ${i.number}';
}

String receiptText(AppState app, Payment p) {
  final c = app.customer(p.customerId);
  final s = app.sale(p.saleId);
  final comp = app.comp[p.saleId];
  return [
    'RECEIPT - ${app.shopName}',
    if (app.shopPhone.isNotEmpty) app.shopPhone,
    '',
    'Customer: ${c?.name ?? ''}',
    'Item: ${app.item(s?.itemId)?.name ?? ''}',
    '${paymentLabel(app, p)}: ${money(p.amount)}',
    'Date: ${fmtDate(p.paymentDate)}',
    'Method: ${p.method}${p.transactionId != null ? ' (${p.transactionId})' : ''}',
    if (comp != null) ...[
      '',
      'Total paid: ${money(comp.totalPaid)} of ${money(comp.total)}',
      'Remaining: ${money(comp.remaining)}',
      if (comp.nextDue != null) 'Next due: ${money(comp.nextDue!.remaining)} on ${fmtDate(comp.nextDue!.dueDate)}',
    ],
    '',
    'Thank you!',
  ].join('\n');
}

/// Payment detail: receipt, edit (with audit history), delete.
Future<void> showPaymentDetail(BuildContext context, int paymentId) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => _PaymentDetail(paymentId: paymentId, outer: context),
  );
}

class _PaymentDetail extends StatelessWidget {
  final int paymentId;
  final BuildContext outer;
  const _PaymentDetail({required this.paymentId, required this.outer});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.payments.where((x) => x.id == paymentId).firstOrNull;
    if (p == null) return const SizedBox(height: 120, child: Center(child: Text('Payment deleted')));
    final c = app.customer(p.customerId);
    final s = app.sale(p.saleId);
    final edits = app.editsByPayment[paymentId] ?? const [];
    return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      Row(children: [
        Text(money(p.amount), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: StatusColors.paid)),
        const SizedBox(width: 8),
        if (p.editedAt != null) const StatusChip('Edited', StatusColors.partial, dense: true),
      ]),
      const SizedBox(height: 8),
      InfoRow('Customer', c?.name ?? '-'),
      InfoRow('Item', app.item(s?.itemId)?.name ?? '-'),
      InfoRow('For', paymentLabel(app, p)),
      InfoRow('Date', fmtDate(p.paymentDate)),
      InfoRow('Method', p.method),
      if (p.bankName != null) InfoRow('Bank', p.bankName!),
      if (p.transactionId != null) InfoRow('Transaction ID', p.transactionId!),
      if (p.chequeNumber != null) InfoRow('Cheque #', p.chequeNumber!),
      if (p.note != null) InfoRow('Note', p.note!),
      InfoRow('Recorded', fmtDate(p.createdAt)),
      if (p.receiptPhoto != null) ...[
        const SizedBox(height: 8),
        PhotoThumb(p.receiptPhoto!, size: 110, caption: 'Receipt'),
      ],
      const SizedBox(height: 14),
      Row(children: [
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: () {
              Navigator.pop(context);
              showModalBottomSheet(
                context: outer,
                isScrollControlled: true,
                showDragHandle: true,
                useSafeArea: true,
                builder: (_) => PaymentForm(saleId: p.saleId, existing: p),
              );
            },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: () => AppLockController.instance
                .whileExternal(() => SharePlus.instance.share(ShareParams(text: receiptText(app, p)))),
            icon: const Icon(Icons.share_outlined),
            label: const Text('Receipt'),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(outer, MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: p.saleId)));
            },
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('Open sale'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: StatusColors.overdue),
            onPressed: () async {
              final ok = await confirm(context,
                  title: 'Delete payment?',
                  message: '${money(p.amount)} on ${fmtDate(p.paymentDate)} will be removed and totals recalculated.',
                  confirmLabel: 'Delete',
                  danger: true);
              if (ok) {
                await app.deletePayment(p);
                if (context.mounted) Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete'),
          ),
        ),
      ]),
      if (edits.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Edit history', style: Theme.of(context).textTheme.titleMedium),
        for (final e in edits)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history, size: 20),
            title: Text(_describe(e.changes)),
            subtitle: Text('${fmtDate(e.editedAt)} ${e.editedAt.hour.toString().padLeft(2, '0')}:${e.editedAt.minute.toString().padLeft(2, '0')}'),
          ),
      ],
    ]);
  }

  String _describe(String json) {
    try {
      final m = (jsonDecode(json) as Map).cast<String, dynamic>();
      return m.entries.map((e) {
        final v = e.value as List;
        String f(Object? x) => e.key == 'amount' && x is num ? money(x) : '${x ?? '-'}';
        return '${e.key}: ${f(v[0])} -> ${f(v[1])}';
      }).join('\n');
    } catch (_) {
      return json;
    }
  }
}
