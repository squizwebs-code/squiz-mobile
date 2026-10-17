import 'package:shared_preferences/shared_preferences.dart';
import 'package:squiz/data/api.dart';
import 'package:squiz/data/bank.dart';
import 'package:squiz/state/app_state.dart';

const sampleBankJson = {
  'generated': 'test',
  'subjects': [
    {'id': 'math', 'name': 'Mathematics'},
    {'id': 'bio', 'name': 'Biology'},
  ],
  'units': [
    {
      'id': 'u1', 'subject': 'math', 'grade': 11, 'no': 1, 'title': 'Algebra', 'kind': 'unit',
      'qs': [
        {'id': 'a', 'k': 'ka', 'q': '1+1?', 'o': ['1', '2', '3'], 'a': 1, 'e': 'Because.'},
        {'id': 'b', 'k': 'kb', 'q': '2+2?', 'o': ['3', '4'], 'a': 1},
        {'id': 'bad', 'k': 'kbad', 'q': 'broken', 'o': ['x', 'y'], 'a': 9}, // answer index outside options: must be dropped
      ],
    },
    {
      'id': 'u2', 'subject': 'bio', 'grade': 11, 'no': 1, 'title': 'Cells', 'kind': 'unit',
      'qs': [
        {'id': 'c', 'k': 'kc', 'q': 'Powerhouse?', 'o': ['Nucleus', 'Mitochondria'], 'a': 1},
        {'id': 'a2', 'k': 'ka', 'q': '1+1?', 'o': ['1', '2', '3'], 'a': 1}, // same content key as "a": counted once
      ],
    },
  ],
};

QuestionBank sampleBank() => QuestionBank.fromJson(Map<String, dynamic>.from(sampleBankJson), BankSource.bundled);

Future<AppState> makeApp({int Function()? nowMs}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final api = Api(TokenStore());
  final app = AppState(prefs: prefs, bankRepo: BankRepository(), auth: AuthApi(api), syncApi: SyncApi(api), nowMs: nowMs);
  app.bank = sampleBank();
  return app;
}
