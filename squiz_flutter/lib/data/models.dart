/// Small value types shared by state, storage and sync.

/// One entry of a synced map: when it was last changed and whether it is on (1) or off (0).
class Entry {
  const Entry(this.ts, this.on);
  final int ts; // milliseconds since epoch
  final bool on;
  List<int> toJson() => [ts, on ? 1 : 0];
  static Entry? fromJson(dynamic v) {
    if (v is List && v.length == 2 && v[0] is num && v[1] is num) return Entry((v[0] as num).toInt(), (v[1] as num) != 0);
    return null;
  }
}

class HistoryItem {
  const HistoryItem({required this.id, required this.title, required this.mode, required this.total, required this.correct, required this.ts, this.seconds});
  final String id, title, mode; // mode: practice | exam
  final int total, correct, ts;
  final int? seconds;
  int get percent => total == 0 ? 0 : (correct * 100 / total).round();
  bool get isExam => mode == 'exam';

  Map<String, dynamic> toJson() => {'id': id, 'ti': title.length > 200 ? title.substring(0, 200) : title, 'm': mode, 'n': total, 'c': correct, 'ts': ts, if (seconds != null) 'd': seconds};
  static HistoryItem? fromJson(dynamic j) {
    if (j is! Map) return null;
    try {
      return HistoryItem(id: j['id'] as String, title: j['ti'] as String, mode: j['m'] as String, total: (j['n'] as num).toInt(), correct: (j['c'] as num).toInt(), ts: (j['ts'] as num).toInt(), seconds: (j['d'] as num?)?.toInt());
    } catch (_) {
      return null;
    }
  }
}

class AccountUser {
  const AccountUser({required this.id, required this.fullName, required this.phone, this.grade, this.mustChangePassword = false});
  final int id;
  final String fullName, phone;
  final int? grade;
  final bool mustChangePassword;
  factory AccountUser.fromJson(Map<String, dynamic> j) => AccountUser(id: j['id'] as int, fullName: j['full_name'] as String, phone: j['phone'] as String, grade: j['selected_grade'] as int?, mustChangePassword: j['must_change_password'] == true);
  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }
}