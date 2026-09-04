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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _index = 0;

  static const _titles = ['Today', 'Plan', 'Progress', 'Subjects', 'Settings'];

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
    // header that content stops at.
    //
    // Today only. Extending the body behind the bar means the screen must
    // inset its own scroll view by the bar's height, and Today is the screen
    // whose whole design is about content flowing beneath a fixed mark. The
    // other four stop at the bar, as they always have.
    final glassBar =
        _index == 0 && state.prefs.materialChoice == MaterialChoice.glass;

    return Scaffold(
      extendBodyBehindAppBar: glassBar,
      appBar: AppBar(
        // The wrapper paints the tint; the bar's own fill would sit on top of
        // the blur and defeat it.
        backgroundColor: glassBar ? Colors.transparent : null,
        flexibleSpace:
            glassBar ? const GlassSurface(child: SizedBox.expand()) : null,
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
        title: _index == 0 && state.subjects.isNotEmpty
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
          TodayEditorialScreen(),
          PlanTabs(),
          ProgressScreen(),
          SubjectsScreen(),
          SettingsScreen(),
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
