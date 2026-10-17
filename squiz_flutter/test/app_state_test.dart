import 'package:flutter_test/flutter_test.dart';
import 'helpers.dart';

void main() {
  test('accuracy and counts', () async {
    final app = await makeApp();
    final b = app.bank!;
    app.recordAnswer(b.byKey['ka']!, true);
    app.recordAnswer(b.byKey['kb']!, false);
    expect(app.answeredCount, 2);
    expect(app.accuracy, 50);
    expect(app.mistakes().map((q) => q.key), ['kb']);
    app.recordAnswer(b.byKey['kb']!, true); // answering a mistake correctly removes it
    expect(app.mistakes(), isEmpty);
  });

  test('streak counts consecutive days and survives a not-yet-started today', () async {
    var now = DateTime(2026, 10, 17, 10).millisecondsSinceEpoch;
    final app = await makeApp(nowMs: () => now);
    final q = app.bank!.byKey['ka']!;
    app.recordAnswer(q, true);
    now = DateTime(2026, 10, 18, 10).millisecondsSinceEpoch;
    app.recordAnswer(q, true);
    expect(app.streak, 2);
    now = DateTime(2026, 10, 19, 8).millisecondsSinceEpoch; // nothing yet today
    expect(app.streak, 2);
    now = DateTime(2026, 10, 21, 8).millisecondsSinceEpoch; // gap
    expect(app.streak, 0);
  });

  test('bookmark toggle keeps a timestamped off entry for sync', () async {
    final app = await makeApp();
    final q = app.bank!.byKey['ka']!;
    app.toggleBookmark(q);
    expect(app.isBookmarked('ka'), isTrue);
    app.toggleBookmark(q);
    expect(app.isBookmarked('ka'), isFalse);
    expect(app.bookmarks['ka'], isNotNull);
    expect(app.bookmarked(), isEmpty);
  });

  test('weakest subject needs at least 5 answers', () async {
    final app = await makeApp();
    expect(app.weakestSubject(), isNull);
  });
}
