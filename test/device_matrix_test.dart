import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prahar/data/database.dart';
import 'package:prahar/domain/models.dart';
import 'package:prahar/domain/preferences.dart';
import 'package:prahar/domain/schedule.dart';
import 'package:prahar/notifications/notifier.dart';
import 'package:prahar/planner/planner.dart';
import 'package:prahar/state/app_state.dart';
import 'package:prahar/ui/home_screen.dart';
import 'package:prahar/ui/how_it_works.dart';
import 'package:prahar/ui/theme.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Does this app survive phones that are not the developer's phone?
///
/// Everything so far has been verified on one Xiaomi at one size with the
/// system font at its default. The two variables most likely to break a
/// layout are the two nobody tests: a **narrow screen** and a **large font
/// scale**. Both are ordinary — a 5-inch phone is 320dp wide, and Android's
/// accessibility font slider goes well past 1.5x on every device sold.
///
/// The test font here draws each glyph as a fixed-width box, so text is wider
/// than on a real device. That makes these conservative rather than wrong: a
/// row that overflows only here is a row that overflows on a real phone a
/// notch or two further up the font slider.
void main() {
  late Directory dir;
  late PraharDatabase db;
  late AppState state;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('prahar_matrix');
    db = PraharDatabase();
    await db.open(path: dir.path);

    // Long names on purpose: the one string the app does not control.
    state = AppState(db: db, notifier: Notifier())
      ..loading = false
      ..prefs = const Prefs()
      ..subjects = [
        Subject(
          id: 's1',
          name: 'Data Structures and Algorithms',
          examDate: DateTime.now().add(const Duration(days: 18)),
          colorValue: 0xFF4F46E5,
        ),
        Subject(
          id: 's2',
          name: 'Thermodynamics',
          examDate: DateTime.now().add(const Duration(days: 5)),
          colorValue: 0xFFD97706,
        ),
      ]
      ..topics = [
        const Topic(
          id: 't1',
          subjectId: 's1',
          title: 'Balanced binary search trees and rotations',
          estimatedMinutes: 300,
        ),
        const Topic(
          id: 't2',
          subjectId: 's2',
          title: 'Entropy',
          estimatedMinutes: 240,
        ),
      ];

    state.plan = const Planner().generate(
      subjects: state.subjects,
      topics: state.topics,
      availability: Availability(
        minutesByWeekday: {for (var d = 1; d <= 7; d++) d: 240},
      ),
      today: DateTime.now(),
    );
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget app(double textScale) => ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(
      theme: PraharTheme.of(
        Brightness.dark,
        material: state.prefs.materialChoice,
        cardStyle: state.prefs.cardStyle,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: HomeScreen(key: UniqueKey()),
    ),
  );

  /// Pumps at [size] and [textScale], walks to [tab], returns what threw.
  Future<Object?> visit(
    WidgetTester tester,
    Size size,
    double textScale,
    int tab,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(textScale));
    await tester.pump();

    if (tab != 0) {
      final label = const [
        'Today',
        'Plan',
        'Progress',
        'Subjects',
        'Settings',
        'Look',
      ][tab];
      final target = find.text(label);
      if (target.evaluate().isEmpty) {
        return 'destination "$label" is not reachable at $size / ${textScale}x';
      }
      await tester.tap(target.last, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    final thrown = tester.takeException();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    return thrown;
  }

  // A small modern phone, and the developer's phone. 320dp wide is the floor
  // Android has always guaranteed and is still what a compact device reports.
  const small = Size(320, 640);
  const normal = Size(411, 914);

  const tabs = ['Today', 'Plan', 'Progress', 'Subjects', 'Settings', 'Look'];

  group('a small phone', () {
    for (var i = 0; i < tabs.length; i++) {
      testWidgets('${tabs[i]} lays out at 320dp', (tester) async {
        expect(await visit(tester, small, 1.0, i), isNull);
      });
    }
  });

  group('a large system font', () {
    for (var i = 0; i < tabs.length; i++) {
      testWidgets('${tabs[i]} lays out at 1.5x', (tester) async {
        expect(await visit(tester, normal, 1.5, i), isNull);
      });
    }
  });

  // The guide is a pushed page, so the tab walk above never reaches it — and
  // its journey steps carry fixed-width columns, which is the shape that
  // fails first on a narrow screen.
  group('the guide', () {
    Future<Object?> pumpGuide(
      WidgetTester tester,
      Size size,
      double scale,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: PraharTheme.of(Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const HowItWorks(showAppBar: true),
          ),
        ),
      );
      await tester.pump();
      return tester.takeException();
    }

    testWidgets('lays out at 320dp', (tester) async {
      expect(await pumpGuide(tester, small, 1.0), isNull);
    });

    testWidgets('lays out at 1.5x', (tester) async {
      expect(await pumpGuide(tester, normal, 1.5), isNull);
    });

    testWidgets('reads as four steps', (tester) async {
      await pumpGuide(tester, normal, 1.0);
      for (final n in ['1', '2', '3', '4']) {
        expect(find.text(n), findsOneWidget);
      }
    });
  });
}
