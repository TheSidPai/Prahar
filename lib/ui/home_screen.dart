import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/preferences.dart';
import '../state/app_state.dart';
import 'brand.dart';
import 'glass.dart';
import 'layout.dart';
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

  /// Which of Plan's two views is showing. It lives here rather than inside
  /// PlanTabs because the control that changes it is drawn in the app bar,
  /// and state belongs with the widget that owns the thing you touch.
  int _planView = 0;

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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final size = MediaQuery.sizeOf(context);
    final rail = Layout.usesRail(size);
    final glass = state.prefs.materialChoice == MaterialChoice.glass;

    // IndexedStack rather than a switch: it keeps every tab's scroll position
    // and state alive, which is why moving between them feels instant.
    final pages = IndexedStack(
      index: _index,
      children: [
        const TodayEditorialScreen(),
        PlanTabs(view: _planView),
        const ProgressScreen(),
        const SubjectsScreen(),
        const SettingsScreen(),
      ],
    );

    // Plan's Days/Month toggle rides in the app bar rather than under it.
    //
    // It is the header of that screen — the thing that says which of two
    // views you are looking at — and leaving it in the body put an opaque
    // strip immediately below the glass, cutting the header into two
    // materials with a seam between them. In the bar it sits inside the same
    // single pane of glass as the title, and the plan scrolls under both.
    //
    // Wide layouts show Days and Month side by side and have no toggle at
    // all, so there is nothing to carry there.
    final showPlanToggle = _index == 1 && !Layout.isWide(size);

    // A glass app bar that content passes *under*, rather than an opaque
    // header that content stops at.
    //
    // Every screen, not just Today. It began on Today alone because that is
    // the screen designed around content flowing beneath a fixed mark, but one
    // glass header among four matte ones does not read as restraint — it reads
    // as the other four being unfinished, which is exactly how it looked on
    // the device. The header is one element in one place; it should be one
    // material.
    //
    // The cost is that extending the body behind the bar makes every screen
    // responsible for starting its content below it. `glassTopInset` is that
    // rule, in one place.
    final glassBar = glass;

    return Scaffold(
      extendBodyBehindAppBar: glassBar,
      appBar: AppBar(
        // The wrapper paints the tint; the bar's own fill would sit on top of
        // the blur and defeat it.
        backgroundColor: glassBar ? Colors.transparent : null,
        flexibleSpace: glassBar
            ? const GlassSurface(child: SizedBox.expand())
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
        // On first run the screen below is the brand — a large centred mark
        // and wordmark — so a title here would be the second one on screen.
        // The tab is labelled in the nav bar either way.
        title: _index == 0
            ? (state.subjects.isEmpty
                  ? null
                  : PraharLogo(
                      markSize: 24,
                      filled: false,
                      wordmarkStyle: Theme.of(
                        context,
                      ).appBarTheme.titleTextStyle,
                    ))
            : Text(_titles[_index]),
        // Sized rather than left to its intrinsic height so the glass pane
        // above it is a predictable shape, and so the body's inset — which
        // Scaffold derives from the bar's total preferred size — is stable
        // whichever view is selected.
        bottom: showPlanToggle
            ? PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Days')),
                      ButtonSegment(value: 1, label: Text('Week')),
                      ButtonSegment(value: 2, label: Text('Month')),
                    ],
                    selected: {_planView},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) =>
                        setState(() => _planView = s.first),
                  ),
                ),
              )
            : null,
      ),
      // When glass is on we want content to slide under the nav rather than
      // stopping short of it. `extendBody` does that; each screen already
      // reserves 90px of bottom padding for the nav's height.
      extendBody: !rail && glass,
      body: rail
          ? Row(
              children: [
                _NavRail(
                  glass: glass,
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                ),
                Expanded(child: pages),
              ],
            )
          : pages,
      floatingActionButton: _index == 3
          ? FloatingActionButton.extended(
              onPressed: () => showSubjectSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('Subject'),
            )
          : null,
      bottomNavigationBar: rail
          ? null
          : _NavBar(
              glass: glass,
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: _destinations,
            ),
    );
  }
}

const _destinations = [
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
  // Drawn, not borrowed — see PraharProgressGlyph. The stock ring was the
  // right idea at the wrong weight: `donut_large` is a solid wedge cut out of
  // a disc, which is heavier than anything else in this row and heavier than
  // the app's own mark. A hairline track with an arc on it says the same
  // thing at the weight the rest of the brand is drawn at.
  NavigationDestination(
    icon: PraharProgressGlyph(),
    selectedIcon: PraharProgressGlyph(selected: true),
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
];

/// Navigation down the side instead of across the bottom.
///
/// Landscape on a phone is about 410dp tall. A 60dp app bar and a 68dp bottom
/// bar take a third of that before a single block is drawn, and the thing that
/// is scarce sideways is height — so navigation moves to the edge that has
/// room. It is the same five destinations in the same order; only the axis
/// changes, so nothing has to be relearned.
class _NavRail extends StatelessWidget {
  const _NavRail({
    required this.glass,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final bool glass;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Five labelled destinations want roughly 360dp. A phone in landscape
    // gives the body about 350 once the app bar has taken its share, so the
    // rail must be allowed to scroll or it overflows on the exact device this
    // layout exists for. LayoutBuilder + IntrinsicHeight is the documented
    // shape for this: the rail still fills the column when there is room, and
    // scrolls when there is not.
    // The width has to be pinned here: a Row hands its non-flex children an
    // unbounded width, and a scroll view cannot lay out against infinity.
    // The body runs behind the app bar when it is glass, and the rail is part
    // of the body. The glass panel itself is left running full height, so it
    // meets the bar without a seam — it is the destinations that move down,
    // because content may flow under glass but a control the user has to hit
    // may not hide behind it.
    final topInset = glassTopInset(context);

    final rail = SizedBox(
      width: 88,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: EdgeInsets.only(top: topInset),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - topInset).clamp(
                0.0,
                double.infinity,
              ),
            ),
            child: IntrinsicHeight(
              child: NavigationRail(
                selectedIndex: selectedIndex,
                onDestinationSelected: onDestinationSelected,
                backgroundColor: glass ? Colors.transparent : null,
                indicatorColor: theme.colorScheme.primary.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.20 : 0.12,
                ),
                // Labels always, as in the bottom bar. An icon-only rail asks
                // the user to learn five glyphs for no gain — the width is
                // there, and the two layouts should not disagree about what the
                // destinations are called.
                labelType: NavigationRailLabelType.all,
                groupAlignment: -0.9,
                destinations: [
                  for (final d in _destinations)
                    NavigationRailDestination(
                      icon: d.icon,
                      selectedIcon: d.selectedIcon,
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      label: Text(
                        d.label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 0.2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (!glass) return rail;
    return GlassSurface(
      borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
      child: rail,
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
