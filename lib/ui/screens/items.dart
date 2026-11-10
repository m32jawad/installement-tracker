import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_log.dart';
import '../../core/format.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'sales.dart';

const itemCategories = ['Mobile Phone', 'Tablet', 'Laptop', 'Accessory', 'Other'];
const itemBrands = ['Apple', 'Samsung', 'Vivo', 'Oppo', 'Infinix', 'Tecno', 'Xiaomi', 'Realme', 'Nokia', 'Other'];

Color itemStatusColor(String s) => switch (s) {
      'sold' => StatusColors.partial,
      'reserved' => accentGold,
      _ => StatusColors.paid,
    };

String itemStatusLabel(String s) => switch (s) {
      'sold' => 'Sold',
      'reserved' => 'Reserved',
      _ => 'Available',
    };

class ItemsScreen extends StatefulWidget {
  /// When set, tapping an item pops with its id (sale wizard picker).
  final bool pickMode;
  const ItemsScreen({super.key, this.pickMode = false});
  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {
  String _q = '';
  late String _status = widget.pickMode ? 'available' : 'all';
  bool _grid = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final list = app.items
        .where((i) => _status == 'all' || i.status == _status)
        .where((i) => matchesQuery(_q, [i.name, i.brand, i.model, i.imei, i.category]))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pickMode ? 'Select Item' : 'Items / Stock'),
        actions: [
          IconButton(
            tooltip: _grid ? 'List view' : 'Grid view',
            icon: Icon(_grid ? Icons.view_list : Icons.grid_view),
            onPressed: () => setState(() => _grid = !_grid),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'addItem',
        onPressed: () async {
          final id = await Navigator.push<int>(
              context, MaterialPageRoute(builder: (_) => const ItemForm(returnId: true)));
          if (id != null && widget.pickMode && context.mounted) Navigator.pop(context, id);
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Item'),
      ),
      body: Column(children: [
        SearchBox(hint: 'Search name, brand, IMEI', onChanged: (v) => setState(() => _q = v)),
        ChoiceChips<String>(
          values: const ['available', 'sold', 'reserved', 'all'],
          selected: _status,
          label: (s) => s == 'all' ? 'All' : itemStatusLabel(s),
          onSelected: (s) => setState(() => _status = s),
        ),
        Expanded(
          child: list.isEmpty
              ? const EmptyState(icon: Icons.phone_android, text: 'No items here.\nTap Add Item to add a phone.')
              : _grid
                  ? GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.78),
                      itemCount: list.length,
                      itemBuilder: (_, i) => _ItemGridCard(list[i], onTap: () => _open(list[i])),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 96),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final it = list[i];
                        return Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                            leading: _ItemImage(it, size: 52),
                            title: Text(it.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text([
                              if (it.subtitle.isNotEmpty) it.subtitle,
                              if (it.imei != null) 'IMEI ${it.imei}',
                            ].join('\n')),
                            isThreeLine: it.subtitle.isNotEmpty && it.imei != null,
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(money(it.sellingPrice), style: const TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                StatusChip(itemStatusLabel(it.status), itemStatusColor(it.status), dense: true),
                              ],
                            ),
                            onTap: () => _open(it),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }

  void _open(Item it) {
    if (widget.pickMode) {
      Navigator.pop(context, it.id);
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => ItemDetailScreen(itemId: it.id!)));
    }
  }
}

class _ItemImage extends StatelessWidget {
  final Item it;
  final double size;
  const _ItemImage(this.it, {required this.size});
  @override
  Widget build(BuildContext context) {
    if (it.photos.isNotEmpty) {
      final f = context.read<AppState>().photos.file(it.photos.first);
      if (f.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(f, width: size, height: size, fit: BoxFit.cover, cacheWidth: (size * 3).toInt()),
        );
      }
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
      child: Icon(it.category == 'Laptop' ? Icons.laptop : Icons.phone_android,
          color: Theme.of(context).colorScheme.onPrimaryContainer),
    );
  }
}

class _ItemGridCard extends StatelessWidget {
  final Item it;
  final VoidCallback onTap;
  const _ItemGridCard(this.it, {required this.onTap});
  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: LayoutBuilder(builder: (_, c) => _ItemImage(it, size: c.maxWidth))),
              const SizedBox(height: 6),
              Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(money(it.sellingPrice)),
              const SizedBox(height: 4),
              StatusChip(itemStatusLabel(it.status), itemStatusColor(it.status), dense: true),
            ]),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------

class ItemForm extends StatefulWidget {
  final Item? existing;
  final bool returnId;
  const ItemForm({super.key, this.existing, this.returnId = false});
  @override
  State<ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends State<ItemForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _brand = TextEditingController(text: widget.existing?.brand);
  late final _model = TextEditingController(text: widget.existing?.model);
  late final _imei = TextEditingController(text: widget.existing?.imei);
  late final _desc = TextEditingController(text: widget.existing?.description);
  late final _cost = TextEditingController(
      text: (widget.existing?.purchaseCost ?? 0) > 0 ? '${widget.existing!.purchaseCost}' : '');
  late final _price = TextEditingController(
      text: (widget.existing?.sellingPrice ?? 0) > 0 ? '${widget.existing!.sellingPrice}' : '');
  late String _category = widget.existing?.category ?? 'Mobile Phone';
  late String _status = widget.existing?.status ?? 'available';
  late List<String> _photos = [...?widget.existing?.photos];
  bool _saving = false;

  String? _t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final app = context.read<AppState>();
    try {
      final id = await app.saveItem(Item(
        id: widget.existing?.id,
        name: _name.text.trim(),
        category: _category,
        brand: _t(_brand),
        model: _t(_model),
        imei: _t(_imei),
        description: _t(_desc),
        purchaseCost: parseAmount(_cost.text) ?? 0,
        sellingPrice: parseAmount(_price.text) ?? 0,
        photos: _photos,
        status: _status,
        createdAt: widget.existing?.createdAt,
      ));
      for (final old in widget.existing?.photos ?? const <String>[]) {
        if (!_photos.contains(old)) await app.photos.delete(old);
      }
      if (mounted) Navigator.pop(context, widget.returnId ? id : null);
    } catch (e, st) {
      AppLog.error('Save item failed', e, st);
      if (mounted) toast(context, 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final imeiDup = _imei.text.trim().length >= 6
        ? app.items.where((i) => i.id != widget.existing?.id && i.imei == _imei.text.trim()).toList()
        : const <Item>[];
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Add Item' : 'Edit Item')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: 'Item name *', hintText: 'e.g. iPhone 13 128GB', prefixIcon: Icon(Icons.phone_android)),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Name is required' : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: itemCategories.contains(_category) ? _category : 'Other',
            decoration: const InputDecoration(labelText: 'Category', prefixIcon: Icon(Icons.category_outlined)),
            items: itemCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) => setState(() => _category = v!),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _brand,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Brand', prefixIcon: Icon(Icons.sell_outlined)),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: -6, children: [
            for (final b in itemBrands)
              ChoiceChip(
                label: Text(b),
                selected: _brand.text == b,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() => _brand.text = b),
              ),
          ]),
          const SizedBox(height: 12),
          TextFormField(
            controller: _model,
            decoration: const InputDecoration(
                labelText: 'Model / variant', hintText: 'Colour, storage, RAM', prefixIcon: Icon(Icons.memory)),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _imei,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'IMEI / serial number', prefixIcon: Icon(Icons.qr_code_2)),
            onChanged: (_) => setState(() {}),
          ),
          if (imeiDup.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text('Warning: IMEI already used by "${imeiDup.first.name}"',
                  style: const TextStyle(color: StatusColors.overdue, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _desc,
            maxLines: 3,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Description', hintText: 'Condition, box, charger...', prefixIcon: Icon(Icons.notes)),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: MoneyField(controller: _cost, label: 'Purchase cost', helper: 'Private')),
            const SizedBox(width: 10),
            Expanded(child: MoneyField(controller: _price, label: 'Selling price')),
          ]),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Stock status', prefixIcon: Icon(Icons.inventory_2_outlined)),
            items: const ['available', 'reserved', 'sold']
                .map((s) => DropdownMenuItem(value: s, child: Text(itemStatusLabel(s))))
                .toList(),
            onChanged: (v) => setState(() => _status = v!),
          ),
          const SizedBox(height: 16),
          Text('Photos', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in _photos)
              Stack(children: [
                PhotoThumb(p),
                Positioned(
                  right: 0,
                  top: 0,
                  child: InkWell(
                    onTap: () => setState(() => _photos.remove(p)),
                    child: const CircleAvatar(radius: 12, backgroundColor: Colors.black54,
                        child: Icon(Icons.close, size: 14, color: Colors.white)),
                  ),
                ),
              ]),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () async {
                final p = await pickAndStorePhoto(context, title: 'Item photo');
                if (p != null) setState(() => _photos = [..._photos, p]);
              },
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).colorScheme.outline),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.add_a_photo_outlined),
              ),
            ),
          ]),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.check), label: const Text('Save Item')),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class ItemDetailScreen extends StatelessWidget {
  final int itemId;
  const ItemDetailScreen({super.key, required this.itemId});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final it = app.item(itemId);
    if (it == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.phone_android, text: 'Item was deleted'));
    }
    final history = app.salesForItem(itemId);
    return Scaffold(
      appBar: AppBar(
        title: Text(it.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemForm(existing: it))),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await confirm(context,
                  title: 'Delete ${it.name}?',
                  message: history.isEmpty
                      ? 'The item and its photos will be deleted.'
                      : 'This item is linked to ${history.length} sale(s). The sales stay, '
                          'but will no longer show the item.',
                  confirmLabel: 'Delete',
                  danger: true);
              if (ok && context.mounted) {
                await app.deleteItem(itemId);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        if (it.photos.isNotEmpty)
          SizedBox(
            height: 200,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              children: [
                for (final p in it.photos)
                  Padding(padding: const EdgeInsets.only(right: 8), child: PhotoThumb(p, size: 176, caption: it.name)),
              ],
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(money(it.sellingPrice),
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))),
                StatusChip(itemStatusLabel(it.status), itemStatusColor(it.status)),
              ]),
              const SizedBox(height: 8),
              InfoRow('Category', it.category),
              if (it.brand != null) InfoRow('Brand', it.brand!),
              if (it.model != null) InfoRow('Model', it.model!),
              if (it.imei != null) InfoRow('IMEI / Serial', it.imei!),
              if (it.description != null) InfoRow('Description', it.description!),
              if (it.purchaseCost > 0) ...[
                InfoRow('Purchase cost', money(it.purchaseCost)),
                InfoRow('Margin', money(it.sellingPrice - it.purchaseCost)),
              ],
              InfoRow('Added', fmtDate(it.createdAt)),
            ]),
          ),
        ),
        if (it.status != 'sold')
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NewSaleWizard(itemId: itemId))),
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('Sell on installments'),
            ),
          ),
        SectionHeader('History', count: history.length),
        if (history.isEmpty) const InlineEmpty('Not sold yet'),
        for (final s in history)
          ListTile(
            leading: const Icon(Icons.history),
            title: Text('Sold to ${app.customer(s.customerId)?.name ?? 'customer'} on ${fmtDate(s.saleDate)}'),
            subtitle: Text('${money(s.totalPrice)} · ${s.cancelled ? 'Cancelled' : 'Installments'}'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: s.id!))),
          ),
      ]),
    );
  }
}
