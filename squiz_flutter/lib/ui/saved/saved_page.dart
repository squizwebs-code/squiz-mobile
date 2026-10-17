import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/bank.dart';
import '../app_scope.dart';
import '../quiz/launcher.dart';
import '../widgets/common.dart';

/// Bookmarked, Mistakes and Flagged questions. Works as a bottom-navigation tab and as a pushed route.
class SavedPage extends StatefulWidget {
  const SavedPage({super.key, this.initialTab = 0});
  final int initialTab;
  @override
  State<SavedPage> createState() => _SavedPageState();
}

class _SavedPageState extends State<SavedPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this, initialIndex: widget.initialTab.clamp(0, 2));

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final lists = [app.bookmarked(), app.mistakes(), app.flagged()];
    const names = ['Bookmarked', 'Mistakes', 'Flagged'];
    final pushed = Navigator.of(context).canPop();
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: pushed,
        title: const Text('Saved'),
        bottom: TabBar(controller: _tabs, tabs: [for (final (i, n) in names.indexed) Tab(text: '$n (${lists[i].length})')]),
      ),
      body: TabBarView(controller: _tabs, children: [
        _SavedList(kind: 0, questions: lists[0], title: 'Bookmarked'),
        _SavedList(kind: 1, questions: lists[1], title: 'Mistakes'),
        _SavedList(kind: 2, questions: lists[2], title: 'Flagged'),
      ]),
    );
  }
}

class _SavedList extends StatelessWidget {
  const _SavedList({required this.kind, required this.questions, required this.title});
  final int kind; // 0 bookmarks, 1 mistakes, 2 flags
  final List<Question> questions;
  final String title;

  static const _empty = [
    ('Nothing bookmarked', 'Tap the bookmark on any question to keep it here.'),
    ('No mistakes to review', 'Questions you get wrong will collect here until you answer them correctly.'),
    ('Nothing flagged', 'Flag questions you want to look at again.'),
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (questions.isEmpty) {
      return EmptyState(icon: [Icons.bookmark_border_rounded, Icons.check_circle_outline_rounded, Icons.flag_outlined][kind], title: _empty[kind].$1, text: _empty[kind].$2);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        FilledButton.icon(
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text('Practise these ${questions.length}'),
          onPressed: () => QuizLauncher.practice(context, title: title, questions: questions, shuffle: false),
        ),
        const SizedBox(height: 12),
        for (final (i, q) in questions.indexed)
          StaggeredIn(
            index: i < 8 ? i : 8,
            child: kind == 1
                ? _QuestionCard(q: q) // a mistake leaves this list by answering it correctly, not by swiping
                : Dismissible(
                    key: ValueKey('$kind-${q.key}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      decoration: BoxDecoration(color: context.sq.bad.withValues(alpha: .15), borderRadius: BorderRadius.circular(16)),
                      child: Icon(Icons.delete_outline_rounded, color: context.sq.bad),
                    ),
                    onDismissed: (_) {
                      if (kind == 0) {
                        app.toggleBookmark(q);
                      } else {
                        app.toggleFlag(q);
                      }
                      final m = ScaffoldMessenger.of(context);
                      m.clearSnackBars();
                      m.showSnackBar(SnackBar(
                        content: Text(kind == 0 ? 'Bookmark removed' : 'Flag removed'),
                        action: SnackBarAction(
                            label: 'Undo',
                            onPressed: () {
                              if (kind == 0) {
                                app.toggleBookmark(q);
                              } else {
                                app.toggleFlag(q);
                              }
                            }),
                      ));
                    },
                    child: _QuestionCard(q: q),
                  ),
          ),
      ],
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.q});
  final Question q;
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final unit = app.bank?.units.where((u) => u.id == q.unitId).firstOrNull;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SubjectBadge(q.subject, size: 28),
            const SizedBox(width: 8),
            Expanded(child: Text(unit?.label ?? '', style: context.tt.labelMedium?.copyWith(color: context.cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis)),
            IconButton(
              tooltip: app.isBookmarked(q.key) ? 'Remove bookmark' : 'Bookmark',
              visualDensity: VisualDensity.compact,
              icon: Icon(app.isBookmarked(q.key) ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: app.isBookmarked(q.key) ? context.cs.primary : null),
              onPressed: () => app.toggleBookmark(q),
            ),
          ]),
          const SizedBox(height: 6),
          Text(q.text, style: context.tt.bodyLarge),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('Try it'),
              onPressed: () => QuizLauncher.practice(context, title: 'Single question', questions: [q], shuffle: false, oneOff: true),
            ),
          ),
        ]),
      ),
    );
  }
}
