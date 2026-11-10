import 'package:intl/intl.dart';

final _num = NumberFormat('#,##0', 'en_US');
final _date = DateFormat('d MMM yyyy');
final _dateShort = DateFormat('d MMM');
final _month = DateFormat('MMM yyyy');

String currencySymbol = 'Rs.';

String money(num v) => '$currencySymbol ${_num.format(v)}';
String plainNum(num v) => _num.format(v);
String fmtDate(DateTime d) => _date.format(d);
String fmtDateShort(DateTime d) => _dateShort.format(d);
String fmtMonth(DateTime d) => _month.format(d);

/// Parses "5,000" / "5000" / " 5 000 " into 5000. Returns null when empty/invalid.
int? parseAmount(String? s) {
  if (s == null) return null;
  final cleaned = s.replaceAll(RegExp(r'[,\s]'), '');
  if (cleaned.isEmpty) return null;
  return int.tryParse(cleaned);
}

String daysLateLabel(int d) => d == 1 ? '1 day late' : '$d days late';

/// Converts a Pakistani local number (03xx-xxxxxxx) to international digits
/// for wa.me links (923xxxxxxxxx). Other formats are passed through digits-only.
String toWhatsAppNumber(String phone) {
  var d = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (d.startsWith('+')) return d.substring(1);
  if (d.startsWith('00')) return d.substring(2);
  if (d.startsWith('0') && d.length == 11) return '92${d.substring(1)}';
  if (d.startsWith('3') && d.length == 10) return '92$d';
  return d;
}

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}

/// Fills [Name], [Amount], [Item], [Date], [Shop Name] in a reminder template.
String fillTemplate(String template,
    {required String name,
    required String amount,
    required String item,
    required String date,
    required String shop}) {
  return template
      .replaceAll('[Name]', name)
      .replaceAll('[Amount]', amount)
      .replaceAll('[Item]', item)
      .replaceAll('[Date]', date)
      .replaceAll('[Shop Name]', shop);
}

const defaultReminderTemplate =
    'Assalam-o-Alaikum [Name], your installment of [Amount] for [Item] is due on [Date]. '
    'Please pay on time. Thank you - [Shop Name]';

/// Case-insensitive search across text fields; digit-only queries also match
/// phone / CNIC / IMEI regardless of dashes and spaces.
bool matchesQuery(String query, Iterable<String?> fields) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final qDigits = q.replaceAll(RegExp(r'\D'), '');
  final digitQuery = qDigits.isNotEmpty && qDigits.length == q.replaceAll(RegExp(r'[\s-]'), '').length;
  for (final f in fields) {
    if (f == null || f.isEmpty) continue;
    if (f.toLowerCase().contains(q)) return true;
    if (digitQuery && f.replaceAll(RegExp(r'\D'), '').contains(qDigits)) return true;
  }
  return false;
}
