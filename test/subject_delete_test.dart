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
import 'package:prahar/ui/subject_detail_screen.dart';
import 'package:prahar/ui/theme.dart';
import 'package:prahar/ui/widgets.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Deleting a subject.
///
/// Seen on the phone on 12 Sep: deleting from the edit sheet closed the sheet
/// and left the subject's page open on a subject that no longer existed, which
/// drew a blank grey screen with no way back. Delete is now a bin beside the
/// pencil, it asks first, and the page leaves once its subject is gone.
void main() {
  late Directory dir;
  late PraharDatabase db;
  late AppState state;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  final exam = DateTime.now().add(const Duration(days: 30));
  final alpha = Subject(id: 'a', name: 'Alpha', examDate: exam);
  final beta = Subject(id: 'b', name: 'Beta', examDate: exam);

  /// The subjects go into the database as well, since deleting one writes
  /// there. In real time: a database write on a widget test's fake clock never
  /// completes, and that hung this file for ten minutes.
  Future<void> withSubjects(WidgetTester tester, List<Subject> subjects) async {
    await tester.runAsync(() async {
      for (final s in subjects) {
        await db.upsertSubject(s);
      }
    });
    final availability = Availability.standard();
    state
      ..subjects = subjects
      ..availability = availability
      ..plan = const Planner().generate(
        subjects: subjects,
        topics: const [],
        availability: availability,
        today: DateTime.now(),
      );
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('prahar_delete');
    db = PraharDatabase();
    await db.open(path: dir.path);
    state = AppState(db: db, notifier: Notifier())
      ..loading = false
      ..prefs = const Prefs();
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  // Today runs a periodic timer, so pumpAndSettle would never return.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          theme: PraharTheme.of(Brightness.dark),
          home: HomeScreen(key: UniqueKey()),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(Icons.menu_book_outlined),
      ),
    );
    await settle(tester);
  }

  final bin = find.byTooltip('Delete subject');

  /// Confirms, then lets the delete's database work finish.
  ///
  /// The dialog was opened on the test's fake clock, so the delete resumes
  /// there too, and a database write on that clock needs both fake time, to
  /// fire its timers, and real time, for the database's replies to arrive.
  /// Either alone leaves it half done, and it then finishes after the test has
  /// closed the database.
  ///
  /// It waits for the state to tell its listeners, not for the subject to
  /// leave the list. The list changes part way through the delete, before the
  /// rest of its database work, and stopping there made this test flaky.
  Future<void> confirmDelete(WidgetTester tester) async {
    var told = false;
    void listener() => told = true;
    state.addListener(listener);

    await tester.tap(find.byKey(const ValueKey('confirm-delete-subject')));
    for (var i = 0; i < 300 && !told; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }

    state.removeListener(listener);
    await settle(tester);
  }

  testWidgets(
    'deleting from its page goes back to the list, not a blank page',
    (tester) async {
      await withSubjects(tester, [alpha]);
      await pumpAt(tester, const Size(411, 914));

      await tester.tap(find.text('Alpha'));
      await settle(tester);
      expect(find.byType(SubjectDetailScreen), findsOneWidget);

      await tester.tap(bin);
      await settle(tester);
      expect(find.byType(AlertDialog), findsOneWidget, reason: 'it asks first');

      await confirmDelete(tester);

      expect(state.subjects, isEmpty);
      expect(
        find.byType(SubjectDetailScreen),
        findsNothing,
        reason: 'a page for a deleted subject is a dead end',
      );
      expect(find.byType(EmptyState), findsOneWidget);
    },
  );

  testWidgets('cancelling keeps the subject and the page', (tester) async {
    await withSubjects(tester, [alpha]);
    await pumpAt(tester, const Size(411, 914));
    await tester.tap(find.text('Alpha'));
    await settle(tester);

    await tester.tap(bin);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('cancel-delete-subject')));
    // Time for a delete to land, had Cancel started one. Without this a
    // wrongly started delete would still be half done at the check below.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    await settle(tester);

    expect(state.subjects, hasLength(1));
    expect(find.byType(SubjectDetailScreen), findsOneWidget);
  });

  testWidgets('the edit sheet no longer has a Delete button', (tester) async {
    await withSubjects(tester, [alpha]);
    await pumpAt(tester, const Size(411, 914));
    await tester.tap(find.text('Alpha'));
    await settle(tester);

    await tester.tap(find.byTooltip('Edit subject'));
    await settle(tester);

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Delete'), findsNothing);
  });

  testWidgets(
    'a tablet shows another subject after a delete, not a blank pane',
    (tester) async {
      await withSubjects(tester, [alpha, beta]);
      await pumpAt(tester, const Size(1280, 800));

      await tester.tap(find.text('Beta'));
      await settle(tester);
      expect(
        find.text('Beta'),
        findsNWidgets(2),
        reason: 'row and pane header',
      );

      await tester.tap(bin);
      await settle(tester);
      await confirmDelete(tester);

      expect(state.subjects, hasLength(1));
      expect(
        find.text('Alpha'),
        findsNWidgets(2),
        reason: 'the pane moves to a subject that still exists',
      );
    },
  );
}
