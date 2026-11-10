import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installment_tracker/data/app_state.dart';
import 'package:installment_tracker/data/database.dart';
import 'package:installment_tracker/data/photo_store.dart';
import 'package:installment_tracker/data/sample_data.dart';
import 'package:installment_tracker/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Renders every main screen with the sample shop at phone size. Any layout
/// overflow or build exception fails the test.
void main() {
  sqfliteFfiInit();

  Future<AppState> seeded(Directory tmp, {bool onboarded = true}) async {
    final db = await openAppDatabase('${tmp.path}/w.db', factory: databaseFactoryFfi);
    final app = AppState(db, PhotoStore(Directory('${tmp.path}/photos')));
    await app.load();
    if (onboarded) {
      await app.setSettings({'shop_name': 'Raza Mobiles', 'onboarded': '1'});
      await loadSampleData(app);
    }
    return app;
  }

  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.75;
    addTearDown(t.view.reset);
  }

  testWidgets('first launch shows onboarding', (tester) async {
    phone(tester);
    final tmp = Directory.systemTemp.createTempSync('w1');
    final app = (await tester.runAsync(() => seeded(tmp, onboarded: false)))!;
    await tester.pumpWidget(InstallmentApp(initial: app));
    await tester.pumpAndSettle();
    expect(find.text('Installment Tracker'), findsOneWidget);
    expect(find.text('Shop name *'), findsOneWidget);
    await tester.runAsync(() => app.db.close());
  });

  testWidgets('dashboard, tabs, sale detail and wizard render', (tester) async {
    phone(tester);
    final tmp = Directory.systemTemp.createTempSync('w2');
    final app = (await tester.runAsync(() => seeded(tmp)))!;
    await tester.pumpWidget(InstallmentApp(initial: app));
    await tester.pumpAndSettle();

    expect(find.text('Raza Mobiles'), findsOneWidget);
    expect(find.text('To collect this month'), findsOneWidget);
    expect(find.text('Due Today'), findsWidgets);
    expect(find.text('Sana Bibi'), findsWidgets); // due today in sample data

    // Overdue filter chip.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Overdue'));
    await tester.pumpAndSettle();
    expect(find.textContaining('late'), findsWidgets);

    for (final tab in ['Customers', 'Sales', 'Payments', 'Reports']) {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)));
      await tester.pumpAndSettle();
    }
    // Reports overall tab.
    await tester.tap(find.text('Overall'));
    await tester.pumpAndSettle();
    expect(find.text('Top items on installments'), findsOneWidget);

    // Sales -> open a sale detail.
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Sales')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ali Raza').first);
    await tester.pumpAndSettle();
    expect(find.text('Installment Schedule'), findsOneWidget);
    expect(find.textContaining('Paid '), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Quick action -> New Sale wizard.
    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Sale'));
    await tester.pumpAndSettle();
    expect(find.text('Add New Customer'), findsOneWidget);
    await tester.tap(find.text('Hamza Iqbal'));
    await tester.pumpAndSettle();
    expect(find.text('Add New Item (photos, IMEI)'), findsOneWidget);

    await tester.runAsync(() => app.db.close());
  });
}
