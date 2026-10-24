import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/brand.dart';
import '../../core/theme.dart';
import '../../data/api.dart';
import '../app_scope.dart';
import '../widgets/common.dart';

extension AdminContext on BuildContext {
  AdminApi get adminApi => AppScope.read(this).admin!;
}

/// Runs an admin call and shows the server's message when it fails. Returns null on failure.
Future<T?> guarded<T>(BuildContext context, Future<T> Function() f, {String? success}) async {
  try {
    final r = await f();
    if (success != null && context.mounted) showSnack(context, success);
    return r;
  } on ApiException catch (e) {
    if (context.mounted) showSnack(context, e.offline ? 'No connection. Please try again.' : e.message);
    return null;
  }
}

String shortDate(dynamic iso) {
  final d = DateTime.tryParse((iso ?? '').toString())?.toLocal();
  if (d == null) return '–';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

String shortDateTime(dynamic iso) {
  final d = DateTime.tryParse((iso ?? '').toString())?.toLocal();
  if (d == null) return '–';
  return '${shortDate(iso)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String ago(dynamic iso) {
  final d = DateTime.tryParse((iso ?? '').toString());
  if (d == null) return 'never';
  return relativeTime(d.millisecondsSinceEpoch, DateTime.now().millisecondsSinceEpoch);
}

/// Saves bytes through the platform's save dialog (works on Android, iOS, desktop and web).
Future<void> saveBytes(BuildContext context, List<int> bytes, String fileName) async {
  try {
    final path = await FilePicker.platform.saveFile(dialogTitle: 'Save $fileName', fileName: fileName, bytes: Uint8List.fromList(bytes));
    if (context.mounted) showSnack(context, path == null && !kIsWeb ? 'Save cancelled' : 'Saved $fileName');
  } catch (_) {
    if (context.mounted) showSnack(context, 'Could not save the file on this device.');
  }
}

class PickedFile {
  PickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

Future<PickedFile?> pickFile(List<String> extensions) async {
  final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: extensions, withData: true);
  final f = r?.files.single;
  if (f == null || f.bytes == null) return null;
  return PickedFile(f.name, f.bytes!);
}

Future<void> copyText(BuildContext context, String text, String what) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showSnack(context, '$what copied');
}

/// Loads data, shows a spinner / the server's error with a retry button, and hands the loaded data plus a reload function to [builder].
class Loader<T> extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  late Future<T> _f = widget.load();

  Future<void> _reload() async {
    final next = widget.load();
    setState(() => _f = next);
    try {
      await next;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: _f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()));
          if (snap.hasError) {
            final e = toApiException(snap.error!);
            return Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(e.offline ? Icons.cloud_off_rounded : Icons.error_outline_rounded, size: 40, color: context.cs.outline),
                const SizedBox(height: 12),
                Text(e.message, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
              ]),
            );
          }
          return widget.builder(context, snap.data as T, _reload);
        },
      );
}

/// Keeps admin content readable on wide screens.
class Constrained extends StatelessWidget {
  const Constrained({super.key, required this.child, this.maxWidth = 1100});
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) => Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child));
}

class KpiCard extends StatelessWidget {
  const KpiCard({super.key, required this.label, required this.value, this.icon, this.sub, this.color});
  final String label;
  final String value;
  final IconData? icon;
  final String? sub;
  final Color? color;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (icon != null) ...[Icon(icon, size: 18, color: color ?? context.sq.link), const SizedBox(width: 6)],
              Expanded(child: Text(label, style: context.tt.labelMedium?.copyWith(color: context.cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 6),
            Text(value, style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            if (sub != null) Text(sub!, style: context.tt.labelSmall?.copyWith(color: context.cs.onSurfaceVariant)),
          ]),
        ),
      );
}

/// Vertical bars with a label under each bar and the value on top. No chart package needed.
class BarsChart extends StatelessWidget {
  const BarsChart({super.key, required this.values, required this.labels, this.height = 120, this.color, this.showEvery = 1});
  final List<num> values;
  final List<String> labels;
  final double height;
  final Color? color;
  final int showEvery;
  @override
  Widget build(BuildContext context) {
    final max = values.fold<num>(0, (a, b) => b > a ? b : a);
    final c = color ?? kBrand;
    return SizedBox(
      height: height + 36,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final (i, v) in values.indexed)
          Expanded(
            child: Tooltip(
              message: '${labels[i]}: $v',
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (v > 0 && values.length <= 12) Text('$v', style: context.tt.labelSmall),
                const SizedBox(height: 2),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  height: max == 0 ? 2 : (v / max * height).clamp(2, height).toDouble(),
                  decoration: BoxDecoration(color: v == 0 ? context.cs.outlineVariant : c, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                ),
                const SizedBox(height: 4),
                SizedBox(height: 16, child: i % showEvery == 0 ? Text(labels[i], style: context.tt.labelSmall?.copyWith(color: context.cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.clip) : null),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Smooth-ish line for a daily series.
class LineChart extends StatelessWidget {
  const LineChart({super.key, required this.values, this.height = 110, this.color});
  final List<num> values;
  final double height;
  final Color? color;
  @override
  Widget build(BuildContext context) => SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: _LinePainter(values, color ?? kBrand, context.cs.outlineVariant)));
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.v, this.color, this.grid);
  final List<num> v;
  final Color color, grid;
  @override
  void paint(Canvas canvas, Size size) {
    final g = Paint()..color = grid..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = size.height * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), g);
    }
    if (v.isEmpty) return;
    final max = v.fold<num>(1, (a, b) => b > a ? b : a).toDouble();
    Offset pt(int i) => Offset(v.length == 1 ? size.width / 2 : size.width * i / (v.length - 1), size.height - (v[i] / max) * (size.height - 8) - 4);
    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < v.length; i++) {
      path.lineTo(pt(i).dx, pt(i).dy);
    }
    final fill = Path.from(path)..lineTo(size.width, size.height)..lineTo(0, size.height)..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: .12));
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(pt(v.length - 1), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_LinePainter o) => o.v != v || o.color != color;
}

/// Label, horizontal bar and value; used for accuracy by subject and similar lists.
class HBar extends StatelessWidget {
  const HBar({super.key, required this.label, required this.fraction, required this.value, this.color, this.sub});
  final String label, value;
  final double fraction;
  final Color? color;
  final String? sub;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          SizedBox(width: 110, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.labelLarge)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(value: fraction.clamp(0, 1).toDouble(), minHeight: 10, color: color ?? kBrand, backgroundColor: context.cs.surfaceContainerHigh),
            ),
          ),
          SizedBox(width: sub == null ? 52 : 92, child: Text(sub == null ? value : '$value · $sub', textAlign: TextAlign.right, style: context.tt.labelMedium)),
        ]),
      );
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.trailing, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: context.tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                if (subtitle != null) Text(subtitle!, style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
              ])),
              if (trailing != null) trailing!,
            ]),
            const SizedBox(height: 12),
            child,
          ]),
        ),
      );
}

Future<String?> askText(BuildContext context, {required String title, String? label, String initial = '', String ok = 'Save', int maxLines = 1, bool obscure = false}) async {
  final c = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true, maxLines: obscure ? 1 : maxLines, obscureText: obscure, decoration: InputDecoration(labelText: label)),
      actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, c.text), child: Text(ok))],
    ),
  );
  c.dispose();
  return r;
}
