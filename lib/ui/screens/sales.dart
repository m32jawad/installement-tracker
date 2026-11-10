import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_log.dart';
import '../../core/format.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../logic/schedule.dart';
import '../theme.dart';
import '../widgets.dart';
import 'collect_payment.dart';
import 'customers.dart';
import 'due_tile.dart';
import 'items.dart';
import 'payments.dart';

enum SaleSort { nextDue, amount, name, newest }

const _sortLabels = {
  SaleSort.nextDue: 'Due date (nearest first)',
  SaleSort.amount: 'Pending amount (high to low)',
  SaleSort.name: 'Customer name A-Z',
  SaleSort.newest: 'Newest sale first',
};

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});
  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  String _q = '';
  SaleStatus? _status;
  SaleSort _sort = SaleSort.nextDue;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final list = app.sales.where((s) {
      final c = app.comp[s.id]!;
      if (_status != null && c.status != _status) return false;
      final cu = app.customer(s.customerId);
      final it = app.item(s.itemId);
      return matchesQuery(_q, [cu?.name, cu?.phone, cu?.cnic, it?.name, it?.imei]);
    }).toList();
    int far(Sale s) => app.comp[s.id]!.nextDue?.dueDate.millisecondsSinceEpoch ?? 1 << 62;
    switch (_sort) {
      case SaleSort.nextDue:
        list.sort((a, b) => far(a).compareTo(far(b)));
      case SaleSort.amount:
        list.sort((a, b) => app.comp[b.id]!.remaining.compareTo(app.comp[a.id]!.remaining));
      case SaleSort.name:
        list.sort((a, b) => (app.customer(a.customerId)?.name ?? '')
            .toLowerCase()
            .compareTo((app.customer(b.customerId)?.name ?? '').toLowerCase()));
      case SaleSort.newest:
        list.sort((a, b) => b.saleDate.compareTo(a.saleDate));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('Sales (${app.sales.length})'),
        actions: [
          PopupMenuButton<SaleSort>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (s) => setState(() => _sort = s),
            itemBuilder: (_) =>
                SaleSort.values.map((s) => PopupMenuItem(value: s, child: Text(_sortLabels[s]!))).toList(),
          ),
        ],
      ),
      body: Column(children: [
        SearchBox(hint: 'Search customer, item, IMEI, CNIC', onChanged: (v) => setState(() => _q = v)),
        ChoiceChips<SaleStatus?>(
          values: const [null, SaleStatus.active, SaleStatus.overdue, SaleStatus.completed, SaleStatus.cancelled],
          selected: _status,
          label: (s) => s == null ? 'All' : saleStatusLabel(s),
          onSelected: (s) => setState(() => _status = s),
        ),
        Expanded(
          child: list.isEmpty
              ? EmptyState(
                  icon: Icons.receipt_long_outlined,
                  text: app.sales.isEmpty ? 'No sales yet' : 'No sales match',
                  action: app.sales.isEmpty
                      ? FilledButton.icon(
                          onPressed: () =>
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const NewSaleWizard())),
                          icon: const Icon(Icons.add_shopping_cart),
                          label: const Text('New Sale'))
                      : null)
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: list.length,
                  itemBuilder: (_, i) => SaleCard(list[i]),
                ),
        ),
      ]),
    );
  }
}

class SaleCard extends StatelessWidget {
  final Sale s;
  const SaleCard(this.s, {super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final c = app.comp[s.id]!;
    final cu = app.customer(s.customerId);
    final it = app.item(s.itemId);
    final next = c.nextDue;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: s.id!))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              PersonAvatar(name: cu?.name ?? '?', photo: cu?.photo, radius: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(cu?.name ?? 'Customer', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  Text(it?.name ?? 'Item', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                ]),
              ),
              StatusChip(saleStatusLabel(c.status), saleStatusColor(c.status), dense: true),
            ]),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: c.progress,
                minHeight: 8,
                color: StatusColors.paid,
                backgroundColor: StatusColors.paid.withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(alignment: WrapAlignment.spaceBetween, spacing: 12, runSpacing: 2, children: [
              Text('Paid ${money(c.totalPaid)} / ${money(s.totalPrice)}', style: const TextStyle(fontSize: 13)),
              if (next != null)
                Text('Next: ${money(next.remaining)} · ${fmtDateShort(next.dueDate)}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: next.daysLate(app.today) > 0 ? StatusColors.overdue : null)),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// New sale wizard (spec 3.4)
// ---------------------------------------------------------------------------

class NewSaleWizard extends StatefulWidget {
  final int? customerId;
  final int? itemId;

  /// When set, edits the plan of an existing sale instead of creating one.
  final Sale? editing;
  const NewSaleWizard({super.key, this.customerId, this.itemId, this.editing});
  @override
  State<NewSaleWizard> createState() => _NewSaleWizardState();
}

class _NewSaleWizardState extends State<NewSaleWizard> {
  int _step = 0;
  int? _customerId;
  int? _itemId;
  String _custQ = '';
  String _itemQ = '';
  final _planForm = GlobalKey<FormState>();
  final _total = TextEditingController();
  final _advance = TextEditingController();
  final _monthly = TextEditingController();
  final _count = TextEditingController();
  final _customDays = TextEditingController(text: '30');
  final _notes = TextEditingController();
  bool _autoCount = true;
  Frequency _freq = Frequency.monthly;
  late DateTime _saleDate;
  late DateTime _firstDue;
  String _advMethod = 'Cash';
  final List<SecurityDoc> _docs = [];
  bool _saving = false;

  bool get _editing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    final e = widget.editing;
    _customerId = e?.customerId ?? widget.customerId;
    _itemId = e?.itemId ?? widget.itemId;
    _saleDate = e?.saleDate ?? app.today;
    _firstDue = e?.firstDueDate ?? _defaultFirstDue(app, _saleDate);
    if (e != null) {
      _total.text = '${e.totalPrice}';
      _advance.text = '${e.advanceAmount}';
      _monthly.text = '${e.monthlyAmount}';
      _count.text = '${e.totalInstallments}';
      _autoCount = autoInstallmentCount(e.totalPrice - e.advanceAmount, e.monthlyAmount) == e.totalInstallments;
      _freq = e.frequency;
      _customDays.text = '${e.customDays}';
      _advMethod = e.advanceMethod;
      _notes.text = e.notes ?? '';
      _step = 2;
    } else if (_itemId != null) {
      final it = app.item(_itemId);
      if (it != null && it.sellingPrice > 0) _total.text = '${it.sellingPrice}';
    }
    if (e == null) {
      if (_customerId != null) _step = 1;
      if (_customerId != null && _itemId != null) _step = 2;
    }
  }

  DateTime _defaultFirstDue(AppState app, DateTime saleDate) {
    final next = addMonths(saleDate, 1);
    final day = app.defaultDueDay;
    if (day >= 1 && day <= 28) return DateTime(next.year, next.month, day);
    return next;
  }

  int? get _countValue => _autoCount ? null : parseAmount(_count.text);

  (List<ScheduledInstallment>?, String?) _preview() {
    final total = parseAmount(_total.text);
    final adv = parseAmount(_advance.text) ?? 0;
    final m = parseAmount(_monthly.text);
    if (total == null || m == null) return (null, null);
    try {
      return (
        generateSchedule(
          total: total,
          advance: adv,
          installmentAmount: m,
          count: _countValue,
          firstDue: _firstDue,
          frequency: _freq,
          customDays: parseAmount(_customDays.text) ?? 30,
        ),
        null
      );
    } on PlanError catch (e) {
      return (null, e.message);
    }
  }

  Sale _buildSale(List<ScheduledInstallment> sched) => Sale(
        id: widget.editing?.id,
        customerId: _customerId!,
        itemId: _itemId,
        saleDate: _saleDate,
        totalPrice: parseAmount(_total.text)!,
        advanceAmount: parseAmount(_advance.text) ?? 0,
        advanceMethod: _advMethod,
        monthlyAmount: parseAmount(_monthly.text)!,
        totalInstallments: sched.length,
        frequency: _freq,
        customDays: parseAmount(_customDays.text) ?? 30,
        firstDueDate: _firstDue,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        createdAt: widget.editing?.createdAt,
      );

  Future<void> _create() async {
    final (sched, err) = _preview();
    if (sched == null) {
      toast(context, err ?? 'Check the payment plan');
      setState(() => _step = 2);
      return;
    }
    setState(() => _saving = true);
    final app = context.read<AppState>();
    try {
      final sale = _buildSale(sched);
      if (_editing) {
        await app.updateSalePlan(sale);
        if (mounted) {
          toast(context, 'Plan updated - schedule regenerated');
          Navigator.pop(context);
        }
      } else {
        final id = await app.createSale(sale, docs: _docs);
        if (mounted) {
          toast(context, 'Sale created - ${sched.length} installments scheduled');
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: id)));
        }
      }
    } catch (e, st) {
      AppLog.error('Create/update sale failed', e, st);
      if (mounted) toast(context, 'Could not save sale: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _next() {
    if (_step == 0 && _customerId == null) return toast(context, 'Select or add a customer');
    if (_step == 2) {
      if (!_planForm.currentState!.validate()) return;
      final (s, err) = _preview();
      if (s == null) return toast(context, err ?? 'Check the payment plan');
    }
    if (_editing && _step == 2) {
      setState(() => _step = 4);
      return;
    }
    if (_step < 4) setState(() => _step++);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit Payment Plan' : 'New Sale')),
      body: Stepper(
        currentStep: _step,
        onStepTapped: (i) {
          if (_editing && (i < 2 || i == 3)) return;
          if (i <= _step || (_customerId != null && i <= 2)) setState(() => _step = i);
        },
        onStepContinue: _step == 4 ? (_saving ? null : _create) : _next,
        onStepCancel: _step == 0 || (_editing && _step == 2) ? null : () => setState(() => _step--),
        controlsBuilder: (ctx, d) => Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Row(children: [
            Expanded(
              child: FilledButton(
                onPressed: d.onStepContinue,
                child: Text(_step == 4 ? (_editing ? 'Save Plan' : 'Create Sale') : 'Next'),
              ),
            ),
            if (d.onStepCancel != null) ...[
              const SizedBox(width: 10),
              OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(90, 50)),
                  onPressed: d.onStepCancel,
                  child: const Text('Back')),
            ],
          ]),
        ),
        steps: [
          Step(
            title: const Text('Customer'),
            subtitle: _customerId == null ? null : Text(app.customer(_customerId!)?.name ?? ''),
            isActive: _step >= 0,
            state: _customerId != null ? StepState.complete : StepState.indexed,
            content: _customerStep(app),
          ),
          Step(
            title: const Text('Item'),
            subtitle: _itemId == null ? const Text('Optional') : Text(app.item(_itemId)?.name ?? ''),
            isActive: _step >= 1,
            state: _itemId != null ? StepState.complete : StepState.indexed,
            content: _itemStep(app),
          ),
          Step(
            title: const Text('Payment plan'),
            isActive: _step >= 2,
            content: _planStep(app),
          ),
          Step(
            title: const Text('Security documents'),
            subtitle: Text(_editing ? 'Manage on the sale page' : '${_docs.length} added'),
            isActive: _step >= 3,
            content: _docsStep(),
          ),
          Step(
            title: const Text('Review & save'),
            isActive: _step >= 4,
            content: _reviewStep(app),
          ),
        ],
      ),
    );
  }

  Widget _customerStep(AppState app) {
    if (_customerId != null) {
      final c = app.customer(_customerId!)!;
      return Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: PersonAvatar(name: c.name, photo: c.photo),
          title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(c.phone),
          trailing: TextButton(onPressed: () => setState(() => _customerId = null), child: const Text('Change')),
        ),
      );
    }
    final matches =
        app.customers.where((c) => matchesQuery(_custQ, [c.name, c.phone, c.cnic])).take(6).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        decoration: const InputDecoration(hintText: 'Search existing customer', prefixIcon: Icon(Icons.search)),
        onChanged: (v) => setState(() => _custQ = v),
      ),
      ...matches.map((c) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: PersonAvatar(name: c.name, photo: c.photo, radius: 18),
            title: Text(c.name),
            subtitle: Text(c.phone),
            onTap: () => setState(() {
              _customerId = c.id;
              _step = 1;
            }),
          )),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () async {
          final id = await Navigator.push<int>(
              context, MaterialPageRoute(builder: (_) => const CustomerForm(returnId: true)));
          if (id != null) {
            setState(() {
              _customerId = id;
              _step = 1;
            });
          }
        },
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add New Customer'),
      ),
    ]);
  }

  void _selectItem(AppState app, int id) {
    setState(() {
      _itemId = id;
      final it = app.item(id);
      if (it != null && it.sellingPrice > 0 && _total.text.isEmpty) _total.text = '${it.sellingPrice}';
      _step = 2;
    });
  }

  Widget _itemStep(AppState app) {
    if (_itemId != null) {
      final it = app.item(_itemId)!;
      return Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: const Icon(Icons.phone_android, size: 32),
          title: Text(it.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text([money(it.sellingPrice), if (it.imei != null) 'IMEI ${it.imei}'].join(' · ')),
          trailing: _editing && !app.canEditPlan(widget.editing!.id!)
              ? null
              : TextButton(onPressed: () => setState(() => _itemId = null), child: const Text('Change')),
        ),
      );
    }
    final matches = app.items
        .where((i) => i.status != 'sold' || i.id == widget.editing?.itemId)
        .where((i) => matchesQuery(_itemQ, [i.name, i.brand, i.imei]))
        .take(6)
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        decoration: const InputDecoration(hintText: 'Search available items / IMEI', prefixIcon: Icon(Icons.search)),
        onChanged: (v) => setState(() => _itemQ = v),
      ),
      if (matches.isEmpty)
        const Padding(padding: EdgeInsets.all(8), child: Text('No available items. Add a new one below.')),
      ...matches.map((i) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.phone_android),
            title: Text(i.name),
            subtitle: Text([money(i.sellingPrice), if (i.imei != null) 'IMEI ${i.imei}'].join(' · ')),
            onTap: () => _selectItem(app, i.id!),
          )),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () async {
          final id = await Navigator.push<int>(
              context, MaterialPageRoute(builder: (_) => const ItemForm(returnId: true)));
          if (id != null) _selectItem(app, id);
        },
        icon: const Icon(Icons.add),
        label: const Text('Add New Item (photos, IMEI)'),
      ),
    ]);
  }

  Widget _planStep(AppState app) {
    final total = parseAmount(_total.text) ?? 0;
    final adv = parseAmount(_advance.text) ?? 0;
    final remaining = total - adv;
    final (sched, err) = _preview();
    void refresh(String _) => setState(() {});
    return Form(
      key: _planForm,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MoneyField(controller: _total, label: 'Total sale price', required: true, onChanged: refresh,
            extraValidator: (v) => v != null && v <= 0 ? 'Must be more than 0' : null),
        const SizedBox(height: 12),
        MoneyField(controller: _advance, label: 'Advance / down payment', required: true, onChanged: refresh,
            extraValidator: (v) => v != null && v > total ? 'More than total price' : null),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Text('Remaining amount'),
            const Spacer(),
            Text(money(remaining < 0 ? 0 : remaining), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ]),
        ),
        const SizedBox(height: 12),
        MoneyField(
            controller: _monthly,
            label: _freq == Frequency.monthly ? 'Monthly installment' : 'Installment amount',
            required: remaining > 0,
            onChanged: refresh),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextFormField(
              controller: _count,
              enabled: !_autoCount,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Number of installments',
                helperText: _autoCount ? 'Auto: ${sched?.length ?? '-'}' : null,
              ),
              onChanged: refresh,
            ),
          ),
          const SizedBox(width: 8),
          Column(children: [
            Switch(value: _autoCount, onChanged: (v) => setState(() {
              _autoCount = v;
              if (!v && sched != null) _count.text = '${sched.length}';
            })),
            const Text('Auto', style: TextStyle(fontSize: 12)),
          ]),
        ]),
        const SizedBox(height: 12),
        DropdownButtonFormField<Frequency>(
          initialValue: _freq,
          decoration: const InputDecoration(labelText: 'Installment frequency'),
          items: Frequency.values
              .map((f) => DropdownMenuItem(value: f, child: Text(f == Frequency.custom ? 'Custom (every N days)' : frequencyLabel(f))))
              .toList(),
          onChanged: (f) => setState(() => _freq = f!),
        ),
        if (_freq == Frequency.custom) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _customDays,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Every how many days?'),
            onChanged: refresh,
          ),
        ],
        const SizedBox(height: 12),
        DateField(
          label: 'Sale date *',
          value: _saleDate,
          onChanged: (d) => setState(() {
            final wasDefault = _firstDue == _defaultFirstDue(app, _saleDate);
            _saleDate = d;
            if (wasDefault) _firstDue = _defaultFirstDue(app, d);
          }),
        ),
        const SizedBox(height: 12),
        DateField(label: 'First installment due date *', value: _firstDue, onChanged: (d) => setState(() => _firstDue = d)),
        const SizedBox(height: 12),
        Text('Advance paid by', style: Theme.of(context).textTheme.labelLarge),
        Wrap(spacing: 6, children: [
          for (final m in app.paymentMethods)
            ChoiceChip(label: Text(m), selected: _advMethod == m, onSelected: (_) => setState(() => _advMethod = m)),
        ]),
        const SizedBox(height: 12),
        TextFormField(
          controller: _notes,
          maxLines: 2,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
              labelText: 'Notes', hintText: 'e.g. Customer promised to pay before 10th every month'),
        ),
        const SizedBox(height: 10),
        if (err != null)
          Text(err, style: const TextStyle(color: StatusColors.overdue, fontWeight: FontWeight.w600))
        else if (sched != null && sched.isNotEmpty)
          Text(
            '${sched.length} x ${money(sched.first.amount)}'
            '${sched.last.amount != sched.first.amount ? ' (last ${money(sched.last.amount)})' : ''}'
            ' · ends ${fmtDate(sched.last.dueDate)}',
            style: const TextStyle(fontWeight: FontWeight.w600, color: brandGreen),
          )
        else if (sched != null && sched.isEmpty && total > 0)
          const Text('Fully paid by advance - no installments', style: TextStyle(fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _docsStep() {
    if (_editing) return const Text('Add or remove documents from the Sale page.');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('CNIC copy, cheque, guarantor CNIC, signed agreement... Photos stay inside the app.'),
      const SizedBox(height: 8),
      ..._docs.map((d) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: PhotoThumb(d.photo, size: 48),
            title: Text(d.typeLabel),
            subtitle: Text([d.chequeNumber, d.bankName, d.note].whereType<String>().join(' · ')),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                context.read<AppState>().photos.delete(d.photo);
                setState(() => _docs.remove(d));
              },
            ),
          )),
      OutlinedButton.icon(
        onPressed: () async {
          final d = await showAddDocSheet(context, saleId: 0);
          if (d != null) setState(() => _docs.add(d));
        },
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Add Document Photo'),
      ),
    ]);
  }

  Widget _reviewStep(AppState app) {
    final (sched, err) = _preview();
    if (_customerId == null || sched == null) {
      return Text(err ?? 'Complete the customer and payment plan first.');
    }
    final c = app.customer(_customerId!)!;
    final it = app.item(_itemId);
    final s = _buildSale(sched);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InfoRow('Customer', c.name),
      InfoRow('Item', it?.name ?? '-'),
      InfoRow('Total', money(s.totalPrice)),
      InfoRow('Advance', '${money(s.advanceAmount)} (${s.advanceMethod})'),
      InfoRow('Remaining', money(s.totalPrice - s.advanceAmount)),
      InfoRow('Installment', '${money(s.monthlyAmount)} ${frequencyLabel(s.frequency, s.customDays).toLowerCase()}'),
      InfoRow('Total months', '${sched.length}'),
      InfoRow('Sale date', fmtDate(s.saleDate)),
      if (sched.isNotEmpty) InfoRow('First due', fmtDate(sched.first.dueDate)),
      if (sched.isNotEmpty) InfoRow('End date', fmtDate(sched.last.dueDate)),
      if (!_editing) InfoRow('Documents', '${_docs.length}'),
      if (_editing)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Saving regenerates the schedule. Skipped marks are cleared.',
              style: TextStyle(color: accentGold, fontWeight: FontWeight.w600)),
        ),
      const SizedBox(height: 8),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Schedule preview'),
        children: [
          for (final i in sched)
            Row(children: [
              SizedBox(width: 36, child: Text('#${i.number}')),
              Expanded(child: Text(fmtDate(i.dueDate))),
              Text(money(i.amount)),
            ]),
        ],
      ),
    ]);
  }
}

/// Bottom sheet to add one security document. [saleId] 0 = draft for the wizard.
Future<SecurityDoc?> showAddDocSheet(BuildContext context, {required int saleId}) async {
  String type = 'cnic_front';
  String? photo;
  final note = TextEditingController();
  final chequeNo = TextEditingController();
  final bank = TextEditingController();
  final chequeDate = TextEditingController();
  final result = await showModalBottomSheet<SecurityDoc>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Add security document', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 0, children: [
              for (final e in securityDocTypes.entries)
                ChoiceChip(label: Text(e.value), selected: type == e.key, onSelected: (_) => setS(() => type = e.key)),
            ]),
            const SizedBox(height: 10),
            if (photo != null)
              Center(child: PhotoThumb(photo!, size: 140))
            else
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(48, 90)),
                onPressed: () async {
                  final p = await pickAndStorePhoto(ctx, title: securityDocTypes[type]!);
                  if (p != null) setS(() => photo = p);
                },
                icon: const Icon(Icons.add_a_photo_outlined, size: 30),
                label: const Text('Take / choose photo *'),
              ),
            if (type == 'cheque') ...[
              const SizedBox(height: 10),
              TextField(controller: chequeNo, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cheque number')),
              const SizedBox(height: 10),
              TextField(controller: bank, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Bank name')),
              const SizedBox(height: 10),
              TextField(controller: chequeDate, decoration: const InputDecoration(labelText: 'Cheque date', hintText: 'e.g. 10 Dec 2026')),
            ],
            const SizedBox(height: 10),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)')),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: photo == null
                  ? null
                  : () => Navigator.pop(
                      ctx,
                      SecurityDoc(
                        saleId: saleId,
                        type: type,
                        photo: photo!,
                        note: note.text.trim().isEmpty ? null : note.text.trim(),
                        chequeNumber: chequeNo.text.trim().isEmpty ? null : chequeNo.text.trim(),
                        bankName: bank.text.trim().isEmpty ? null : bank.text.trim(),
                        chequeDate: chequeDate.text.trim().isEmpty ? null : chequeDate.text.trim(),
                      )),
              child: const Text('Add Document'),
            ),
          ]),
        ),
      ),
    ),
  );
  if (result == null && photo != null && context.mounted) {
    await context.read<AppState>().photos.delete(photo);
  }
  return result;
}

// ---------------------------------------------------------------------------
// Sale detail (spec 3.4 Sale Detail Page)
// ---------------------------------------------------------------------------

class SaleDetailScreen extends StatelessWidget {
  final int saleId;
  const SaleDetailScreen({super.key, required this.saleId});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.sale(saleId);
    if (s == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.receipt_long, text: 'Sale was deleted'));
    }
    final c = app.comp[saleId]!;
    final cu = app.customer(s.customerId)!;
    final it = app.item(s.itemId);
    final next = c.nextDue;
    final docs = app.docsBySale[saleId] ?? const [];
    final notes = app.notesBySale[saleId] ?? const [];
    final pays = app.paymentsForSale(saleId);

    return Scaffold(
      appBar: AppBar(
        title: Text(cu.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => _menu(context, v, s),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit sale')),
              const PopupMenuItem(value: 'note', child: Text('Add note')),
              PopupMenuItem(value: 'cancel', child: Text(s.cancelled ? 'Re-activate sale' : 'Cancel sale')),
              const PopupMenuItem(value: 'delete', child: Text('Delete sale')),
            ],
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (it != null && it.photos.isNotEmpty)
                  PhotoThumb(it.photos.first, size: 58, caption: it.name)
                else
                  PersonAvatar(name: cu.name, photo: cu.photo, radius: 29),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => CustomerDetailScreen(customerId: cu.id!))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(cu.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                      Text(it?.name ?? 'Item', style: const TextStyle(fontSize: 15)),
                      if (it?.imei != null)
                        Text('IMEI ${it!.imei}', style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12)),
                    ]),
                  ),
                ),
                StatusChip(saleStatusLabel(c.status), saleStatusColor(c.status)),
              ]),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: c.progress,
                  minHeight: 12,
                  color: StatusColors.paid,
                  backgroundColor: StatusColors.paid.withValues(alpha: 0.15),
                ),
              ),
              const SizedBox(height: 6),
              Text('Paid ${(c.progress * 100).round()}% - ${money(c.totalPaid)} / ${money(s.totalPrice)}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.0,
            children: [
              StatCard(title: 'Total price', value: money(s.totalPrice), color: brandGreen, icon: Icons.sell_outlined),
              StatCard(title: 'Paid so far', value: money(c.totalPaid), color: StatusColors.paid, icon: Icons.check_circle_outline),
              StatCard(title: 'Remaining', value: money(c.remaining), color: StatusColors.overdue, icon: Icons.hourglass_bottom),
              StatCard(
                title: next == null ? 'Next due' : 'Next due ${fmtDate(next.dueDate)}',
                value: next == null ? '-' : money(next.remaining),
                color: accentGold,
                icon: Icons.event,
              ),
            ],
          ),
        ),
        if (c.credit > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text('Includes ${money(c.credit)} extra kept as advance',
                style: const TextStyle(color: StatusColors.partial, fontWeight: FontWeight.w600)),
          ),
        if (!s.cancelled && c.status != SaleStatus.completed)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => showCollectPayment(context, saleId: saleId, installmentId: next?.id),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Collect Payment'),
                ),
              ),
              if (next != null) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(48, 50), foregroundColor: const Color(0xFF1DA851)),
                  onPressed: () => showReminderSheet(context, DueEntry(s, cu, it, next)),
                  icon: const Icon(Icons.chat),
                  label: const Text('Remind'),
                ),
              ],
            ]),
          ),
        SectionHeader('Installment Schedule', count: c.installments.length),
        const _Legend(),
        Card(
          child: Column(children: [
            for (final i in c.installments) _InstallmentRow(s, cu, it, i),
          ]),
        ),
        SectionHeader('Payments', count: pays.length),
        if (pays.isEmpty) const InlineEmpty('No payments yet'),
        ...pays.map((p) => PaymentTile(p, showCustomer: false)),
        SectionHeader('Security Documents',
            count: docs.length,
            trailing: TextButton.icon(
              onPressed: () async {
                final d = await showAddDocSheet(context, saleId: saleId);
                if (d != null) await app.addSecurityDoc(d);
              },
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Add'),
            )),
        if (docs.isEmpty) const InlineEmpty('No documents attached'),
        if (docs.isNotEmpty)
          SizedBox(
            height: 150,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final d in docs)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: SizedBox(
                      width: 104,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        PhotoThumb(d.photo, size: 104, caption: d.typeLabel, onLongPress: () async {
                          final ok = await confirm(context,
                              title: 'Delete ${d.typeLabel}?',
                              message: 'The photo will be removed from this sale.',
                              confirmLabel: 'Delete',
                              danger: true);
                          if (ok) await app.deleteSecurityDoc(d);
                        }),
                        Text(d.typeLabel, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        Text([d.chequeNumber, fmtDateShort(d.createdAt)].whereType<String>().join(' · '),
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
        if (docs.isNotEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Text('Tap to view full size · long-press to delete', style: TextStyle(fontSize: 12)),
          ),
        SectionHeader('Notes',
            trailing: TextButton.icon(
                onPressed: () => _menu(context, 'note', s), icon: const Icon(Icons.add), label: const Text('Add'))),
        if (s.notes != null) ListTile(leading: const Icon(Icons.sticky_note_2_outlined), title: Text(s.notes!)),
        for (final n in notes)
          ListTile(
            leading: const Icon(Icons.notes),
            title: Text(n.note),
            subtitle: Text(fmtDate(n.createdAt)),
            onLongPress: () async {
              if (await confirm(context, title: 'Delete note?', message: n.note, danger: true)) {
                await app.deleteSaleNote(n.id);
              }
            },
          ),
        if (s.notes == null && notes.isEmpty) const InlineEmpty('No notes'),
        SectionHeader('Plan'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            InfoRow('Sale date', fmtDate(s.saleDate)),
            InfoRow('Advance', '${money(s.advanceAmount)} (${s.advanceMethod})'),
            InfoRow('Installment', '${money(s.monthlyAmount)} · ${frequencyLabel(s.frequency, s.customDays)}'),
            InfoRow('Installments', '${s.totalInstallments}'),
            if (c.installments.isNotEmpty) InfoRow('End date', fmtDate(c.installments.last.dueDate)),
          ]),
        ),
      ]),
    );
  }

  Future<void> _menu(BuildContext context, String v, Sale s) async {
    final app = context.read<AppState>();
    switch (v) {
      case 'edit':
        if (app.canEditPlan(s.id!)) {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => NewSaleWizard(editing: s)));
        } else {
          final n = await promptText(context, title: 'Edit sale notes', initial: s.notes);
          if (n != null) await app.updateSaleNotes(s.id!, n.isEmpty ? null : n);
          if (context.mounted) {
            toast(context, 'Amounts are locked once installments are paid. Edit the payments instead.');
          }
        }
      case 'note':
        final n = await promptText(context, title: 'Add note', hint: 'e.g. Customer called, will pay Friday');
        if (n != null && n.isNotEmpty) await app.addSaleNote(s.id!, n);
      case 'cancel':
        final ok = await confirm(context,
            title: s.cancelled ? 'Re-activate sale?' : 'Cancel sale?',
            message: s.cancelled
                ? 'The schedule will count again in dashboard and reports.'
                : 'Cancelled sales are hidden from dues and reports. Payments are kept.');
        if (ok) await app.setSaleCancelled(s.id!, !s.cancelled);
      case 'delete':
        final ok = await confirm(context,
            title: 'Delete sale?',
            message: 'Deletes the schedule, all payments and documents of this sale. '
                'The item becomes available again. This cannot be undone.',
            confirmLabel: 'Delete',
            danger: true);
        if (ok) {
          await app.deleteSale(s.id!);
          if (context.mounted) Navigator.pop(context);
        }
    }
  }
}

class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Wrap(spacing: 10, runSpacing: 4, children: [
          _Dot(StatusColors.paid, 'Paid'),
          _Dot(StatusColors.pending, 'Pending'),
          _Dot(StatusColors.overdue, 'Overdue'),
          _Dot(StatusColors.skipped, 'Skipped'),
          _Dot(StatusColors.partial, 'Partial'),
        ]),
      );
}

class _Dot extends StatelessWidget {
  final Color c;
  final String t;
  const _Dot(this.c, this.t);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(t, style: const TextStyle(fontSize: 12)),
      ]);
}

class _InstallmentRow extends StatelessWidget {
  final Sale s;
  final Customer cu;
  final Item? it;
  final InstallmentState i;
  const _InstallmentRow(this.s, this.cu, this.it, this.i);

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final color = instStatusColor(i.status);
    final late = i.daysLate(app.today);
    final reason = i.skipped ? app.installment(i.id)?.skipReason : null;
    return InkWell(
      onTap: s.cancelled ? null : () => _actions(context),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: color, width: 4),
            bottom: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.4)),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        child: Row(children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Text('${i.number}', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(fmtDate(i.dueDate), style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                [
                  if (i.paidDate != null && i.paid > 0) 'Paid ${fmtDateShort(i.paidDate!)} · ${i.method}',
                  if (i.status == InstStatus.partial) '${money(i.remaining)} still due',
                  if (late > 0 && !i.skipped) daysLateLabel(late),
                  if (reason != null) reason,
                ].join(' · '),
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
              ),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(money(i.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            StatusChip(instStatusLabel(i.status), color, dense: true),
          ]),
        ]),
      ),
    );
  }

  Future<void> _actions(BuildContext context) async {
    final app = context.read<AppState>();
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Installment ${i.number} · ${fmtDate(i.dueDate)} · ${money(i.amount)}',
              style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 6),
          if (i.isOpen)
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: Text('Collect ${money(i.remaining)}'),
              onTap: () {
                Navigator.pop(ctx);
                showCollectPayment(context, saleId: s.id!, installmentId: i.id);
              },
            ),
          if (i.isOpen && !i.skipped)
            ListTile(
              leading: const Icon(Icons.redo),
              title: const Text('Mark as Skipped'),
              onTap: () {
                Navigator.pop(ctx);
                markSkippedFlow(context, i.id);
              },
            ),
          if (i.skipped && i.isOpen)
            ListTile(
              leading: const Icon(Icons.undo),
              title: const Text('Un-skip'),
              onTap: () async {
                Navigator.pop(ctx);
                await app.setSkipped(i.id, false);
              },
            ),
          if (i.isOpen)
            ListTile(
              leading: const Icon(Icons.chat_outlined, color: Color(0xFF25D366)),
              title: const Text('Send reminder'),
              onTap: () {
                Navigator.pop(ctx);
                showReminderSheet(context, DueEntry(s, cu, it, i));
              },
            ),
          if (!i.isOpen)
            const ListTile(leading: Icon(Icons.check_circle, color: StatusColors.paid), title: Text('Fully paid')),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}
