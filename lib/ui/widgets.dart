import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/app_log.dart';
import '../core/format.dart';
import '../data/app_state.dart';
import 'lock.dart';

class StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool dense;
  const StatusChip(this.label, this.color, {super.key, this.dense = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: dense ? 7 : 10, vertical: dense ? 2 : 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: dense ? 11 : 12)),
      );
}

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;
  const StatCard(
      {super.key,
      required this.title,
      required this.value,
      required this.color,
      required this.icon,
      this.onTap});

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 5))),
            padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(title,
                          maxLines: 2,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12.5))),
                ]),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
                ),
              ],
            ),
          ),
        ),
      );
}

class SectionHeader extends StatelessWidget {
  final String title;
  final int? count;
  final Widget? trailing;
  final Color? color;
  const SectionHeader(this.title, {super.key, this.count, this.trailing, this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
        child: Row(children: [
          Flexible(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700, color: color)),
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            StatusChip('$count', color ?? Theme.of(context).colorScheme.primary, dense: true),
          ],
          const Spacer(),
          if (trailing != null) trailing!,
        ]),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 15)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

class InlineEmpty extends StatelessWidget {
  final String text;
  const InlineEmpty(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
      );
}

/// Shows a stored photo, or initials when there is none.
class PersonAvatar extends StatelessWidget {
  final String name;
  final String? photo;
  final double radius;
  const PersonAvatar({super.key, required this.name, this.photo, this.radius = 22});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final f = photo == null ? null : app.photos.file(photo!);
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundImage: f != null && f.existsSync() ? FileImage(f) : null,
      child: Text(initials(name),
          style: TextStyle(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
              fontSize: radius * 0.7)),
    );
  }
}

class PhotoThumb extends StatelessWidget {
  final String photo;
  final double size;
  final String? caption;
  final VoidCallback? onLongPress;
  const PhotoThumb(this.photo, {super.key, this.size = 84, this.caption, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final f = context.read<AppState>().photos.file(photo);
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PhotoViewer(file: f, caption: caption))),
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: f.existsSync()
            ? Image.file(f, width: size, height: size, fit: BoxFit.cover, cacheWidth: (size * 3).toInt())
            : Container(
                width: size,
                height: size,
                color: Colors.black12,
                child: const Icon(Icons.broken_image_outlined)),
      ),
    );
  }
}

class PhotoViewer extends StatelessWidget {
  final File file;
  final String? caption;
  const PhotoViewer({super.key, required this.file, this.caption});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, title: Text(caption ?? 'Photo')),
        body: Center(
          child: InteractiveViewer(maxScale: 6, child: Image.file(file)),
        ),
      );
}

/// Asks camera or gallery, copies the picked image into the app's private
/// photo folder and returns its stored name (null when cancelled).
Future<String?> pickAndStorePhoto(BuildContext context, {String title = 'Add photo'}) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
        ),
        ListTile(
          leading: const Icon(Icons.photo_camera_outlined),
          title: const Text('Take photo'),
          onTap: () => Navigator.pop(ctx, ImageSource.camera),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('Choose from gallery'),
          onTap: () => Navigator.pop(ctx, ImageSource.gallery),
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (source == null || !context.mounted) return null;
  final app = context.read<AppState>();
  try {
    final x = await AppLockController.instance.whileExternal(() => ImagePicker()
        .pickImage(source: source, maxWidth: 1800, maxHeight: 1800, imageQuality: 78));
    if (x == null) return null;
    return await app.photos.importFile(x.path);
  } catch (e, st) {
    AppLog.error('Photo pick failed', e, st);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not get photo: $e')));
    }
    return null;
  }
}

Future<bool> confirm(BuildContext context,
    {required String title,
    required String message,
    String confirmLabel = 'Yes',
    bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: Colors.red.shade700) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> promptText(BuildContext context,
    {required String title, String? initial, String hint = '', int maxLines = 3}) async {
  final ctrl = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: maxLines,
        minLines: 1,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
      ],
    ),
  );
  return r;
}

class MoneyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool required;
  final String? helper;
  final ValueChanged<String>? onChanged;
  final String? Function(int?)? extraValidator;
  const MoneyField(
      {super.key,
      required this.controller,
      required this.label,
      this.required = false,
      this.helper,
      this.onChanged,
      this.extraValidator});

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          prefixText: '$currencySymbol ',
          helperText: helper,
        ),
        onChanged: onChanged,
        validator: (v) {
          final n = parseAmount(v);
          if (required && n == null) return 'Required';
          if (extraValidator != null) return extraValidator!(n);
          return null;
        },
      );
}

class DateField extends StatelessWidget {
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? firstDate;
  const DateField(
      {super.key, required this.label, required this.value, required this.onChanged, this.firstDate});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: value,
            firstDate: firstDate ?? DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (d != null) onChanged(d);
        },
        child: InputDecorator(
          decoration: InputDecoration(
              labelText: label, suffixIcon: const Icon(Icons.calendar_month_outlined)),
          child: Text(fmtDate(value), style: const TextStyle(fontSize: 16)),
        ),
      );
}

class SearchBox extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  const SearchBox({super.key, required this.hint, required this.onChanged, this.controller});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
          ),
        ),
      );
}

class ChoiceChips<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;
  const ChoiceChips(
      {super.key,
      required this.values,
      required this.selected,
      required this.label,
      required this.onSelected});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            for (final v in values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(label(v)),
                  selected: v == selected,
                  onSelected: (_) => onSelected(v),
                ),
              ),
          ],
        ),
      );
}

class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  const InfoRow(this.label, this.value, {super.key, this.icon});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
            const SizedBox(width: 8),
          ],
          SizedBox(
              width: 110,
              child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.outline))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
        ]),
      );
}

void toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
