import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'data/api.dart';
import 'data/bank.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  final prefs = await SharedPreferences.getInstance();
  final api = Api(TokenStore());
  final state = AppState(prefs: prefs, bankRepo: BankRepository(), auth: AuthApi(api), syncApi: SyncApi(api), admin: AdminApi(api));
  api.onSessionExpired = () => state.sessionExpired();
  runApp(SquizApp(state: state));
  await state.init();
}
