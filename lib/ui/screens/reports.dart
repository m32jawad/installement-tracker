import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_log.dart';
import '../../core/format.dart';
import '../../data/app_state.dart';
import '../../logic/schedule.dart';
import '../../services/exporter.dart';
import '../lock.dart';
import '../theme.dart';
import '../widgets.dart';
import 'customers.dart';
import 'due_tile.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);
  late DateTime _month;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    final t = context.read<AppState>().today;
    _month = DateTime(t.year, t.month);
  }

  Future<void> _exportPdf() async {
    setState(() => _exporting = true);
    final app = context.read<AppState>();
    try {
      final f = await monthlyReportPdf(app, _month);
      await AppLockController.instance
          .whileExternal(() => shareFile(f, 'Monthly report ${fmtMonth(_month)} - ${app.shopName}'));
    } catch (e, st) {
      AppLog.error('Monthly PDF export failed', e, st);
      if (mounted) toast(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Reports'),
          actions: [
            IconButton(
              tooltip: 'Export monthly report (PDF)',
              onPressed: _exporting ? null : _exportPdf,
              icon: _exporting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.picture_as_pdf_outlined),
            ),
          ],
          bottom: TabBar(
            controller: _tabs,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: const [Tab(text: 'Monthly'), Tab(text: 'Overall')],
          ),
        ),
        body: TabBarView(controller: _tabs, children: [
          _monthly(context),
          const _Overall(),
        ]),
      );

  Widget _monthly(BuildContext context) {
    final app = context.watch<AppState>();
    final entries = app.dueInMonth(_month);
    final byMethod = app.collectedByMethod(_month).entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final collected = app.collectedInMonth(_month);
    final paid = entries.where((e) => e.inst.status == InstStatus.paid).toList();
    final skipped = entries.where((e) => e.inst.status == InstStatus.skipped).toList();
    final overdue = entries.where((e) => e.inst.isOpen && !e.inst.skipped && e.inst.daysLate(app.today) > 0).toList();
    final pending = entries.where((e) => e.inst.isOpen && !e.inst.skipped && e.inst.daysLate(app.today) == 0).toList();

    return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: Row(children: [
          IconButton(onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)), icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: Text(fmtMonth(_month),
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          ),
          IconButton(onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)), icon: const Icon(Icons.chevron_right)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 6,
          childAspectRatio: 1.15,
          children: [
            StatCard(title: 'Collected', value: money(collected), color: StatusColors.paid, icon: Icons.check_circle_outline),
            StatCard(title: 'Expected', value: money(app.expectedInMonth(_month)), color: brandGreen, icon: Icons.calendar_month),
            StatCard(title: 'Pending / Missed', value: money(app.pendingInMonth(_month)), color: StatusColors.overdue, icon: Icons.warning_amber),
          ],
        ),
      ),
      if (byMethod.isNotEmpty) ...[
        const SectionHeader('Collected by method'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              for (final e in byMethod)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    SizedBox(width: 110, child: Text(e.key)),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: collected == 0 ? 0 : e.value / collected,
                          minHeight: 10,
                          color: brandGreen,
                          backgroundColor: brandGreen.withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(money(e.value), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                ),
            ]),
          ),
        ),
      ],
      SectionHeader('Overdue', count: overdue.length, color: StatusColors.overdue),
      if (overdue.isEmpty) const InlineEmpty('None'),
      ...overdue.map((e) => DueTile(e)),
      SectionHeader('Skipped', count: skipped.length, color: StatusColors.skipped),
      if (skipped.isEmpty) const InlineEmpty('None'),
      ...skipped.map((e) => DueTile(e, actions: false)),
      SectionHeader('Still to come', count: pending.length, color: accentGold),
      if (pending.isEmpty) const InlineEmpty('None'),
      ...pending.map((e) => DueTile(e)),
      SectionHeader('Paid', count: paid.length, color: StatusColors.paid),
      if (paid.isEmpty) const InlineEmpty('None'),
      ...paid.map((e) => DueTile(e, actions: false)),
      Padding(
        padding: const EdgeInsets.all(16),
        child: OutlinedButton.icon(
          onPressed: _exporting ? null : _exportPdf,
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Export & share this month as PDF'),
        ),
      ),
    ]);
  }
}

class _Overall extends StatelessWidget {
  const _Overall();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    // Customer-wise: late payments = installments paid after due + currently overdue.
    final custStats = <int, (int late, int onTime)>{};
    for (final e in app.allInstallments()) {
      final id = e.customer.id!;
      final cur = custStats[id] ?? (0, 0);
      final late = e.inst.paidLate || (e.inst.isOpen && !e.inst.skipped && e.inst.daysLate(app.today) > 0) ||
          (e.inst.skipped && e.inst.isOpen);
      final onTime = !e.inst.isOpen && !e.inst.paidLate;
      custStats[id] = (cur.$1 + (late ? 1 : 0), cur.$2 + (onTime ? 1 : 0));
    }
    final best = custStats.entries.where((e) => e.value.$2 > 0).toList()
      ..sort((a, b) => (b.value.$2 - b.value.$1 * 2).compareTo(a.value.$2 - a.value.$1 * 2));
    final worst = custStats.entries.where((e) => e.value.$1 > 0).toList()
      ..sort((a, b) => b.value.$1.compareTo(a.value.$1));

    // Item-wise: count sales per item name (brand + name).
    final itemCounts = <String, (int count, int value)>{};
    for (final s in app.sales.where((s) => !s.cancelled)) {
      final name = app.item(s.itemId)?.name ?? 'Unknown item';
      final cur = itemCounts[name] ?? (0, 0);
      itemCounts[name] = (cur.$1 + 1, cur.$2 + s.totalPrice);
    }
    final topItems = itemCounts.entries.toList()..sort((a, b) => b.value.$1.compareTo(a.value.$1));

    return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.75,
          children: [
            StatCard(title: 'Total sales (all time)', value: money(app.totalSalesValue()), color: brandGreen, icon: Icons.shopping_bag_outlined),
            StatCard(title: 'Total collected', value: money(app.totalCollected()), color: StatusColors.paid, icon: Icons.check_circle_outline),
            StatCard(title: 'Outstanding', value: money(app.totalOutstanding()), color: StatusColors.overdue, icon: Icons.hourglass_bottom),
            StatCard(
              title: app.showProfit ? 'Profit (private)' : 'Profit (tap to show)',
              value: app.showProfit ? money(app.totalProfit()) : '••••••',
              color: accentGold,
              icon: app.showProfit ? Icons.visibility : Icons.visibility_off,
              onTap: () => app.setSetting('show_profit', app.showProfit ? '0' : '1'),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          '${app.sales.where((s) => !s.cancelled).length} sales · ${app.customers.length} customers · '
          '${app.items.where((i) => i.status == 'available').length} items in stock',
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      const SectionHeader('Best payers'),
      if (best.isEmpty) const InlineEmpty('Not enough payments yet'),
      for (final e in best.take(5)) _custRow(context, app, e.key, '${e.value.$2} on time · ${e.value.$1} late', StatusColors.paid),
      const SectionHeader('Most late', color: StatusColors.overdue),
      if (worst.isEmpty) const InlineEmpty('No late customers'),
      for (final e in worst.take(5)) _custRow(context, app, e.key, '${e.value.$1} late / skipped', StatusColors.overdue),
      const SectionHeader('Top items on installments'),
      if (topItems.isEmpty) const InlineEmpty('No sales yet'),
      for (final e in topItems.take(8))
        ListTile(
          leading: CircleAvatar(child: Text('${e.value.$1}')),
          title: Text(e.key),
          subtitle: Text('${e.value.$1} sold · ${money(e.value.$2)}'),
        ),
    ]);
  }

  Widget _custRow(BuildContext context, AppState app, int id, String sub, Color color) {
    final c = app.customer(id)!;
    return ListTile(
      leading: PersonAvatar(name: c.name, photo: c.photo, radius: 18),
      title: Text(c.name),
      subtitle: Text(sub, style: TextStyle(color: color)),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailScreen(customerId: id))),
    );
  }
}
