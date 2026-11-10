import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';

import 'core/app_log.dart';
import 'data/app_state.dart';
import 'data/database.dart';
import 'data/photo_store.dart';
import 'ui/lock.dart';
import 'ui/screens/home_shell.dart';
import 'ui/screens/onboarding.dart';
import 'ui/theme.dart';

/// Opens the database in the app's private folder. Also used after a restore.
Future<AppState> openAppState() async {
  final docs = await getApplicationDocumentsDirectory();
  final dbPath = p.join(await getDatabasesPath(), dbFileName);
  final db = await openAppDatabase(dbPath);
  final app = AppState(db, PhotoStore(Directory(p.join(docs.path, 'photos'))));
  await app.load();
  return app;
}

Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    final docs = await getApplicationDocumentsDirectory();
    await AppLog.init(docs.path);
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      AppLog.error('Flutter error: ${details.exceptionAsString()}', null, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      AppLog.error('Uncaught platform error', error, stack);
      return true;
    };
    AppLog.info('App start');
    final app = await openAppState();
    AppLockController.instance.init(hasPin: () => app.hasPin);
    runApp(InstallmentApp(initial: app));
  }, (error, stack) => AppLog.error('Uncaught zone error', error, stack));
}

/// Holds the current [AppState] so a backup restore can swap it out.
class AppHolder extends ChangeNotifier {
  AppState app;
  AppHolder(this.app);

  Future<void> reopen() async {
    final old = app;
    app = await openAppState();
    notifyListeners();
    // Let the widget tree rebuild with the new state before disposing the old one.
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }
}

class InstallmentApp extends StatefulWidget {
  final AppState initial;
  const InstallmentApp({super.key, required this.initial});
  @override
  State<InstallmentApp> createState() => _InstallmentAppState();
}

class _InstallmentAppState extends State<InstallmentApp> {
  late final holder = AppHolder(widget.initial);

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
        value: holder,
        child: Consumer<AppHolder>(
          builder: (context, h, _) => ChangeNotifierProvider<AppState>.value(
            value: h.app,
            child: ChangeNotifierProvider.value(
              value: AppLockController.instance,
              child: const _Root(),
            ),
          ),
        ),
      );
}

class _Root extends StatelessWidget {
  const _Root();

  ThemeMode _mode(String s) => switch (s) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final lock = context.watch<AppLockController>();
    return MaterialApp(
      title: 'Installment Tracker',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: _mode(app.themeMode),
      home: app.onboarded ? const HomeShell() : const OnboardingScreen(),
      builder: (context, child) => Stack(children: [
        if (child != null) child,
        if (lock.locked && app.hasPin) const Positioned.fill(child: LockScreen()),
      ]),
    );
  }
}
