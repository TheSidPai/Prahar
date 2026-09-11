import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/database.dart';
import 'notifications/notifier.dart';
import 'state/app_state.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = PraharDatabase();
  await db.open();

  final notifier = Notifier();
  await notifier.init();

  final state = AppState(db: db, notifier: notifier);
  await state.load();

  // Ask before the first frame so the alarm sync below actually lands. Not
  // while the first-run tour runs: it asks at its reminders stop, where it can
  // say why, and these dialogs would otherwise cover its welcome card.
  if (!state.tourActive) await notifier.requestPermissions();
  await state.refreshAlarms();

  runApp(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const PraharApp(),
    ),
  );
}
