import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/app_state.dart';
import '../../logic/schedule.dart';
import '../theme.dart';
import '../widgets.dart';
import 'due_tile.dart';
import 'items.dart';
import 'payments.dart';
import 'settings.dart';

enum DashFilter { all, today, overdue, thisMonth, nextMonth }

const _filterLabels = {
  DashFilter.all: 'All',
  DashFilter.today: 'Due Today',
  DashFilter.overdue: 'Overdue',
  DashFilter.thisMonth: 'This Month',
  DashFilter.nextMonth: 'Next Month',
};

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DashFilter _filter = DashFilter.all;
  String _q = '';
  late DateTime _calMonth;
  DateTime? _calDay;

  @override
  void initState() {
    super.initState();
    final t = context.read<AppState>().today;
    _calMonth = DateTime(t.year, t.month);
  }

  bool _matches(DueEntry e) => matchesQuery(_q, [
        e.customer.name,
        e.customer.phone,
        e.customer.cnic,
        e.itemName,
        e.item?.imei,
      ]);

  List<DueEntry> _filtered(AppState app) {
    final t = app.today;
    List<DueEntry> l;
    switch (_filter) {
      case DashFilter.all:
        l = app.openDue();
      case DashFilter.today:
        l = app.dueToday();
      case DashFilter.overdue:
        l = app.overdue();
      case DashFilter.thisMonth:
        l = app.dueInMonth(t).where((e) => e.inst.isOpen && !e.inst.skipped).toList();
      case DashFilter.nextMonth:
        l = app.dueInMonth(DateTime(t.year, t.month + 1)).where((e) => e.inst.isOpen && !e.inst.skipped).toList();
    }
    return l.where(_matches).toList();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = app.today;
    final searching = _filter != DashFilter.all || _q.isNotEmpty;
    final dueToday = app.dueToday();
    final week = app.dueNextDays(7);
    final overdue = app.overdue()..sort((a, b) => a.inst.dueDate.compareTo(b.inst.dueDate));
    final recent = app.payments.take(8).toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(app.shopName),
          Text(fmtDate(t), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Items / Stock',
            icon: const Icon(Icons.phone_android),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ItemsScreen())),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: app.load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.75,
                children: [
                  StatCard(
                      title: 'To collect this month',
                      value: money(app.expectedInMonth(t)),
                      color: brandGreen,
                      icon: Icons.calendar_month,
                      onTap: () => setState(() => _filter = DashFilter.thisMonth)),
                  StatCard(
                      title: 'Collected this month',
                      value: money(app.collectedInMonth(t)),
                      color: StatusColors.paid,
                      icon: Icons.check_circle_outline,
                      onTap: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const PaymentsScreen(standalone: true)))),
                  StatCard(
                      title: 'Pending / Overdue',
                      value: money(app.pendingAndOverdueNow()),
                      color: StatusColors.overdue,
                      icon: Icons.warning_amber_rounded,
                      onTap: () => setState(() => _filter = DashFilter.overdue)),
                  StatCard(
                      title: 'Total outstanding',
                      value: money(app.totalOutstanding()),
                      color: accentGold,
                      icon: Icons.account_balance_wallet_outlined),
                ],
              ),
            ),
            SearchBox(hint: 'Search customer, phone, item, IMEI', onChanged: (v) => setState(() => _q = v.trim())),
            ChoiceChips<DashFilter>(
              values: DashFilter.values,
              selected: _filter,
              label: (f) => _filterLabels[f]!,
              onSelected: (f) => setState(() => _filter = f),
            ),
            if (searching) ...[
              SectionHeader(_filterLabels[_filter]!, count: _filtered(app).length),
              if (_filtered(app).isEmpty) const InlineEmpty('Nothing due here'),
              ..._filtered(app).map((e) => DueTile(e)),
            ] else ...[
              SectionHeader('Due Today', count: dueToday.length, color: accentGold),
              if (dueToday.isEmpty) const InlineEmpty('No one is due today'),
              ...dueToday.map((e) => DueTile(e)),
              SectionHeader('Overdue / Late', count: overdue.length, color: StatusColors.overdue),
              if (overdue.isEmpty) const InlineEmpty('No overdue installments'),
              ...overdue.take(15).map((e) => DueTile(e)),
              if (overdue.length > 15)
                TextButton(
                    onPressed: () => setState(() => _filter = DashFilter.overdue),
                    child: Text('Show all ${overdue.length} overdue')),
              SectionHeader('Due This Week', count: week.length),
              if (week.isEmpty) const InlineEmpty('Nothing due in the next 7 days'),
              ...week.map((e) => DueTile(e)),
              SectionHeader('Due This Month'),
              _MonthCalendar(
                month: _calMonth,
                selected: _calDay,
                onMonth: (m) => setState(() {
                  _calMonth = m;
                  _calDay = null;
                }),
                onDay: (d) => setState(() => _calDay = _calDay == d ? null : d),
              ),
              if (_calDay != null) ...[
                SectionHeader('Due on ${fmtDate(_calDay!)}'),
                ...() {
                  final l = app
                      .dueInMonth(_calDay!)
                      .where((e) => e.inst.dueDate == _calDay && !e.inst.skipped)
                      .toList();
                  if (l.isEmpty) return [const InlineEmpty('Nothing due that day')];
                  return l.map((e) => DueTile(e, actions: e.inst.isOpen)).toList();
                }(),
              ],
              SectionHeader('Recent Payments',
                  trailing: TextButton(
                      onPressed: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const PaymentsScreen(standalone: true))),
                      child: const Text('See all'))),
              if (recent.isEmpty) const InlineEmpty('No payments yet'),
              ...recent.map((p) => PaymentTile(p)),
            ],
            if (app.sales.isEmpty && !searching)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Tap + New to add your first sale. The app builds the installment '
                  'schedule and shows who is due here every morning.',
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  final DateTime month;
  final DateTime? selected;
  final ValueChanged<DateTime> onMonth;
  final ValueChanged<DateTime> onDay;
  const _MonthCalendar(
      {required this.month, required this.selected, required this.onMonth, required this.onDay});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final dueDays = app.dueDatesInMonth(month);
    final overdueDays = app
        .dueInMonth(month)
        .where((e) => e.inst.isOpen && !e.inst.skipped && e.inst.dueDate.isBefore(app.today))
        .map((e) => e.inst.dueDate)
        .toSet();
    final first = DateTime(month.year, month.month, 1);
    final lead = first.weekday % 7; // Sunday first
    final days = daysInMonth(month.year, month.month);
    final cells = <Widget>[
      for (final d in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
        Center(child: Text(d, style: TextStyle(color: scheme.outline, fontWeight: FontWeight.w600))),
      for (var i = 0; i < lead; i++) const SizedBox(),
      for (var d = 1; d <= days; d++)
        Builder(builder: (_) {
          final date = DateTime(month.year, month.month, d);
          final isToday = date == app.today;
          final isSel = date == selected;
          final has = dueDays.contains(date);
          final dot = overdueDays.contains(date) ? StatusColors.overdue : accentGold;
          return InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => onDay(date),
            child: Container(
              decoration: BoxDecoration(
                color: isSel ? scheme.primary : (isToday ? scheme.primaryContainer : null),
                shape: BoxShape.circle,
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('$d',
                    style: TextStyle(
                        color: isSel ? scheme.onPrimary : null,
                        fontWeight: has || isToday ? FontWeight.w700 : FontWeight.w400)),
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: has ? dot : Colors.transparent),
                ),
              ]),
            ),
          );
        }),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          Row(children: [
            IconButton(
                onPressed: () => onMonth(DateTime(month.year, month.month - 1)),
                icon: const Icon(Icons.chevron_left)),
            Expanded(
                child: Text(fmtMonth(month),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            IconButton(
                onPressed: () => onMonth(DateTime(month.year, month.month + 1)),
                icon: const Icon(Icons.chevron_right)),
          ]),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.05,
            children: cells,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Tap a date to see who is due',
                style: TextStyle(color: scheme.outline, fontSize: 12)),
          ),
        ]),
      ),
    );
  }
}
