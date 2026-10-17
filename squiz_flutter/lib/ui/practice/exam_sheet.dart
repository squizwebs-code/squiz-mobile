import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/bank.dart';
import '../quiz/launcher.dart';

/// Bottom sheet that sets up an exam: question count and timer.
Future<void> showExamSheet(BuildContext context, {required String title, required List<Question> questions}) {
  if (questions.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No questions available here yet.')));
    return Future.value();
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (c) => _ExamSheet(parentContext: context, title: title, questions: questions),
  );
}

class _ExamSheet extends StatefulWidget {
  const _ExamSheet({required this.parentContext, required this.title, required this.questions});
  final BuildContext parentContext;
  final String title;
  final List<Question> questions;
  @override
  State<_ExamSheet> createState() => _ExamSheetState();
}

class _ExamSheetState extends State<_ExamSheet> {
  late int count = widget.questions.length >= 20 ? 20 : widget.questions.length;
  int? minutes = 30;

  @override
  Widget build(BuildContext context) {
    final total = widget.questions.length;
    final counts = {for (final n in const [10, 20, 30, 40, 50]) if (n < total) n, total}.toList()..sort();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Start an exam', style: context.tt.titleLarge),
            Text(widget.title, style: context.tt.bodyMedium?.copyWith(color: context.cs.onSurfaceVariant)),
            const SizedBox(height: 20),
            Text('Questions', style: context.tt.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final n in counts) ChoiceChip(label: Text(n == total ? 'All $n' : '$n'), selected: count == n, onSelected: (_) => setState(() => count = n)),
            ]),
            const SizedBox(height: 20),
            Text('Timer', style: context.tt.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(label: const Text('No timer'), selected: minutes == null, onSelected: (_) => setState(() => minutes = null)),
              for (final m in const [10, 15, 20, 30, 45, 60, 90]) ChoiceChip(label: Text('$m min'), selected: minutes == m, onSelected: (_) => setState(() => minutes = m)),
            ]),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: context.sq.soft, borderRadius: BorderRadius.circular(14)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline_rounded, size: 20, color: context.sq.link),
                const SizedBox(width: 10),
                Expanded(child: Text('Questions are shuffled. Correct answers are shown only after you submit. You can change an answer and mark questions for review until then.', style: context.tt.bodySmall)),
              ]),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text('Start · $count questions${minutes == null ? '' : ' · $minutes min'}'),
                onPressed: () {
                  Navigator.pop(context);
                  QuizLauncher.exam(widget.parentContext, title: widget.title, questions: widget.questions, count: count, minutes: minutes);
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
