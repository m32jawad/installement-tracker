import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_log.dart';
import '../../core/format.dart';
import '../../data/app_state.dart';
import '../../data/backup.dart';
import '../../data/sample_data.dart';
import '../../main.dart';
import '../../services/exporter.dart';
import '../lock.dart';
import '../theme.dart';
import '../widgets.dart';
import 'items.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    Widget header(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(t, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
        header('Shop profile'),
        ListTile(
          leading: const Icon(Icons.storefront_outlined),
          title: Text(app.shopName),
          subtitle: Text([app.ownerName, app.shopPhone, app.shopAddress].where((s) => s.isNotEmpty).join(' · ')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _ProfileScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.phone_android),
          title: const Text('Items / stock'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ItemsScreen())),
        ),
        header('App lock'),
        ListTile(
          leading: Icon(app.hasPin ? Icons.lock : Icons.lock_open, color: app.hasPin ? brandGreen : null),
          title: Text(app.hasPin ? 'PIN lock is ON' : 'PIN lock is OFF'),
          subtitle: const Text('Asked when opening the app and after 45 s in background'),
          trailing: TextButton(
            onPressed: () async {
              final pin = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const SetPinScreen()));
              if (pin != null) {
                await app.setPin(pin);
                if (context.mounted) toast(context, 'PIN saved');
              }
            },
            child: Text(app.hasPin ? 'Change' : 'Set PIN'),
          ),
        ),
        if (app.hasPin)
          ListTile(
            leading: const Icon(Icons.no_encryption_outlined),
            title: const Text('Remove PIN'),
            onTap: () async {
              if (await confirm(context, title: 'Remove PIN?', message: 'Anyone with the phone can open the app.')) {
                await app.setPin(null);
              }
            },
          ),
        header('Payments & installments'),
        ListTile(
          leading: const Icon(Icons.account_balance_outlined),
          title: const Text('Payment methods'),
          subtitle: Text(app.paymentMethods.join(', ')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _MethodsScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.event_repeat),
          title: const Text('Default due day'),
          subtitle: Text(app.defaultDueDay == 0
              ? 'Same date as the sale, one month later'
              : '${app.defaultDueDay} of each month'),
          onTap: () async {
            final v = await promptText(context,
                title: 'Default due day (1-28, 0 = sale date)', initial: '${app.defaultDueDay}', maxLines: 1);
            final n = int.tryParse(v ?? '');
            if (n != null && n >= 0 && n <= 28) await app.setSetting('default_due_day', '$n');
          },
        ),
        ListTile(
          leading: const Icon(Icons.chat_outlined),
          title: const Text('WhatsApp reminder message'),
          subtitle: Text(app.reminderTemplate, maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () async {
            final v = await promptText(context,
                title: 'Reminder template',
                initial: app.reminderTemplate,
                hint: 'Use [Name] [Amount] [Item] [Date] [Shop Name]',
                maxLines: 5);
            if (v != null) await app.setSetting('wa_template', v.isEmpty ? defaultReminderTemplate : v);
          },
        ),
        ListTile(
          leading: const Icon(Icons.currency_exchange),
          title: const Text('Currency symbol'),
          subtitle: Text(app.currency),
          onTap: () async {
            final v = await promptText(context, title: 'Currency symbol', initial: app.currency, maxLines: 1);
            if (v != null && v.isNotEmpty) await app.setSetting('currency', v);
          },
        ),
        header('Appearance'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'system', label: Text('System'), icon: Icon(Icons.brightness_auto)),
              ButtonSegment(value: 'light', label: Text('Light'), icon: Icon(Icons.light_mode)),
              ButtonSegment(value: 'dark', label: Text('Dark'), icon: Icon(Icons.dark_mode)),
            ],
            selected: {app.themeMode},
            onSelectionChanged: (s) => app.setSetting('theme', s.first),
          ),
        ),
        header('Backup & export'),
        ListTile(
          leading: const Icon(Icons.backup_outlined),
          title: const Text('Create backup'),
          subtitle: const Text('All data + photos in one .zip. Save it to Google Drive, WhatsApp or USB.'),
          onTap: () => _backup(context),
        ),
        ListTile(
          leading: const Icon(Icons.settings_backup_restore),
          title: const Text('Restore from backup'),
          subtitle: const Text('Replaces everything on this phone'),
          onTap: () => _restore(context),
        ),
        ListTile(
          leading: const Icon(Icons.table_view_outlined),
          title: const Text('Export all data (Excel / CSV)'),
          onTap: () async {
            try {
              final files = await exportAllCsv(app);
              await AppLockController.instance.whileExternal(() => SharePlus.instance.share(ShareParams(
                  files: files.map((f) => XFile(f.path, mimeType: 'text/csv')).toList(),
                  text: '${app.shopName} - data export')));
            } catch (e, st) {
              AppLog.error('CSV export failed', e, st);
              if (context.mounted) toast(context, 'Export failed: $e');
            }
          },
        ),
        header('Help & diagnostics'),
        ListTile(
          leading: const Icon(Icons.bug_report_outlined),
          title: const Text('Diagnostics log'),
          subtitle: FutureBuilder<int>(
            future: AppLog.errorCount(),
            builder: (_, s) => Text(s.data == null || s.data == 0
                ? 'No errors recorded'
                : '${s.data} error(s) recorded - share with your developer'),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _LogScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.science_outlined),
          title: const Text('Load sample data'),
          subtitle: const Text('Adds demo customers and sales to explore the app'),
          onTap: () async {
            if (await confirm(context, title: 'Load sample data?', message: 'Adds 5 demo customers, 7 items and 5 sales.')) {
              await loadSampleData(app);
              if (context.mounted) toast(context, 'Sample data added');
            }
          },
        ),
        header('Danger zone'),
        ListTile(
          leading: const Icon(Icons.delete_forever, color: StatusColors.overdue),
          title: const Text('Delete all data', style: TextStyle(color: StatusColors.overdue)),
          subtitle: const Text('Customers, items, sales, payments and photos. Settings are kept.'),
          onTap: () async {
            final ok = await confirm(context,
                title: 'Delete ALL data?',
                message: 'Everything will be erased from this phone. Make a backup first. This cannot be undone.',
                confirmLabel: 'Delete everything',
                danger: true);
            if (!ok || !context.mounted) return;
            final again = await promptText(context, title: 'Type DELETE to confirm', maxLines: 1);
            if (again == 'DELETE') {
              await app.wipeAll();
              if (context.mounted) toast(context, 'All data deleted');
            }
          },
        ),
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text('Installment Tracker v1.0.0 · works offline · data stays on this phone',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }

  BackupService _service(AppState app) =>
      BackupService(app.db.path, app.photos.dir);

  Future<void> _backup(BuildContext context) async {
    final app = context.read<AppState>();
    try {
      final zip = await _service(app).createBackup(app.db, await exportDir());
      await app.setSetting('last_backup', DateTime.now().toIso8601String());
      await AppLockController.instance.whileExternal(() => SharePlus.instance.share(ShareParams(
          files: [XFile(zip.path, mimeType: 'application/zip')],
          text: '${app.shopName} backup ${fmtDate(DateTime.now())}')));
    } catch (e, st) {
      AppLog.error('Backup failed', e, st);
      if (context.mounted) toast(context, 'Backup failed: $e');
    }
  }

  Future<void> _restore(BuildContext context) async {
    final app = context.read<AppState>();
    final holder = context.read<AppHolder>();
    final ok = await confirm(context,
        title: 'Restore backup?',
        message: 'All current data on this phone will be replaced by the backup.',
        confirmLabel: 'Choose file',
        danger: true);
    if (!ok) return;
    try {
      final file = await AppLockController.instance.whileExternal(() => FilePicker.pickFile());
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final service = _service(app);
      final dbPath = app.db.path;
      await app.db.close();
      try {
        await service.restoreBackup(bytes);
      } finally {
        await holder.reopen();
      }
      if (context.mounted) {
        toast(context, 'Backup restored');
        Navigator.popUntil(context, (r) => r.isFirst);
      }
      AppLog.info('Restore finished into ${p.basename(dbPath)}');
    } on FormatException catch (e) {
      if (context.mounted) toast(context, e.message);
    } catch (e, st) {
      AppLog.error('Restore failed', e, st);
      if (context.mounted) toast(context, 'Restore failed: $e');
    }
  }
}

class _ProfileScreen extends StatefulWidget {
  const _ProfileScreen();
  @override
  State<_ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<_ProfileScreen> {
  late final app = context.read<AppState>();
  late final _shop = TextEditingController(text: app.shopName);
  late final _owner = TextEditingController(text: app.ownerName);
  late final _phone = TextEditingController(text: app.shopPhone);
  late final _address = TextEditingController(text: app.shopAddress);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Shop profile')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Shown on receipts, reminders and PDF reports.'),
          const SizedBox(height: 12),
          TextField(controller: _shop, decoration: const InputDecoration(labelText: 'Shop name')),
          const SizedBox(height: 12),
          TextField(controller: _owner, decoration: const InputDecoration(labelText: 'Owner name')),
          const SizedBox(height: 12),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
          const SizedBox(height: 12),
          TextField(controller: _address, decoration: const InputDecoration(labelText: 'Address')),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () async {
              await app.setSettings({
                'shop_name': _shop.text.trim().isEmpty ? 'My Shop' : _shop.text.trim(),
                'owner_name': _owner.text.trim(),
                'shop_phone': _phone.text.trim(),
                'shop_address': _address.text.trim(),
              });
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ]),
      );
}

class _MethodsScreen extends StatelessWidget {
  const _MethodsScreen();
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final methods = app.paymentMethods;
    return Scaffold(
      appBar: AppBar(title: const Text('Payment methods')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final v = await promptText(context, title: 'New payment method', hint: 'e.g. Raast, Bank Al Habib', maxLines: 1);
          if (v != null && v.isNotEmpty && !methods.contains(v)) await app.setPaymentMethods([...methods, v]);
        },
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: ReorderableListView(
        onReorderItem: (a, b) {
          final l = [...methods];
          final m = l.removeAt(a);
          l.insert(b, m);
          app.setPaymentMethods(l);
        },
        children: [
          for (final m in methods)
            ListTile(
              key: ValueKey(m),
              leading: const Icon(Icons.drag_indicator),
              title: Text(m),
              trailing: methods.length <= 1
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => app.setPaymentMethods(methods.where((x) => x != m).toList()),
                    ),
            ),
        ],
      ),
    );
  }
}

class _LogScreen extends StatefulWidget {
  const _LogScreen();
  @override
  State<_LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<_LogScreen> {
  bool _errorsOnly = false;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Diagnostics log'),
          actions: [
            IconButton(
              tooltip: 'Share log',
              icon: const Icon(Icons.share),
              onPressed: () async {
                final f = AppLog.file;
                if (f != null && await f.exists()) {
                  await AppLockController.instance.whileExternal(() => SharePlus.instance.share(ShareParams(
                      files: [XFile(f.path, mimeType: 'text/plain')], text: 'Installment Tracker diagnostics log')));
                }
              },
            ),
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                await AppLog.clear();
                setState(() {});
              },
            ),
          ],
        ),
        body: FutureBuilder<String>(
          future: AppLog.read(),
          builder: (_, s) {
            var lines = (s.data ?? '').trim().split('\n').reversed.toList();
            if (_errorsOnly) lines = lines.where((l) => l.contains('[ERROR]') || l.contains('[WARN]')).toList();
            return Column(children: [
              SwitchListTile(
                title: const Text('Errors and warnings only'),
                value: _errorsOnly,
                onChanged: (v) => setState(() => _errorsOnly = v),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: lines.length,
                  itemBuilder: (_, i) => Text(
                    lines[i],
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: lines[i].contains('[ERROR]')
                          ? StatusColors.overdue
                          : lines[i].contains('[WARN]')
                              ? accentGold
                              : null,
                    ),
                  ),
                ),
              ),
            ]);
          },
        ),
      );
}
