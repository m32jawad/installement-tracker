import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../logic/schedule.dart';

const brandGreen = Color(0xFF0F7A55);
const accentGold = Color(0xFFE09A00);

/// Status colours are the same on every screen (spec 6).
class StatusColors {
  static const paid = Color(0xFF2E9E5B);
  static const pending = Color(0xFFE0A100);
  static const overdue = Color(0xFFD32F2F);
  static const skipped = Color(0xFF757575);
  static const partial = Color(0xFF1E88E5);
  static const cancelled = Color(0xFF9E9E9E);
}

Color instStatusColor(InstStatus s) {
  switch (s) {
    case InstStatus.paid:
      return StatusColors.paid;
    case InstStatus.pending:
      return StatusColors.pending;
    case InstStatus.overdue:
      return StatusColors.overdue;
    case InstStatus.skipped:
      return StatusColors.skipped;
    case InstStatus.partial:
      return StatusColors.partial;
  }
}

Color saleStatusColor(SaleStatus s) {
  switch (s) {
    case SaleStatus.active:
      return StatusColors.pending;
    case SaleStatus.overdue:
      return StatusColors.overdue;
    case SaleStatus.completed:
      return StatusColors.paid;
    case SaleStatus.cancelled:
      return StatusColors.cancelled;
  }
}

Color customerStatusColor(CustomerStatus s) {
  switch (s) {
    case CustomerStatus.good:
      return StatusColors.paid;
    case CustomerStatus.late:
      return StatusColors.overdue;
    case CustomerStatus.skipped:
      return StatusColors.skipped;
    case CustomerStatus.completed:
      return StatusColors.partial;
    case CustomerStatus.none:
      return StatusColors.cancelled;
  }
}

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(
    seedColor: brandGreen,
    brightness: b,
    primary: b == Brightness.light ? brandGreen : const Color(0xFF5FD3A2),
    secondary: accentGold,
  );
  final light = b == Brightness.light;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: light ? const Color(0xFFF4F6F5) : const Color(0xFF111413),
    appBarTheme: AppBarTheme(
      backgroundColor: light ? brandGreen : const Color(0xFF17201C),
      foregroundColor: Colors.white,
      centerTitle: false,
      titleTextStyle: const TextStyle(fontFamily: 'Roboto', fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
    ),
    cardTheme: CardThemeData(
      elevation: light ? 1.5 : 0,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 15),
      bodyLarge: TextStyle(fontSize: 16),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 50),
        textStyle: const TextStyle(fontFamily: 'Roboto', fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 66,
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontFamily: 'Roboto', fontSize: 12, fontWeight: FontWeight.w500)),
    ),
  );
}
