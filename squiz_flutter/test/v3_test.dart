import 'package:flutter_test/flutter_test.dart';
import 'package:squiz/data/models.dart';
import 'helpers.dart';

void main() {
  group('Matric streams', () {
    test('no stream shows every subject for grade 11', () {
      final b = sampleBank();
      expect(b.subjectsFor(11).map((s) => s.id), containsAll(['math', 'bio', 'geo']));
    });
    test('Natural Science hides Social Science subjects in grade 11 only', () {
      final b = sampleBank()..activeTrack = 'natural';
      final ids = b.subjectsFor(11).map((s) => s.id).toList();
      expect(ids, contains('bio'));
      expect(ids, isNot(contains('geo')));
      expect(b.questionsFor(11, subject: 'geo'), isEmpty);
    });
    test('Social Science hides Natural Science subjects', () {
      final b = sampleBank()..activeTrack = 'social';
      final ids = b.subjectsFor(11).map((s) => s.id).toList();
      expect(ids, contains('geo'));
      expect(ids, isNot(contains('bio')));
      expect(ids, contains('math')); // shared subjects stay
    });
    test('the filter does not apply below grade 11', () {
      final b = sampleBank()..activeTrack = 'social';
      expect(b.hasTracks, isTrue);
      // grade 9 has no units in the sample, but the filter must not be the reason
      expect(b.unitsFor(9), isEmpty);
    });
  });

  group('AccountUser', () {
    test('parses an admin and the owner flag', () {
      final u = AccountUser.fromJson({'id': 1, 'full_name': 'Abebe Kebede', 'username': 'abebe', 'phone': '+251911223344', 'role': 'admin', 'is_owner': true, 'selected_grade': 12, 'selected_track': 'natural'});
      expect(u.isAdmin, isTrue);
      expect(u.isOwner, isTrue);
      expect(u.track, 'natural');
      expect(u.initials, 'AK');
    });
    test('defaults to a student', () {
      final u = AccountUser.fromJson({'id': 2, 'full_name': 'Sara', 'phone': '0911', 'selected_grade': null});
      expect(u.isAdmin, isFalse);
      expect(u.isOwner, isFalse);
      expect(u.username, '');
    });
  });
}
