import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_log.dart';
import '../../data/app_state.dart';
import '../../data/sample_data.dart';
import '../lock.dart';
import '../theme.dart';
import '../widgets.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _form = GlobalKey<FormState>();
  final _shop = TextEditingController();
  final _owner = TextEditingController();
  final _phone = TextEditingController();
  String? _pin;
  bool _sample = false;
  bool _busy = false;

  Future<void> _finish() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final app = context.read<AppState>();
    try {
      await app.setSettings({
        'shop_name': _shop.text.trim(),
        'owner_name': _owner.text.trim(),
        'shop_phone': _phone.text.trim(),
      });
      if (_pin != null) await app.setPin(_pin);
      if (_sample) await loadSampleData(app);
      await app.setSetting('onboarded', '1');
      AppLog.info('Onboarding finished (pin=${_pin != null}, sample=$_sample)');
    } catch (e, st) {
      AppLog.error('Onboarding failed', e, st);
      if (mounted) toast(context, 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 76,
                  height: 76,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: brandGreen, borderRadius: BorderRadius.circular(22)),
                  child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 42),
                ),
                const SizedBox(height: 16),
                Text('Installment Tracker',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('Know who owes you money, every day. Works fully offline.',
                    style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 16)),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _shop,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      labelText: 'Shop name *', prefixIcon: Icon(Icons.storefront_outlined)),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _owner,
                  textCapitalization: TextCapitalization.words,
                  decoration:
                      const InputDecoration(labelText: 'Owner name', prefixIcon: Icon(Icons.person_outline)),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                      labelText: 'Shop phone', prefixIcon: Icon(Icons.phone_outlined)),
                ),
                const SizedBox(height: 16),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: Icon(_pin == null ? Icons.lock_open_outlined : Icons.lock_outline,
                        color: brandGreen),
                    title: Text(_pin == null ? 'Protect with a PIN' : 'PIN set'),
                    subtitle: const Text('Recommended: CNIC and cheque photos stay private'),
                    trailing: TextButton(
                      onPressed: () async {
                        final pin = await Navigator.push<String>(
                            context, MaterialPageRoute(builder: (_) => const SetPinScreen()));
                        if (pin != null) setState(() => _pin = pin);
                      },
                      child: Text(_pin == null ? 'Set PIN' : 'Change'),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _sample,
                  onChanged: (v) => setState(() => _sample = v),
                  title: const Text('Load sample data'),
                  subtitle: const Text('A few demo customers and sales to try the app. '
                      'You can delete them later in Settings.'),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _busy ? null : _finish,
                  icon: _busy
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.arrow_forward),
                  label: const Text('Start'),
                ),
              ],
            ),
          ),
        ),
      );
}
