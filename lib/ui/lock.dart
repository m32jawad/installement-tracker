import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_log.dart';
import '../data/app_state.dart';
import 'theme.dart';

/// Locks the app on start and after it has been in the background for
/// [relockAfter], when a PIN is set. Opening the camera / gallery / share
/// sheet goes through [whileExternal] so it does not trigger a lock.
class AppLockController extends ChangeNotifier with WidgetsBindingObserver {
  AppLockController._();
  static final instance = AppLockController._();

  static const relockAfter = Duration(seconds: 45);

  bool locked = false;
  bool Function() hasPin = () => false;
  DateTime? _pausedAt;
  int _external = 0;

  void init({required bool Function() hasPin}) {
    this.hasPin = hasPin;
    locked = hasPin();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<T> whileExternal<T>(Future<T> Function() fn) async {
    _external++;
    try {
      return await fn();
    } finally {
      // Resume events arrive slightly after the future completes.
      Future.delayed(const Duration(seconds: 2), () => _external--);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _pausedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final at = _pausedAt;
      _pausedAt = null;
      if (_external > 0 || at == null || !hasPin()) return;
      if (DateTime.now().difference(at) >= relockAfter) lock();
    }
  }

  void lock() {
    if (!hasPin()) return;
    locked = true;
    notifyListeners();
  }

  void unlock() {
    locked = false;
    notifyListeners();
  }
}

class PinPad extends StatefulWidget {
  final String title;
  final String? subtitle;
  final int minLength;
  final Future<String?> Function(String pin) onSubmit; // returns error text or null
  const PinPad({super.key, required this.title, this.subtitle, this.minLength = 4, required this.onSubmit});

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';
  String? _error;
  static const maxLen = 6;

  Future<void> _press(String k) async {
    HapticFeedback.selectionClick();
    setState(() {
      _error = null;
      if (k == '<') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < maxLen) {
        _pin += k;
      }
    });
    if (_pin.length == maxLen) await _submit();
  }

  Future<void> _submit() async {
    if (_pin.length < widget.minLength) {
      setState(() => _error = 'PIN must be ${widget.minLength}-$maxLen digits');
      return;
    }
    final err = await widget.onSubmit(_pin);
    if (!mounted) return;
    if (err != null) {
      HapticFeedback.heavyImpact();
      setState(() {
        _error = err;
        _pin = '';
      });
    }
  }

  Widget _key(String k) {
    final scheme = Theme.of(context).colorScheme;
    Widget child;
    if (k == '<') {
      child = const Icon(Icons.backspace_outlined);
    } else if (k == 'ok') {
      child = const Icon(Icons.check_rounded, size: 30);
    } else {
      child = Text(k, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w500));
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Material(
        color: k == 'ok' ? scheme.primary : scheme.surfaceContainerHighest,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => k == 'ok' ? _submit() : _press(k),
          child: SizedBox(
            width: 74,
            height: 74,
            child: Center(
              child: IconTheme(
                data: IconThemeData(color: k == 'ok' ? scheme.onPrimary : scheme.onSurface),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.headlineSmall),
        if (widget.subtitle != null) ...[
          const SizedBox(height: 6),
          Text(widget.subtitle!, textAlign: TextAlign.center, style: TextStyle(color: scheme.outline)),
        ],
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            maxLen,
            (i) => Container(
              margin: const EdgeInsets.all(7),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < _pin.length ? scheme.primary : Colors.transparent,
                border: Border.all(color: i < widget.minLength ? scheme.primary : scheme.outline, width: 2),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 26,
          child: _error == null
              ? null
              : Text(_error!, style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600)),
        ),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['<', '0', 'ok'],
        ])
          Row(mainAxisAlignment: MainAxisAlignment.center, children: row.map(_key).toList()),
      ],
    );
  }
}

class LockScreen extends StatelessWidget {
  const LockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(children: [
              const Icon(Icons.lock_outline_rounded, size: 46, color: brandGreen),
              const SizedBox(height: 8),
              Text(app.shopName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 20),
              PinPad(
                title: 'Enter PIN',
                onSubmit: (pin) async {
                  if (app.checkPin(pin)) {
                    AppLockController.instance.unlock();
                    return null;
                  }
                  AppLog.warn('Wrong PIN entered');
                  return 'Wrong PIN, try again';
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Two-step "enter new PIN / confirm" flow. Returns the PIN or null.
class SetPinScreen extends StatefulWidget {
  const SetPinScreen({super.key});
  @override
  State<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends State<SetPinScreen> {
  String? _first;
  Key _padKey = UniqueKey();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Set PIN')),
        body: Center(
          child: SingleChildScrollView(
            child: PinPad(
              key: _padKey,
              title: _first == null ? 'Choose a PIN' : 'Confirm PIN',
              subtitle: _first == null
                  ? '4 to 6 digits. You will need it to open the app.'
                  : 'Enter the same PIN again',
              onSubmit: (pin) async {
                if (_first == null) {
                  setState(() {
                    _first = pin;
                    _padKey = UniqueKey();
                  });
                  return null;
                }
                if (pin != _first) {
                  setState(() {
                    _first = null;
                    _padKey = UniqueKey();
                  });
                  return 'PINs did not match, start again';
                }
                Navigator.pop(context, pin);
                return null;
              },
            ),
          ),
        ),
      );
}
