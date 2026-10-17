import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../app_scope.dart';

Future<void> showGradeSheet(BuildContext context) {
  final app = AppScope.read(context);
  return showModalBottomSheet<void>(
    context: context,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Choose your grade', style: c.tt.titleLarge),
          const SizedBox(height: 4),
          Text('Subjects and questions update to match.', style: c.tt.bodyMedium?.copyWith(color: c.cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          for (final g in const [9, 10, 11, 12])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: app.grade == g ? c.cs.primary : c.cs.outlineVariant, width: app.grade == g ? 2 : 1)),
                leading: Icon(app.grade == g ? Icons.radio_button_checked : Icons.radio_button_off, color: app.grade == g ? c.cs.primary : c.cs.outline),
                title: Text('Grade $g', style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: () {
                  app.setGrade(g);
                  Navigator.pop(c);
                },
              ),
            ),
        ]),
      ),
    ),
  );
}
