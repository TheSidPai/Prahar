import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prahar/data/database.dart';
import 'package:prahar/domain/preferences.dart';
import 'package:prahar/notifications/notifier.dart';
import 'package:prahar/state/app_state.dart';
import 'package:prahar/ui/brand.dart';
import 'package:prahar/ui/home_screen.dart';
import 'package:prahar/ui/theme.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The screen every user sees first, and the only one that was never tested.
///
/// It shipped with `HowItWorks` — itself a ListView — nested inside another
/// ListView, which is an unbounded-height viewport error. A debug build shows
/// that as a red banner; a **release** build draws a plain black rectangle and
/// says nothing, so the bottom two thirds of the first screen was a rendering
/// failure that looked like an empty screen, taking the only call to action
/// off screen with it. It was found by looking at a phone, months late.
///
/// Pumping it once would have caught it, which is the entire reason this file
/// exists.
void main() {
  late Directory dir;
  late PraharDatabase db;
  late AppState state;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('prahar_firstrun');
    db = PraharDatabase();
    await db.open(path: dir.path);

    // Exactly a fresh install: no subjects, no topics, no plan.
    state = AppState(db: db, notifier: Notifier())
      ..loading = false
      ..prefs = const Prefs();
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget app() => ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(
      theme: PraharTheme.of(Brightness.dark),
      home: HomeScreen(key: UniqueKey()),
    ),
  );

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pump();
  }

  const portrait = Size(411, 914);
  const landscape = Size(891, 411);

  for (final (name, size) in [('upright', portrait), ('sideways', landscape)]) {
    testWidgets('$name: lays out without throwing', (tester) async {
      await pumpAt(tester, size);
      expect(
        tester.takeException(),
        isNull,
        reason: 'a release build would draw this failure as a black rectangle',
      );
    });

    testWidgets('$name: offers the one action there is', (tester) async {
      await pumpAt(tester, size);

      // With nothing in the database, adding a subject is the only thing that
      // can be done, so it must be on screen — not below a fold, and not
      // behind a rendering error.
      final cta = find.text('Add your first subject');
      expect(cta, findsOneWidget);

      final box = tester.getRect(cta);
      final screen = tester.getRect(find.byType(MaterialApp));
      expect(
        box.bottom,
        lessThanOrEqualTo(screen.bottom),
        reason: 'the call to action is off the bottom of the screen',
      );
    });
  }

  testWidgets('the brand is the drawn mark, not the launcher tile', (
    tester,
  ) async {
    await pumpAt(tester, portrait);

    // PraharMarkFilled is the icon on the home screen; showing it inside the
    // app shows the user the thing they just tapped, and it sits on the page
    // like a sticker rather than belonging to it.
    expect(find.byType(PraharMark), findsWidgets);
    expect(find.byType(PraharMarkFilled), findsNothing);
  });

  testWidgets('the app bar does not title a screen that titles itself', (
    tester,
  ) async {
    await pumpAt(tester, portrait);

    // "Today" over a large centred wordmark is two titles. The nav bar still
    // labels the tab, so nothing is lost.
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Today')),
      findsNothing,
    );
  });
}
