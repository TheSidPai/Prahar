import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/preferences.dart';
import '../state/app_state.dart';
import 'home_screen.dart';
import 'theme.dart';

class PraharApp extends StatelessWidget {
  const PraharApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilds when Prefs changes, so the theme choice takes effect the moment
    // the user picks it rather than on the next launch.
    final prefs = context.select<AppState, Prefs>((s) => s.prefs);
    return MaterialApp(
      title: 'Prahar',
      debugShowCheckedModeBanner: false,
      themeMode: switch (prefs.themeChoice) {
        ThemeChoice.system => ThemeMode.system,
        ThemeChoice.light => ThemeMode.light,
        ThemeChoice.dark => ThemeMode.dark,
      },
      theme: PraharTheme.of(Brightness.light, material: prefs.materialChoice),
      darkTheme: PraharTheme.of(Brightness.dark, material: prefs.materialChoice),
      home: const HomeScreen(),
    );
  }
}
