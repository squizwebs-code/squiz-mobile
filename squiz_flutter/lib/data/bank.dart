import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class Subject {
  const Subject(this.id, this.name);
  final String id, name;
}

class Question {
  const Question({required this.id, required this.key, required this.text, required this.options, required this.answer, required this.explanation, required this.unitId, required this.subject, required this.grade, this.image});
  final String id; // id inside its bank
  final String key; // content key: identical for the same question in any bank/grade; state is stored against this
  final String text;
  final List<String> options;
  final int answer;
  final String explanation; // empty when the source has none - nothing is ever invented
  final String unitId, subject;
  final int grade;
  final String? image;

  /// Questions whose answer key matches no option are dropped when the bank loads, so this always holds for loaded data.
  bool get playable => answer >= 0 && answer < options.length && options.length >= 2;
  bool get hasExplanation => explanation.trim().isNotEmpty;
}

class UnitData {
  const UnitData({required this.id, required this.subject, required this.grade, required this.no, required this.title, required this.kind, required this.questions});
  final String id, subject, title, kind;
  final int grade, no;
  final List<Question> questions;
  bool get isQuick => kind == 'quick';
  String get label => isQuick ? 'Quick check' : title;
}

class QuestionBank {
  QuestionBank._(this.subjects, this.units, this.generated, this.source) {
    for (final u in units) {
      for (final q in u.questions) {
        byKey.putIfAbsent(q.key, () => q);
      }
    }
  }

  final List<Subject> subjects;
  final List<UnitData> units;
  final String generated;
  final BankSource source;
  final Map<String, Question> byKey = {};

  int get questionCount => byKey.length;
  Subject? subject(String id) {
    for (final s in subjects) {
      if (s.id == id) return s;
    }
    return null;
  }

  String subjectName(String id) => subject(id)?.name ?? id;

  /// Units that apply to a grade. Grade 0 in the source means "all grades" (quick checks).
  List<UnitData> unitsFor(int grade, {String? subject}) => [
        for (final u in units)
          if ((u.grade == grade || u.grade == 0) && (subject == null || u.subject == subject) && u.questions.isNotEmpty) u
      ];

  List<Question> questionsFor(int grade, {String? subject, String? unit}) {
    final seen = <String>{};
    final out = <Question>[];
    for (final u in unitsFor(grade, subject: subject)) {
      if (unit != null && u.id != unit) continue;
      for (final q in u.questions) {
        if (seen.add(q.key)) out.add(q);
      }
    }
    return out;
  }

  List<Subject> subjectsFor(int grade) => [
        for (final s in subjects)
          if (unitsFor(grade, subject: s.id).isNotEmpty) s
      ];

  int countFor(int grade, String subject) => questionsFor(grade, subject: subject).length;

  factory QuestionBank.fromJson(Map<String, dynamic> j, BankSource source) {
    final subjects = [for (final s in (j['subjects'] as List? ?? const [])) Subject(s['id'].toString(), (s['name'] ?? s['id']).toString())];
    final units = <UnitData>[];
    for (final raw in (j['units'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(raw as Map);
      final uid = (m['id'] ?? '').toString();
      final subject = (m['subject'] ?? '').toString();
      final grade = (m['grade'] as num?)?.toInt() ?? 0;
      final qs = <Question>[];
      for (final qr in (m['qs'] as List? ?? const [])) {
        final q = Map<String, dynamic>.from(qr as Map);
        final text = (q['q'] ?? '').toString();
        final question = Question(
          id: (q['id'] ?? '').toString(),
          key: (q['k'] ?? q['id'] ?? text).toString(),
          text: text,
          options: [for (final o in (q['o'] as List? ?? const [])) o.toString()],
          answer: q['a'] is int ? q['a'] as int : -1,
          explanation: (q['e'] ?? '').toString(),
          unitId: uid,
          subject: subject,
          grade: grade,
          image: q['img']?.toString(),
        );
        if (question.playable && (q['bad'] != true)) qs.add(question);
      }
      units.add(UnitData(id: uid, subject: subject, grade: grade, no: (m['no'] as num?)?.toInt() ?? 0, title: (m['title'] ?? 'Unit').toString(), kind: (m['kind'] ?? 'unit').toString(), questions: qs));
    }
    return QuestionBank._(subjects, units, (j['generated'] ?? '').toString(), source);
  }
}

enum BankSource { bundled, server }

/// Loads the question bank. The bundled bank always works offline; a copy downloaded from the server (after sign-in)
/// replaces it so edits made by administrators reach the phone.
class BankRepository {
  BankRepository({AssetBundle? bundle, Future<Directory> Function()? dir}) : _bundle = bundle ?? rootBundle, _dir = dir ?? getApplicationSupportDirectory;
  final AssetBundle _bundle;
  final Future<Directory> Function() _dir;

  Future<File> _file() async => File('${(await _dir()).path}/bank_server.json');
  Future<File> _etagFile() async => File('${(await _dir()).path}/bank_server.etag');

  Future<QuestionBank> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final map = await compute(_decode, await f.readAsString());
        final bank = QuestionBank.fromJson(map, BankSource.server);
        if (bank.questionCount > 0) return bank;
      }
    } catch (_) {/* a damaged cache must never stop the app: fall back to the bundled bank */}
    final map = await compute(_decode, await _bundle.loadString('assets/data/bank.json'));
    return QuestionBank.fromJson(map, BankSource.bundled);
  }

  Future<String?> savedEtag() async {
    try {
      final f = await _etagFile();
      return await f.exists() ? await f.readAsString() : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveServerBank(String json, String? etag) async {
    final f = await _file();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(json, flush: true);
    await tmp.rename(f.path); // atomic replace: a crash never leaves half a file
    if (etag != null) await (await _etagFile()).writeAsString(etag);
  }

  Future<void> deleteServerBank() async {
    for (final f in [await _file(), await _etagFile()]) {
      if (await f.exists()) await f.delete();
    }
  }
}

Map<String, dynamic> _decode(String s) => jsonDecode(s) as Map<String, dynamic>;
