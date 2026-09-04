import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/preferences.dart';
import '../state/app_state.dart';
import 'brand.dart';
import 'glass.dart';
import 'plan_screen.dart';
import 'settings_screen.dart';
import 'subjects_screen.dart';
import 'today_editorial_screen.dart';
import 'today_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _index = 0;

  /// The editorial Today is appended rather than inserted next to the original
  /// so every existing index — and the FAB's `_index == 3` — keeps its
  /// meaning. It is a trial tab: one of the two Todays is meant to be deleted
  /// once they have been compared on a real day, and this is the cheaper one
  /// to remove.
  static const _titles = [
    'Today',
    'Plan',
    'Progress',
    'Subjects',
    'Settings',
    'Today',
  ];

  /// Indices whose screen is a Today, and so carries the mark in the app bar.
  static const _todayTabs = {0, 5};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The alarm window is only two weeks deep, and the OS can drop pending
  /// alarms after a reboot or a force-stop. Topping up whenever the app comes
  /// to the foreground is the cheapest way to keep it honest.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      final app = context.read<AppState>();
      // Left open overnight, `today` moves on but the loaded log does not, so
      // yesterday's blocks would show as today's and misstate the day's
      // remaining capacity.
      app.refreshIfDayChanged();
      app.refreshAlarms();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (state.loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // A glass app bar that content passes *under*, rather than an opaque
    // header that content stops at. Scoped to the editorial tab while the two
    // Todays are being compared: extending the body behind the bar means every
    // screen must inset its own scroll view by the bar's height, and doing
    // that to five screens for a trial that may be reverted is not a trade
    // worth making. If the editorial Today wins, this moves with it.
    final glassBar = _todayTabs.contains(_index) &&
        _index != 0 &&
        state.prefs.materialChoice == MaterialChoice.glass;

    return Scaffold(
      extendBodyBehindAppBar: glassBar,
      appBar: AppBar(
        // The wrapper paints the tint; the bar's own fill would sit on top of
        // the blur and defeat it.
        backgroundColor: glassBar ? Colors.transparent : null,
        flexibleSpace: glassBar
            ? const GlassSurface(
                // Thinner than the app's other glass. This pane is always on
                // screen with text moving beneath it, so it has to read as a
                // sheet of glass rather than as a panel — at the standard
                // 0.42/0.45 it looked like an opaque header that happened to
                // blur.
                tintAlpha: 0.28,
                child: SizedBox.expand(),
              )
            : null,
        // Today carries the mark instead of the word "Today". The tab is
        // already labelled in the nav bar and the full date sits in the
        // header just below, so that title line was spending itself on a
        // word nobody needed — and the brand was visible only on the
        // first-run screen, disappearing for good once a subject existed.
        //
        // The wordmark borrows the app bar's own title style so "Prahar"
        // sits at exactly the weight and size "Plan" and "Progress" do.
        // On first run the empty state already shows the large filled logo,
        // so the bar stands down rather than stack two marks.
        title: _todayTabs.contains(_index) && state.subjects.isNotEmpty
            ? PraharLogo(
                markSize: 24,
                filled: false,
                wordmarkStyle: Theme.of(context).appBarTheme.titleTextStyle,
              )
            : Text(_titles[_index]),
      ),
      // When glass is on we want content to slide under the nav rather than
      // stopping short of it. `extendBody` does that; each screen already
      // reserves 90px of bottom padding for the nav's height.
      extendBody: state.prefs.materialChoice == MaterialChoice.glass,
      body: IndexedStack(
        index: _index,
        children: const [
          TodayScreen(),
          PlanTabs(),
          ProgressScreen(),
          SubjectsScreen(),
          SettingsScreen(),
          TodayEditorialScreen(),
        ],
      ),
      floatingActionButton: _index == 3
          ? FloatingActionButton.extended(
              onPressed: () => showSubjectSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('Subject'),
            )
          : null,
      bottomNavigationBar: _NavBar(
        glass: state.prefs.materialChoice == MaterialChoice.glass,
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Plan',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Progress',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: 'Subjects',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'TestEd',
          ),
        ],
      ),
    );
  }
}

/// Wraps the OS NavigationBar in a GlassSurface when the material is Glass.
///
/// Handles both variants in one place so the two implementations do not
/// drift out of sync visually.
class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.glass,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final bool glass;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<Widget> destinations;

  @override
  Widget build(BuildContext context) {
    final bar = NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: destinations,
      // The wrapper draws the tint, so make the bar itself transparent when
      // glass; otherwise its own fill would obscure the blur.
      backgroundColor: glass ? Colors.transparent : null,
    );
    if (!glass) return bar;

    return GlassSurface(
      // Top-only rounded corners so the bar tucks into the bottom of the
      // screen while still reading as a distinct surface.
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: bar,
    );
  }
}
