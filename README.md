# Installment Tracker

Offline-first Android app for a shop owner who sells phones (and other items) on installments.
Built from [`Installment_x5f_Tracker_x5f_App_x5f_Spec.md`](Installment_x5f_Tracker_x5f_App_x5f_Spec.md), MVP scope (spec section 8).

**Flow:** Add customer → New sale (item + price + advance + monthly) → the app builds the
installment schedule → collect payments → dashboard shows who is Due, Late, Skipped or Paid.

## Install on a phone

1. Download `app-release.apk` (link in the workspace chat / Media tab).
2. Open it on the phone. Android asks to allow installs from that app (Chrome / Files / WhatsApp): allow it.
3. Tap **Install**, then **Open**. Android 7.0 (API 24) or newer.

On first launch: enter the shop name, optionally set a PIN, and optionally load sample data to try things out
(Settings → Delete all data clears it).

## What's in the MVP

| Area | What it does |
|---|---|
| Dashboard | To collect this month, collected, pending/overdue, total outstanding; Due Today, Overdue (days late), Due This Week, month calendar with dots, recent payments; filters + search (name, phone, CNIC, item, IMEI) |
| Customers | Add/edit (photo, CNIC, address, guarantor, notes), list with status badge, detail with totals, next due, Call/WhatsApp, payment timeline, ledger export (PDF / CSV) |
| Items | Name, category, brand, model, IMEI (duplicate warning), cost (private), price, photos, stock status, sale history |
| Sales | 5-step wizard (customer → item → plan → security docs → review); monthly / weekly / bi-weekly / every N days; auto or manual count; last installment absorbs remainder; month-end dates clamp (31 Jan → 28 Feb) |
| Sale detail | Progress bar, summary cards, colour-coded schedule (Paid green, Pending yellow, Overdue red, Skipped grey, Partial blue), skip / un-skip with reason, security document gallery, notes, edit plan (until installments are paid), cancel, delete |
| Payments | Full / partial / extra (ask: apply to next, or keep as advance), any past date, method (customisable list), bank / transaction ID / cheque no., receipt photo; edit with audit history; delete; share text receipt; ledger with date-range and method filters |
| Reports | Monthly (collected by method, expected, missed, who paid / skipped / overdue) with PDF export; overall totals, private profit, best payers, most late, top items |
| Settings | Shop profile, PIN lock (salted SHA-256, re-locks after 45 s in background), payment methods, default due day, WhatsApp template, currency, light/dark theme, backup/restore (.zip with DB + photos), CSV export of all tables, diagnostics log, sample data, delete all data |

### Not in this MVP (spec Phase 2 or follow-ups)

- Push notifications / scheduled reminders (spec 3.6 "Phase 1.5"). Reminders today are in-app plus 1-tap WhatsApp / SMS / Call.
- Fingerprint / Face unlock (PIN only), Urdu translation, cloud sync, multi-user, expenses, late fees, Bluetooth receipt printing.
- Excel export is CSV (opens in Excel / Google Sheets).

## Monitoring

The app has no backend, so it cannot alert anyone by itself (a notify token must never ship inside an APK).
Every key operation and every uncaught error is written to a local log (`lib/core/app_log.dart`).
The owner opens **Settings → Diagnostics log**, which shows the error count, and can share the log in one tap.
Remote alerting arrives with cloud sync (Phase 2) through a server that holds the token.

## Develop

Toolchain: Flutter 3.47 (stable), Android SDK platform 36, build-tools 36.0.0, NDK 28.2.13676358, JDK 17+.

```bash
flutter pub get
flutter test                              # 30 tests: logic, SQLite repository, UI smoke
flutter build apk --release               # build/app/outputs/flutter-apk/app-release.apk
```

Release signing reads `android/key.properties` (gitignored):

```properties
storeFile=/path/to/installment-release.jks
storePassword=...
keyAlias=installment
keyPassword=...
```

Without it the release build is signed with the debug key. **Every update must be signed with the same key as
the installed APK**, or Android refuses to install it over the old one.

Screens + walkthrough video:

```bash
SCREENSHOTS_DIR=build/screens flutter test test/screenshots_test.dart
tool/make_walkthrough.sh build/screens build/walkthrough.mp4
```

### Layout

```
lib/
  logic/schedule.dart      pure business rules: schedule generation, payment allocation, statuses
  data/                    SQLite schema (database.dart), models, AppState repository, backup, sample data
  services/                PDF / CSV export, call / WhatsApp / SMS launchers
  ui/                      theme (status colours), shared widgets, PIN lock, screens/
test/
  schedule_test.dart       spec section 9 scenarios 1-4 + edge cases
  app_state_test.dart      real SQLite (sqflite_common_ffi): scenarios 1, 4, 5 persisted, backup round-trip
  widget_test.dart         every main screen renders at phone size without overflow
```

Installment paid amounts and statuses are **derived**: they are recomputed from the payments on every change, so
editing or deleting a payment updates every total at once (spec scenario 4). The `paid_amount` / `status`
columns in `installments` are a cache written back for exports.
