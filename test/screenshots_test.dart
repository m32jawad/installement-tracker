// Renders the real app screens (sample shop, real Roboto + Material Icons
// fonts) to PNG files for docs and the walkthrough video.
//
//   SCREENSHOTS_DIR=build/screens flutter test test/screenshots_test.dart
//
// Skipped in a normal `flutter test` run.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installment_tracker/data/app_state.dart';
import 'package:installment_tracker/data/database.dart';
import 'package:installment_tracker/data/photo_store.dart';
import 'package:installment_tracker/data/sample_data.dart';
import 'package:installment_tracker/main.dart';
import 'package:installment_tracker/ui/lock.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final outDir = Platform.environment['SCREENSHOTS_DIR'];

Future<void> _loadFont(String family, List<String> files) async {
  final fonts = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/sdk/flutter'}'
      '/bin/cache/artifacts/material_fonts';
  final loader = FontLoader(family);
  for (final f in files) {
    final bytes = File('$fonts/$f').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

void main() {
  sqfliteFfiInit();
  final key = GlobalKey();
  var n = 0;

  Future<void> shot(WidgetTester t, String name) async {
    await t.pumpAndSettle();
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await t.runAsync(() async {
      final img = await boundary.toImage(pixelRatio: 2.75);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      n++;
      File('$outDir/${n.toString().padLeft(2, '0')}_$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }

  Future<void> tapText(WidgetTester t, String text, {bool last = false}) async {
    final f = find.text(text);
    await t.ensureVisible(last ? f.last : f.first);
    await t.pumpAndSettle();
    await t.tap(last ? f.last : f.first);
    await t.pumpAndSettle();
  }

  Future<void> tab(WidgetTester t, String label) async {
    await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
    await t.pumpAndSettle();
  }

  testWidgets('capture screens', (t) async {
    debugDisableShadows = false; // real soft shadows, not test outlines
    await _loadFont('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']);
    await _loadFont('MaterialIcons', ['MaterialIcons-Regular.otf']);
    Directory(outDir!).createSync(recursive: true);
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.75;
    addTearDown(t.view.reset);

    final tmp = Directory.systemTemp.createTempSync('shots');
    final app = (await t.runAsync(() async {
      final db = await openAppDatabase('${tmp.path}/s.db', factory: databaseFactoryFfi);
      final a = AppState(db, PhotoStore(Directory('${tmp.path}/photos')));
      await a.load();
      return a;
    }))!;

    Widget wrap() => RepaintBoundary(key: key, child: InstallmentApp(initial: app));

    // 1. First launch
    await t.pumpWidget(wrap());
    await shot(t, 'onboarding');

    await t.runAsync(() async {
      await app.setSettings({'shop_name': 'Raza Mobiles', 'owner_name': 'Ali Raza', 'shop_phone': '0300-1112223', 'onboarded': '1'});
      await loadSampleData(app);
    });
    await t.pumpAndSettle();

    // 2-4. Dashboard
    await shot(t, 'dashboard');
    await t.drag(find.byType(ListView).first, const Offset(0, -900));
    await shot(t, 'dashboard_overdue');
    await t.drag(find.byType(ListView).first, const Offset(0, -1100));
    await shot(t, 'dashboard_calendar');
    await t.drag(find.byType(ListView).first, const Offset(0, 4000));
    await t.pumpAndSettle();

    // 5. Reminder sheet
    await t.tap(find.byTooltip('Remind').first);
    await shot(t, 'whatsapp_reminder');
    await t.tapAt(const Offset(200, 80));
    await t.pumpAndSettle();

    // 6-7. Sales -> sale detail with every status colour
    await tab(t, 'Sales');
    await shot(t, 'sales');
    await tapText(t, 'Usman Ghani');
    await t.drag(find.byType(ListView).first, const Offset(0, -520));
    await shot(t, 'sale_detail_schedule');

    // 8. Collect payment sheet
    await t.drag(find.byType(ListView).first, const Offset(0, 2000));
    await t.pumpAndSettle();
    await tapText(t, 'Collect Payment');
    await shot(t, 'collect_payment');
    await t.tapAt(const Offset(200, 60));
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();

    // 9-10. Customers
    await tab(t, 'Customers');
    await shot(t, 'customers');
    await tapText(t, 'Ali Raza');
    await shot(t, 'customer_detail');
    await t.pageBack();
    await t.pumpAndSettle();

    // 11. Payments ledger
    await tab(t, 'Payments');
    await shot(t, 'payments');

    // 12-13. Reports
    await tab(t, 'Reports');
    await shot(t, 'report_monthly');
    await tapText(t, 'Overall');
    await shot(t, 'report_overall');

    // 14. New sale wizard, plan step
    await tab(t, 'Home');
    await tapText(t, 'New');
    await tapText(t, 'New Sale');
    await tapText(t, 'Hamza Iqbal');
    await tapText(t, 'Oppo A78');
    await t.enterText(find.widgetWithText(TextFormField, 'Advance / down payment *'), '12000');
    await t.enterText(find.widgetWithText(TextFormField, 'Monthly installment *'), '5000');
    await t.pumpAndSettle();
    await t.drag(find.byType(Stepper), const Offset(0, -260));
    await shot(t, 'new_sale_plan');
    await t.pageBack();
    await t.pumpAndSettle();

    // 15. Settings
    await t.tap(find.byTooltip('Settings'));
    await shot(t, 'settings');
    await t.pageBack();
    await t.pumpAndSettle();

    // 16. PIN lock
    await t.runAsync(() => app.setPin('1234'));
    AppLockController.instance.init(hasPin: () => app.hasPin);
    AppLockController.instance.lock();
    await shot(t, 'pin_lock');

    await t.runAsync(() => app.db.close());
    debugDisableShadows = true;
  }, skip: outDir == null);
}
