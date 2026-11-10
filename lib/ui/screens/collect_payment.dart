import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_log.dart';
import '../../core/format.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../logic/schedule.dart';
import '../theme.dart';
import '../widgets.dart';

/// "Collect Payment" from the quick-action button or a customer page:
/// pick which sale first (skipped when the customer has one open sale).
Future<void> collectPaymentFlow(BuildContext context, {int? customerId}) async {
  final app = context.read<AppState>();
  final open = app.sales.where((s) {
    if (customerId != null && s.customerId != customerId) return false;
    final c = app.comp[s.id]!;
    return !s.cancelled && c.status != SaleStatus.completed;
  }).toList()
    ..sort((a, b) {
      final x = app.comp[a.id]!.nextDue?.dueDate ?? DateTime(2100);
      final y = app.comp[b.id]!.nextDue?.dueDate ?? DateTime(2100);
      return x.compareTo(y);
    });
  if (open.isEmpty) {
    toast(context, 'No open sales to collect for');
    return;
  }
  if (open.length == 1) {
    await showCollectPayment(context, saleId: open.first.id!, installmentId: app.comp[open.first.id]!.nextDue?.id);
    return;
  }
  final picked = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _SalePicker(sales: open),
  );
  if (picked != null && context.mounted) {
    await showCollectPayment(context, saleId: picked, installmentId: app.comp[picked]!.nextDue?.id);
  }
}

class _SalePicker extends StatefulWidget {
  final List<Sale> sales;
  const _SalePicker({required this.sales});
  @override
  State<_SalePicker> createState() => _SalePickerState();
}

class _SalePickerState extends State<_SalePicker> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final l = widget.sales.where((s) {
      final c = app.customer(s.customerId);
      return matchesQuery(_q, [c?.name, c?.phone, app.item(s.itemId)?.name]);
    }).toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, sc) => Column(children: [
        Text('Collect payment for...', style: Theme.of(context).textTheme.titleLarge),
        SearchBox(hint: 'Search customer or item', onChanged: (v) => setState(() => _q = v)),
        Expanded(
          child: ListView(
            controller: sc,
            children: [
              for (final s in l)
                Builder(builder: (_) {
                  final c = app.customer(s.customerId)!;
                  final n = app.comp[s.id]!.nextDue;
                  final late = n?.daysLate(app.today) ?? 0;
                  return ListTile(
                    leading: PersonAvatar(name: c.name, photo: c.photo),
                    title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(app.item(s.itemId)?.name ?? 'Item'),
                    trailing: n == null
                        ? null
                        : Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(money(n.remaining), style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(late > 0 ? daysLateLabel(late) : fmtDateShort(n.dueDate),
                                style: TextStyle(fontSize: 12, color: late > 0 ? StatusColors.overdue : null)),
                          ]),
                    onTap: () => Navigator.pop(context, s.id),
                  );
                }),
            ],
          ),
        ),
      ]),
    );
  }
}

Future<void> showCollectPayment(BuildContext context, {required int saleId, int? installmentId}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => PaymentForm(saleId: saleId, installmentId: installmentId),
    );

/// Collect a new payment, or edit [existing].
class PaymentForm extends StatefulWidget {
  final int saleId;
  final int? installmentId;
  final Payment? existing;
  const PaymentForm({super.key, required this.saleId, this.installmentId, this.existing});
  @override
  State<PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends State<PaymentForm> {
  final _form = GlobalKey<FormState>();
  late int? _instId = widget.existing?.installmentId ?? widget.installmentId;
  final _amount = TextEditingController();
  late DateTime _date = widget.existing?.paymentDate ?? context.read<AppState>().today;
  late String _method = widget.existing?.method ?? 'Cash';
  late final _txn = TextEditingController(text: widget.existing?.transactionId);
  late final _bank = TextEditingController(text: widget.existing?.bankName);
  late final _cheque = TextEditingController(text: widget.existing?.chequeNumber);
  late final _note = TextEditingController(text: widget.existing?.note);
  late String? _receipt = widget.existing?.receiptPhoto;
  bool _saving = false;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_editing) {
      _amount.text = '${widget.existing!.amount}';
    } else {
      _amount.text = '${_dueFor(_instId) ?? ''}';
    }
  }

  int? _dueFor(int? instId) {
    final app = context.read<AppState>();
    if (instId == null) return app.comp[widget.saleId]?.nextDue?.remaining;
    return app.installmentState(widget.saleId, instId)?.remaining;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final app = context.read<AppState>();
    final sale = app.sale(widget.saleId)!;
    final amount = parseAmount(_amount.text)!;
    var applyExtra = widget.existing?.applyExtraToNext ?? true;

    if (!_editing || amount != widget.existing!.amount) {
      final due = _instId == null ? app.comp[widget.saleId]!.remaining : (_dueFor(_instId) ?? 0);
      if (_instId != null && amount > due && !(widget.existing?.isAdvance ?? false)) {
        final extra = amount - due;
        final choice = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Extra amount'),
            content: Text('${money(amount)} is ${money(extra)} more than this installment (${money(due)}).\n\n'
                'Apply the extra to the next installment?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep as advance')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply to next')),
            ],
          ),
        );
        if (choice == null) return;
        applyExtra = choice;
      }
    }

    setState(() => _saving = true);
    String? t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final p = Payment(
      id: widget.existing?.id,
      saleId: widget.saleId,
      installmentId: _instId,
      customerId: sale.customerId,
      amount: amount,
      paymentDate: _date,
      method: _method,
      transactionId: _method == 'Bank Transfer' || _method == 'JazzCash' || _method == 'Easypaisa' ? t(_txn) : null,
      bankName: _method == 'Bank Transfer' || _method == 'Cheque' ? t(_bank) : null,
      chequeNumber: _method == 'Cheque' ? t(_cheque) : null,
      receiptPhoto: _receipt,
      note: t(_note),
      isAdvance: widget.existing?.isAdvance ?? false,
      applyExtraToNext: applyExtra,
      createdAt: widget.existing?.createdAt,
      editedAt: widget.existing?.editedAt,
    );
    try {
      if (_editing) {
        await app.editPayment(widget.existing!, p);
        if (widget.existing!.receiptPhoto != null && widget.existing!.receiptPhoto != _receipt) {
          await app.photos.delete(widget.existing!.receiptPhoto);
        }
      } else {
        await app.addPayment(p);
      }
      if (!mounted) return;
      Navigator.pop(context);
      final c = app.comp[widget.saleId]!;
      toast(
          context,
          _editing
              ? 'Payment updated - totals recalculated'
              : 'Saved ${money(amount)}. Remaining ${money(c.remaining)}'
                  '${c.status == SaleStatus.completed ? ' - sale completed!' : ''}');
    } catch (e, st) {
      AppLog.error('Save payment failed', e, st);
      if (mounted) {
        setState(() => _saving = false);
        toast(context, 'Could not save payment: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final sale = app.sale(widget.saleId);
    if (sale == null) return const SizedBox(height: 120, child: Center(child: Text('Sale not found')));
    final comp = app.comp[widget.saleId]!;
    final cu = app.customer(sale.customerId)!;
    final open = comp.installments.where((i) => i.isOpen || i.id == _instId).toList();
    final isAdvance = widget.existing?.isAdvance ?? false;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _form,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          children: [
            Text(_editing ? 'Edit Payment' : 'Collect Payment',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            Text('${cu.name} · ${app.item(sale.itemId)?.name ?? 'Item'} · Remaining ${money(comp.remaining)}',
                style: TextStyle(color: Theme.of(context).colorScheme.outline)),
            const SizedBox(height: 14),
            if (isAdvance)
              const InfoRow('Type', 'Advance / down payment')
            else
              DropdownButtonFormField<int?>(
                initialValue: open.any((i) => i.id == _instId) ? _instId : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Installment'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Oldest unpaid first (auto)')),
                  for (final i in open)
                    DropdownMenuItem<int?>(
                      value: i.id,
                      child: Text(
                        'Installment ${i.number} - Due ${fmtDateShort(i.dueDate)} - ${money(i.remaining)}'
                        '${i.skipped ? ' (skipped)' : ''}${i.daysLate(app.today) > 0 && !i.skipped ? ' (late)' : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _instId = v;
                  if (!_editing) _amount.text = '${_dueFor(v) ?? ''}';
                }),
              ),
            const SizedBox(height: 12),
            MoneyField(
              controller: _amount,
              label: 'Amount paid',
              required: true,
              helper: 'Full, partial or extra',
              extraValidator: (v) => v != null && v <= 0 ? 'Must be more than 0' : null,
            ),
            const SizedBox(height: 12),
            DateField(label: 'Payment date', value: _date, onChanged: (d) => setState(() => _date = d)),
            const SizedBox(height: 12),
            Text('Payment method', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 0, children: [
              for (final m in {...app.paymentMethods, _method})
                ChoiceChip(label: Text(m), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
            ]),
            if (_method == 'Bank Transfer' || _method == 'Cheque') ...[
              const SizedBox(height: 10),
              TextFormField(controller: _bank, textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Bank name (optional)')),
            ],
            if (_method == 'Bank Transfer' || _method == 'JazzCash' || _method == 'Easypaisa') ...[
              const SizedBox(height: 10),
              TextFormField(controller: _txn, decoration: const InputDecoration(labelText: 'Transaction ID (optional)')),
            ],
            if (_method == 'Cheque') ...[
              const SizedBox(height: 10),
              TextFormField(controller: _cheque, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Cheque number')),
            ],
            const SizedBox(height: 10),
            TextFormField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Note', hintText: 'e.g. Paid late, promised on time next'),
            ),
            const SizedBox(height: 10),
            Row(children: [
              if (_receipt != null) ...[
                PhotoThumb(_receipt!, size: 56, caption: 'Receipt'),
                const SizedBox(width: 8),
                TextButton(onPressed: () => setState(() => _receipt = null), child: const Text('Remove')),
              ] else
                OutlinedButton.icon(
                  onPressed: () async {
                    final p = await pickAndStorePhoto(context, title: 'Receipt / proof photo');
                    if (p != null) setState(() => _receipt = p);
                  },
                  icon: const Icon(Icons.receipt_outlined),
                  label: const Text('Receipt photo (optional)'),
                ),
            ]),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check),
              label: Text(_editing ? 'Save Changes' : 'Save Payment'),
            ),
          ],
        ),
      ),
    );
  }
}
