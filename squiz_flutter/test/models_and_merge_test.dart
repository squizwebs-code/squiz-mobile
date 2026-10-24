import 'package:flutter_test/flutter_test.dart';
import 'package:squiz/data/models.dart';
import 'package:squiz/state/app_state.dart';
import 'helpers.dart';

void main() {
  group('bank parsing', () {
    test('drops questions whose answer index is outside the options', () {
      final b = sampleBank();
      expect(b.byKey.containsKey('kbad'), isFalse);
      expect(b.byKey.keys.toSet(), {'ka', 'kb', 'kc', 'kg1'});
    });
    test('same content key across units is one question', () {
      final b = sampleBank();
      expect(b.questionsFor(11).length, 4);
      expect(b.questionsFor(11, subject: 'math').length, 2);
    });
    test('missing explanation stays empty', () {
      final q = sampleBank().byKey['kb']!;
      expect(q.hasExplanation, isFalse);
      expect(q.explanation, '');
    });
    test('grade without units has no subjects', () => expect(sampleBank().subjectsFor(9), isEmpty));
  });

  group('Merge', () {
    test('entries: newer timestamp wins, tie keeps local', () {
      final local = {'a': const Entry(10, true), 'b': const Entry(5, true)};
      final remote = {'a': const Entry(9, false), 'b': const Entry(5, false), 'c': const Entry(1, true)};
      final m = Merge.entries(local, remote);
      expect(m['a']!.on, isTrue);
      expect(m['b']!.on, isTrue);
      expect(m['c']!.on, isTrue);
      expect(Merge.entries(remote, local)['a']!.on, isTrue); // order does not change the winner when timestamps differ
    });
    test('history: union by id, newest first, capped', () {
      HistoryItem h(String id, int ts) => HistoryItem(id: id, title: 't', mode: 'practice', total: 2, correct: 1, ts: ts);
      final m = Merge.history([h('x', 1), h('y', 3)], [h('y', 3), h('z', 2)], cap: 2);
      expect(m.map((e) => e.id), ['y', 'z']);
    });
    test('Entry json round trip and rejection of bad shapes', () {
      expect(Entry.fromJson(const Entry(7, true).toJson())!.ts, 7);
      expect(Entry.fromJson([1]), isNull);
      expect(Entry.fromJson('x'), isNull);
    });
  });
}
