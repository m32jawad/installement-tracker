import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/app_state.dart';
import '../../logic/schedule.dart';
import '../../services/contact.dart';
import '../theme.dart';
import '../widgets.dart';
import 'collect_payment.dart';
import 'sales.dart';

/// A due installment row: customer, item, amount, due date, status, and
/// [Collect] [Remind] [Mark Skipped] buttons.
class DueTile extends StatelessWidget {
  final DueEntry e;
  final bool actions;
  const DueTile(this.e, {super.key, this.actions = true});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final st = e.inst;
    final late = st.daysLate(app.today);
    final color = st.status == InstStatus.pending && st.dueDate == app.today
        ? accentGold
        : instStatusColor(st.status);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: e.sale.id!))),
        child: Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 5))),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              PersonAvatar(name: e.customer.name, photo: e.customer.photo, radius: 19),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.customer.name,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  Text('${e.itemName} · #${st.number}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(money(st.remaining),
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: color)),
                Text(
                    late > 0
                        ? 'Was due ${fmtDateShort(st.dueDate)}'
                        : 'Due ${fmtDateShort(st.dueDate)}',
                    style: const TextStyle(fontSize: 12)),
              ]),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: Wrap(spacing: 6, runSpacing: 4, children: [
                  if (late > 0)
                    StatusChip(daysLateLabel(late), StatusColors.overdue, dense: true)
                  else
                    StatusChip(st.dueDate == app.today ? 'Due today' : instStatusLabel(st.status), color,
                        dense: true),
                  if (st.status == InstStatus.partial)
                    StatusChip('Paid ${money(st.paid)}', StatusColors.partial, dense: true),
                ]),
              ),
              if (actions) ...[
                IconButton(
                  tooltip: 'Remind',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chat_outlined, color: Color(0xFF25D366)),
                  onPressed: () => showReminderSheet(context, e),
                ),
                IconButton(
                  tooltip: 'Mark skipped',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.redo_rounded),
                  onPressed: () => markSkippedFlow(context, e.inst.id),
                ),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(64, 38), padding: const EdgeInsets.symmetric(horizontal: 14)),
                  onPressed: () => showCollectPayment(context, saleId: e.sale.id!, installmentId: st.id),
                  child: const Text('Collect'),
                ),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}

Future<void> markSkippedFlow(BuildContext context, int installmentId) async {
  final app = context.read<AppState>();
  final reason = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final ctrl = TextEditingController();
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Mark as skipped', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('It stays in the schedule (grey) and can be un-skipped and collected later.'),
          const SizedBox(height: 12),
          Wrap(spacing: 6, children: [
            for (final r in const ['Will pay next month double', 'Out of city', 'No response'])
              ActionChip(label: Text(r), onPressed: () => ctrl.text = r),
          ]),
          const SizedBox(height: 8),
          TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Reason (optional)')),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Mark Skipped')),
        ]),
      );
    },
  );
  if (reason == null) return;
  await app.setSkipped(installmentId, true, reason: reason.isEmpty ? null : reason);
  if (context.mounted) toast(context, 'Installment marked as skipped');
}

Future<void> showReminderSheet(BuildContext context, DueEntry e) async {
  final app = context.read<AppState>();
  final msg = app.reminderText(e);
  await showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Remind ${e.customer.name}', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFDCF8C6).withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(msg, style: const TextStyle(color: Colors.black87)),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
            icon: const Icon(Icons.chat),
            label: const Text('Send on WhatsApp'),
            onPressed: () {
              Navigator.pop(ctx);
              openWhatsApp(context, e.customer.phone, msg);
            },
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.sms_outlined),
                label: const Text('SMS'),
                onPressed: () {
                  Navigator.pop(ctx);
                  sendSms(context, e.customer.phone, msg);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.call_outlined),
                label: const Text('Call'),
                onPressed: () {
                  Navigator.pop(ctx);
                  callPhone(context, e.customer.phone);
                },
              ),
            ),
          ]),
        ]),
      ),
    ),
  );
}
