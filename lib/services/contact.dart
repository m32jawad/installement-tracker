import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_log.dart';
import '../core/format.dart';

Future<void> _open(BuildContext context, Uri uri, String what) async {
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) throw Exception('No app to handle $what');
  } catch (e, st) {
    AppLog.error('Could not open $what', e, st);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not open $what')));
    }
  }
}

Future<void> callPhone(BuildContext context, String phone) =>
    _open(context, Uri(scheme: 'tel', path: phone.replaceAll(' ', '')), 'phone dialer');

Future<void> openWhatsApp(BuildContext context, String phone, String message) =>
    _open(
        context,
        Uri.parse(
            'https://wa.me/${toWhatsAppNumber(phone)}?text=${Uri.encodeComponent(message)}'),
        'WhatsApp');

Future<void> sendSms(BuildContext context, String phone, String message) => _open(
    context,
    Uri(scheme: 'sms', path: phone.replaceAll(' ', ''), queryParameters: {'body': message}),
    'SMS app');
