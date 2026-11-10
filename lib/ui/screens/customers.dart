import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_log.dart';
import '../../core/format.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../logic/schedule.dart';
import '../../services/contact.dart';
import '../../services/exporter.dart';
import '../lock.dart';
import '../theme.dart';
import '../widgets.dart';
import 'collect_payment.dart';
import 'payments.dart';
import 'sales.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  String _q = '';
  CustomerStatus? _status;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final list = app.customers.where((c) => matchesQuery(_q, [c.name, c.phone, c.altPhone, c.cnic])).map((c) {
      return (c, app.customerSummary(c.id!));
    }).where((t) => _status == null || t.$2.status == _status).toList();

    return Scaffold(
      appBar: AppBar(title: Text('Customers (${app.customers.length})')),
      body: Column(children: [
        SearchBox(hint: 'Search name, phone, CNIC', onChanged: (v) => setState(() => _q = v)),
        ChoiceChips<CustomerStatus?>(
          values: const [null, CustomerStatus.good, CustomerStatus.late, CustomerStatus.skipped, CustomerStatus.completed],
          selected: _status,
          label: (s) => s == null ? 'All' : customerStatusLabel(s),
          onSelected: (s) => setState(() => _status = s),
        ),
        Expanded(
          child: list.isEmpty
              ? EmptyState(
                  icon: Icons.people_outline,
                  text: app.customers.isEmpty ? 'No customers yet' : 'No customers match',
                  action: app.customers.isEmpty
                      ? FilledButton.icon(
                          onPressed: () =>
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerForm())),
                          icon: const Icon(Icons.person_add_alt_1),
                          label: const Text('Add Customer'))
                      : null,
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final (c, s) = list[i];
                    final letter = c.name.isEmpty ? '' : c.name[0].toUpperCase();
                    final showLetter = i == 0 || list[i - 1].$1.name.toUpperCase().substring(0, 1) != letter;
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (showLetter && _q.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 10, 0, 2),
                          child: Text(letter,
                              style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800)),
                        ),
                      _CustomerCard(c, s),
                    ]);
                  },
                ),
        ),
      ]),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  final Customer c;
  final CustomerSummary s;
  const _CustomerCard(this.c, this.s);

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          leading: PersonAvatar(name: c.name, photo: c.photo),
          title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          subtitle: Text('${c.phone}\nActive sales: ${s.activeSales} · Pending: ${money(s.pending)}'),
          isThreeLine: true,
          trailing: StatusChip(customerStatusLabel(s.status), customerStatusColor(s.status), dense: true),
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => CustomerDetailScreen(customerId: c.id!))),
        ),
      );
}

// ---------------------------------------------------------------------------

class CustomerForm extends StatefulWidget {
  final Customer? existing;

  /// When true, pops with the new customer's id (used by the sale wizard).
  final bool returnId;
  const CustomerForm({super.key, this.existing, this.returnId = false});
  @override
  State<CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends State<CustomerForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _phone = TextEditingController(text: widget.existing?.phone);
  late final _alt = TextEditingController(text: widget.existing?.altPhone);
  late final _cnic = TextEditingController(text: widget.existing?.cnic);
  late final _address = TextEditingController(text: widget.existing?.address);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  late final _gName = TextEditingController(text: widget.existing?.guarantorName);
  late final _gPhone = TextEditingController(text: widget.existing?.guarantorPhone);
  late String? _photo = widget.existing?.photo;
  bool _saving = false;

  String? _t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final app = context.read<AppState>();
    try {
      final id = await app.saveCustomer(Customer(
        id: widget.existing?.id,
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        altPhone: _t(_alt),
        cnic: _t(_cnic),
        address: _t(_address),
        photo: _photo,
        notes: _t(_notes),
        guarantorName: _t(_gName),
        guarantorPhone: _t(_gPhone),
        createdAt: widget.existing?.createdAt,
      ));
      if (widget.existing?.photo != null && widget.existing!.photo != _photo) {
        await app.photos.delete(widget.existing!.photo);
      }
      if (mounted) Navigator.pop(context, widget.returnId ? id : null);
    } catch (e, st) {
      AppLog.error('Save customer failed', e, st);
      if (mounted) toast(context, 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final duplicate = widget.existing == null
        ? context.read<AppState>().customers.where((c) =>
            _phone.text.trim().length >= 7 &&
            c.phone.replaceAll(RegExp(r'\D'), '') == _phone.text.replaceAll(RegExp(r'\D'), ''))
        : const <Customer>[];
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Add Customer' : 'Edit Customer')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Center(
            child: GestureDetector(
              onTap: () async {
                final p = await pickAndStorePhoto(context, title: 'Customer photo');
                if (p != null) setState(() => _photo = p);
              },
              child: Stack(children: [
                PersonAvatar(name: _name.text.isEmpty ? '+' : _name.text, photo: _photo, radius: 44),
                const Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(radius: 15, child: Icon(Icons.camera_alt, size: 16)),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Full name *', prefixIcon: Icon(Icons.person_outline)),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Name is required' : null,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
                labelText: 'Phone number *', hintText: '03xx-xxxxxxx', prefixIcon: Icon(Icons.phone_outlined)),
            validator: (v) {
              final d = (v ?? '').replaceAll(RegExp(r'\D'), '');
              if (d.isEmpty) return 'Phone is required';
              if (d.length < 7) return 'Phone looks too short';
              return null;
            },
            onChanged: (_) => setState(() {}),
          ),
          if (duplicate.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text('Note: ${duplicate.first.name} already has this number',
                  style: const TextStyle(color: accentGold, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _alt,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Alternate phone', prefixIcon: Icon(Icons.phone_forwarded_outlined)),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _cnic,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'CNIC number (recommended)', hintText: '35202-1234567-1', prefixIcon: Icon(Icons.badge_outlined)),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _address,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Address (home / shop)', prefixIcon: Icon(Icons.home_outlined)),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _notes,
            maxLines: 3,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Notes', hintText: 'e.g. Works at shop in main bazaar, reliable', prefixIcon: Icon(Icons.notes)),
          ),
          const SizedBox(height: 20),
          Text('Guarantor (optional)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextFormField(
            controller: _gName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Guarantor name', prefixIcon: Icon(Icons.shield_outlined)),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _gPhone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Guarantor phone', prefixIcon: Icon(Icons.phone_outlined)),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check),
            label: const Text('Save Customer'),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class CustomerDetailScreen extends StatelessWidget {
  final int customerId;
  const CustomerDetailScreen({super.key, required this.customerId});

  Future<void> _export(BuildContext context, Customer c, bool pdf) async {
    final app = context.read<AppState>();
    try {
      final f = pdf ? await customerLedgerPdf(app, c) : await customerLedgerCsv(app, c);
      await AppLockController.instance.whileExternal(() => shareFile(f, 'Ledger - ${c.name}'));
    } catch (e, st) {
      AppLog.error('Ledger export failed', e, st);
      if (context.mounted) toast(context, 'Export failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = app.customer(customerId);
    if (c == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.person_off, text: 'Customer was deleted'));
    }
    final sum = app.customerSummary(customerId);
    final sales = app.salesFor(customerId);
    final timeline = _timeline(app, customerId);

    return Scaffold(
      appBar: AppBar(
        title: Text(c.name),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerForm(existing: c))),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'pdf') return _export(context, c, true);
              if (v == 'csv') return _export(context, c, false);
              if (v == 'delete') {
                final ok = await confirm(context,
                    title: 'Delete ${c.name}?',
                    message: 'This deletes the customer, all ${sales.length} sales, '
                        'schedules and payments. This cannot be undone.',
                    confirmLabel: 'Delete',
                    danger: true);
                if (ok && context.mounted) {
                  await app.deleteCustomer(customerId);
                  if (context.mounted) Navigator.pop(context);
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('Export ledger (PDF)')),
              PopupMenuItem(value: 'csv', child: Text('Export ledger (Excel / CSV)')),
              PopupMenuItem(value: 'delete', child: Text('Delete customer')),
            ],
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                PersonAvatar(name: c.name, photo: c.photo, radius: 32),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    Text(c.phone, style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 4),
                    StatusChip(customerStatusLabel(sum.status), customerStatusColor(sum.status), dense: true),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                      onPressed: () => callPhone(context, c.phone),
                      icon: const Icon(Icons.call),
                      label: const Text('Call')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1DA851)),
                      onPressed: () => openWhatsApp(context, c.phone, 'Assalam-o-Alaikum ${c.name}, '),
                      icon: const Icon(Icons.chat),
                      label: const Text('WhatsApp')),
                ),
              ]),
              const Divider(height: 24),
              if (c.altPhone != null) InfoRow('Alt. phone', c.altPhone!, icon: Icons.phone_forwarded_outlined),
              if (c.cnic != null) InfoRow('CNIC', c.cnic!, icon: Icons.badge_outlined),
              if (c.address != null) InfoRow('Address', c.address!, icon: Icons.home_outlined),
              if (c.guarantorName != null || c.guarantorPhone != null)
                InfoRow('Guarantor', [c.guarantorName, c.guarantorPhone].whereType<String>().join(' · '),
                    icon: Icons.shield_outlined),
              if (c.notes != null) InfoRow('Notes', c.notes!, icon: Icons.notes),
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
              StatCard(title: 'Total purchase', value: money(sum.totalPurchase), color: brandGreen, icon: Icons.shopping_bag_outlined),
              StatCard(title: 'Total paid', value: money(sum.totalPaid), color: StatusColors.paid, icon: Icons.check_circle_outline),
              StatCard(title: 'Pending / due', value: money(sum.pending), color: StatusColors.overdue, icon: Icons.hourglass_bottom),
              StatCard(
                  title: sum.nextDue == null ? 'Next due' : 'Next due ${fmtDateShort(sum.nextDue!.dueDate)}',
                  value: sum.nextDue == null ? '-' : money(sum.nextDue!.remaining),
                  color: accentGold,
                  icon: Icons.event),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: sales.isEmpty ? null : () => collectPaymentFlow(context, customerId: customerId),
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Collect Payment'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(48, 50)),
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => NewSaleWizard(customerId: customerId))),
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('New Sale'),
              ),
            ),
          ]),
        ),
        SectionHeader('Sales', count: sales.length),
        if (sales.isEmpty) const InlineEmpty('No sales yet'),
        ...sales.map((s) => SaleCard(s)),
        SectionHeader('Payment History'),
        if (timeline.isEmpty) const InlineEmpty('Nothing yet'),
        ...timeline,
      ]),
    );
  }

  /// Timeline: advance + payments + skipped installments, newest first.
  List<Widget> _timeline(AppState app, int customerId) {
    final rows = <(DateTime, Widget)>[];
    for (final p in app.paymentsForCustomer(customerId)) {
      rows.add((p.paymentDate, PaymentTile(p, showCustomer: false)));
    }
    for (final s in app.salesFor(customerId)) {
      for (final i in app.comp[s.id]!.installments.where((i) => i.status == InstStatus.skipped)) {
        rows.add((
          i.dueDate,
          ListTile(
            dense: true,
            leading: const CircleAvatar(
                radius: 16, backgroundColor: StatusColors.skipped, child: Icon(Icons.redo, size: 16, color: Colors.white)),
            title: Text('Installment ${i.number} - ${money(i.amount)} - Skipped'),
            subtitle: Text('${fmtDate(i.dueDate)} · ${app.item(s.itemId)?.name ?? ''}'),
          )
        ));
      }
    }
    rows.sort((a, b) => b.$1.compareTo(a.$1));
    return rows.map((r) => r.$2).toList();
  }
}
