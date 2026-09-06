# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## For a fresh session

If you are just picking this up, read in this order: **Current state** →
**Open feedback** → **Recent decisions worth carrying forward** →
whatever section your task touches. The whole file is here because every
paragraph was learned the hard way, but the state + feedback + decisions
are what let a new session act, not just understand.

### Where things stand, as of 6 Sep

**13 commits are unpushed.** The user pushes, never Claude. Everything below
is committed, built and installed on the phone; `.claude/settings.json` is
dirty and should be reverted, not committed — see the note at the end of this
section.

**One decision is open, and it is the only thing blocking anything.** The user
asked whether the launcher icon can animate on the home screen when the app is
minimised, as a goodbye. **It cannot** — the icon is drawn by the launcher,
adaptive icons are two static layers, and no Android API lets an app animate
its own icon. What is real is the *opposite* moment: Android 12+ plays an
`AnimatedVectorDrawable` as the splash when the app is opened
(`windowSplashScreenAnimatedIcon`), which is what people usually remember as
happening on exit. Three options were put to the user and none chosen yet:

1. Do nothing; the tap easter egg and the return greeting already give the
   mark two reliable moments.
2. Build the splash AVD, accepting that the mark's six tuned numbers would
   exist a **third** time in vector XML — generate it from a tool script so a
   retune regenerates rather than requiring hand-editing.
3. Free middle path: play Unfurl on Today's app bar on every cold start rather
   than only after 30s away. Costs nothing, lands ~300ms after the launcher
   icon disappears, close enough to read as continuous. **This was the
   recommendation.**

**Distribution is decided in principle: free, not Play.** Signed APKs on
GitHub Releases, with Obtainium mentioned for auto-updates. The full process
was written out and the user has not started it. `tools\dev.ps1 apk` then
`signer`, rename to `prahar-<version>.apk`, tag, `gh release create`. Do not
put the keystore in CI. The $25 Play fee buys discovery and nothing this app
needs yet.

**The keystore now exists.** `dev.ps1 signer` prints `CN=Siddhant, …, C=IN`.
The debug-to-release switch is done and cost one uninstall; every future build
installs over the top normally.

### Also settled on 5 Sep: landscape, and the formatting style

**Landscape has been seen on the device and it looks right.** The user turned
the phone sideways on 5 Sep and confirmed it. It was written and tested blind
— MIUI refuses adb input injection, so nothing here could rotate the phone —
and `test/landscape_test.dart` was the only evidence until then. That test
earned its keep: it found three real overflows before any of this reached a
screen. The verification gap it covers is still real for the *next* visual
change, so keep writing layout tests, but landscape itself is no longer an
open question.

**The tree is now in the new tall `dart format` style**, adopted in one
commit on 5 Sep. `tools\dev.ps1 format` is safe to run again — see below.

### Settled on 5 Sep: the permission question is closed

`bypassPermissions` in `.claude/settings.local.json` **does not work on this
machine.** A fresh session ran one novel command (`tools\dev.ps1 devices`)
and the user confirmed they were prompted. That was the last untested
hypothesis, and it now joins the falsified list below.

Do not re-run this test and do not open the question again. The only thing
that works is launching from a terminal in this directory with
`claude --dangerously-skip-permissions`; the conditions attached to that are
below and are binding.

Files you will touch most:

- `lib/planner/planner.dart` — the greedy scheduler
- `lib/planner/calibration.dart` — the per-subject rate learning
- `lib/state/app_state.dart` — the single `ChangeNotifier`
- `lib/data/database.dart` — SQLite DAO + migrations (bump the version!)
- `lib/ui/today_editorial_screen.dart` — Today: hero, rail, done-strip
- `lib/ui/layout.dart` — breakpoints; width sets columns, height sets nav
- `lib/ui/brand.dart` — `PraharMark`, `PraharLogo` CustomPainters
- `lib/ui/glass.dart` — `GlassSurface`, `SheetBackground`
- `lib/ui/theme.dart` — one place for every visual token
- `tools/dev.ps1` — every build action; noisy tasks log to `build\dev.log`
- `tools/make_icon.ps1` — the launcher-icon generator (T3+K4 numbers live here)

## Run Claude from this directory

`cd` into the project root before starting Claude. This file and
`.claude/settings.json` are only loaded when the working directory is the
project. Starting from a parent directory (a home folder, say) silently skips
both, and any permission granted lands in *global* settings instead of the
project's, where it follows you into every unrelated repo.

Which settings file holds what: `.claude/settings.json` is **tracked in git**
and so holds nothing machine-specific and no standing permission grants;
`.claude/settings.local.json` is **gitignored** and holds both, including the
`bypassPermissions` mode, so that a "never ask" grant cannot travel to a clone.

**Claude Code writes new grants into the tracked file by itself** whenever the
user picks "always allow", and it did so four times on 5–6 Sep. Move them to
`settings.local.json` (and the global `~/.claude/settings.json`, which the
user asked to keep in step) and `git checkout -- .claude/settings.json`.
**Check `git status` before any push**; that file is the one that travels to a
clone. It is dirty right now for exactly this reason.

## What this is

Prahar is a local-first study planner for Android: the student enters subjects,
topics and how much time they have per day; the app generates a day-by-day
schedule and fires on-device reminders for each block.

There is **no backend, no account and no network client**. Everything lives in a
local SQLite file and OS-scheduled alarms. Keep it that way unless explicitly
asked — "add sync" is a real architectural change, not a small feature.

## Commands

Everything goes through `tools\dev.ps1`. Do not invoke `flutter` directly: the
script sets `JAVA_HOME` to JDK 17 (the system default is JDK 25, which the
Android Gradle plugin rejects) and puts Flutter on PATH. It is also the only
command shape that is permission-allow-listed, so ad-hoc `flutter` calls will
prompt on every run.

```powershell
tools\dev.ps1 setup        # scaffold android/ from a throwaway flutter create, then pub get
tools\dev.ps1 androidsdk   # install the Android SDK headlessly via sdkmanager
tools\dev.ps1 gradledist   # pre-fetch the Gradle distribution with curl
tools\dev.ps1 fonts        # download bundled variable fonts to assets/fonts
tools\dev.ps1 pubget
tools\dev.ps1 test         # full suite, output also copied to build\dev.log
tools\dev.ps1 testq        # same, but prints only the last 12 lines
tools\dev.ps1 test <name>  # one test by name substring
tools\dev.ps1 analyze      # prints the last 8 lines; full run in build\dev.log
tools\dev.ps1 format
tools\dev.ps1 doctor
tools\dev.ps1 devices      # also diagnoses "no device" causes on MIUI
tools\dev.ps1 run          # onto the connected phone
tools\dev.ps1 apk          # release APK — what goes on the phone
tools\dev.ps1 bundle       # release App Bundle — what Play takes
tools\dev.ps1 keystore     # create the upload key (run it yourself; it prompts)
tools\dev.ps1 signer       # print who signed the last build
tools\dev.ps1 install      # build + adb install + launch, one shot
tools\dev.ps1 licenses     # accept Android SDK licences (cosmetic; see below)
tools\dev.ps1 sdkpkg "<pkg;id>"   # install any sdkmanager package, quoting handled
tools\dev.ps1 exempt [off] # toggle battery-optimisation exemption over adb
tools\dev.ps1 notif        # diagnose notification channel + delivery state
tools\dev.ps1 alarms       # list pending alarms with exact/inexact status
tools\dev.ps1 check        # app process alive + last log lines
tools\dev.ps1 screenshot   # pull the phone screen to build/screen.png
tools\dev.ps1 launch       # bring the app to the foreground
tools\dev.ps1 adb <args>   # passthrough for ad-hoc adb (one allow rule for all)
tools\status.ps1           # read-only: toolchain, SDK components, project sanity, devices
tools\make_icon.ps1        # regenerate every launcher icon density
tools\make_logos.ps1       # render alternative logo concepts side by side
tools\make_v2_thickness.ps1     # T2/T3 hand-thickness ladder
tools\make_t3_tick_variants.ps1 # K1..K5 tick-thickness ladder
tools\make_v2_launcher.ps1      # any icon variant at every launcher density
tools\make_nav_options.ps1      # nav icon candidates, 7 per tab, at 96 and 24px
tools\make_mark_anim.ps1        # the mark's animation as 10-frame filmstrips
```

**`dev.ps1 adb` must never be passed `-t`.** PowerShell binds parameters by
unambiguous prefix and `-t` is a prefix of this script's own `-Task`, so
`dev.ps1 adb logcat -d -t 200` sets `Task='200'` and prints the help. It fails
silently and looks exactly like adb returning nothing — an hour went into
"the log buffer is empty" before that was spotted. Use `-v brief -s <tag>`.

### Use these exact command shapes, or the permission prompts come back

This cost the user a night of interruptions and three wrong theories, so the
conclusion is written down plainly.

**Do not try to fix this with permission patterns. It does not work here.**

The decisive test: `dev.ps1 testq` prompted, the user chose *always allow*,
and Claude Code wrote the rule itself, in its own format —

```
"PowerShell(& 'c:\\Users\\TheSidPai\\Prahar\\tools\\dev.ps1' testq)"
```

— and the very next **byte-identical** run prompted again. A plain command,
no pipe, no redirect, no chaining, a rule the tool authored for itself: still
prompted. PowerShell command rules do not stick on this setup.

Three theories were tried and falsified before that, each costing the user a
round of interruptions, so they are recorded here to save the next session
repeating them: it is *not* the escaping (doubled vs single backslashes), not
a missing trailing wildcard, and not prefix-versus-exact matching. Do not
re-derive any of it. Two further traps are real but were not the cause:

- **A piped command can never be permanently allowed.** Choosing *always
  allow* on `A | B` saves the rule as `A`, so it never matches `A | B` again.
- **Redirects are not offered an "always allow" at all** — the prompt is a
  bare yes/no, so nothing can be saved.

The one rule that demonstrably works is `dev.ps1 analyze` in
`settings.local.json`, which never prompted all session. Why that one holds
and an identically-shaped new one does not is unexplained. Leave it alone.

**A fourth theory died on 5 Sep: `"defaultMode": "bypassPermissions"` in
`settings.local.json` does not work either.** It was suspected that the
earlier failure was only because the file had been edited mid-session, so a
fresh session was the clean test — one novel command, and the user confirmed
a prompt appeared. The line is still in the file because it costs nothing,
but it is inert here and is not evidence of anything. Note the user drives
Claude through the VS Code extension by default, which may or may not be the
reason; that is not worth another session to find out.

**So: for long or unattended runs the user launches
`claude --dangerously-skip-permissions`** from a terminal opened in this
directory — the flag cannot be passed from the VS Code sidebar button, which
is why this keeps coming up. That is a deliberate, informed
choice for this repo — local, single-developer, fully version-controlled,
nothing secret in the tree — and it comes with standing conditions, which
are binding:

- **No WebFetch, no WebSearch in such a session.** They are the only route by
  which untrusted text could reach the context, and with no prompts there is
  no checkpoint behind them. If something genuinely needs looking up, stop
  and say so.
- **Stay inside `c:\Users\TheSidPai\Prahar`.** The flag is session-wide, not
  repo-scoped: a shell command can reach any path on the machine. Only
  behaviour keeps it confined.
- **Still never push**, and commit after each verified step so the distance
  back to a good state stays short.

None of that makes the command hygiene below pointless — it is simply good
practice now rather than a workaround:

- **No pipes, no `;` chains, one command per call.** `dev.ps1` does its own
  output trimming (below), so there is nothing left to pipe.
- **Never compound a command with `&&` or `;`.** This is the same trap as the
  pipe one above and it was walked into again on 5 Sep: every git call was
  being issued as `cd <dir> && git ...`, so "always allow" saved the rule as
  `cd <dir>`, which never matched the next one. Use `git -C
  c:\Users\TheSidPai\Prahar <subcommand>` — one command, stable prefix,
  matchable. The allow lists in both settings files are written against that
  shape.
- **Commit messages:** write the message to `build\commit-msg.txt` with the
  file tools and then run `git commit -F build/commit-msg.txt`, which is a
  fixed command shape. Never pass the message inline in a heredoc: that makes
  every commit a novel command that has to be approved afresh. The path is
  fixed and under gitignored `/build/`; never the scratchpad, whose path
  carries the session id and dies with the session.
- **Keep them short: a subject line and three or four lines of body.** Say
  what changed and the one thing a reader could not infer from the diff. This
  file is where reasoning belongs — it is read at the start of every session,
  whereas a commit body is read approximately never. Essay-length messages
  were written all through 5 Sep and the user asked twice for them to stop.
- **Group commits by the piece of work, not by the file.** One commit per
  round of a feature, not one per edit; and when a feature had a false start,
  squash it away rather than shipping "add it, then fix it" as two commits —
  that documents the mistake rather than the change.
- **Staging:** always
  `git add -A -- lib test tools CLAUDE.md pubspec.yaml assets android .claude`.
- **Tools scripts:** single quotes, lowercase drive letter, exactly
  `& 'c:\Users\TheSidPai\Prahar\tools\dev.ps1' <task>`.

### Noisy tasks log themselves

`analyze` prints its last 8 lines, `testq` its last 12, and both leave the
whole run in `build\dev.log` to read with an offset. `test` tees: full output
on screen and a copy in the log. This replaced trimming with
`| Select-Object -Last N` at the call site.

Use `>` inside the script, never `*>&1`: merging a native command's stderr
wraps every line in an ErrorRecord in PowerShell 5.1 and buries the very
output the task exists to show. That mistake was made and caught here — the
warning further down this file about `2>&1` is the same trap.

### Working unattended

The user sleeps; the machine does not have to. What makes overnight work
possible is the above plus a few standing decisions:

- **Decide and record, don't ask.** Make the reasonable call, state the
  assumption in the commit message, and leave anything genuinely ambiguous
  for the morning report rather than blocking on it overnight.
- **Never push.** The user pushes. Commits accumulate locally.
- **Device work is optional at night.** `install` is fine, but a screenshot
  at 3am captures a locked black screen, and `dev.ps1 exempt` does not
  survive a reboot. Anything needing eyes on the phone waits.
- **Leave a morning report**: what landed, what was decided and why, what is
  waiting on a human. The commit log is that report if the messages are good.

**Screenshots capture whatever is on the phone**, not just the Prahar app.
Ask before taking one if the user might have other content open, and delete
the file from `build/` afterwards if you did. `build/screen.png` is
gitignored.

**You cannot drive the UI from adb on this device.** `input tap` fails with
`SecurityException: Injecting input events requires ... INJECT_EVENTS` —
MIUI gates it behind a developer-option the phone does not have on. So a
screenshot shows whichever screen the user left open; to see a particular
screen, ask them to open it. Do not build a tap-based verification flow.

**Two install failures worth recognising on sight.**

`INSTALL_FAILED_UPDATE_INCOMPATIBLE ... signatures do not match` means the
build is signed with a different key than the app on the phone. Expected once,
on the switch from the debug key to the release one, and the only way through
is an uninstall — which destroys the local database, so export first.

`INSTALL_FAILED_USER_RESTRICTED: Install canceled by user` is MIUI, not
signing. It appeared on 5 Sep on the first *fresh package* install after that
uninstall, with "Install via USB" already enabled, and then succeeded on an
immediate retry with nothing changed. So the cause is almost certainly the
on-screen confirmation MIUI throws up for a new package, which cancels itself
if it is not tapped in time. Updates to an already-installed package never
show it, which is why hundreds of installs had never hit this. Retry once, and
look at the phone.

**`install` builds first — it did not always.** Until 4 Sep it installed
whatever APK was already sitting in `build/`, so after a code change it
silently reinstalled the *previous* build. Everything looks correct, the
change appears not to work, and the next hour goes into debugging code that
was never on the phone. This happened. If a change seems absent from the
running app, check `build\app\outputs\flutter-apk\app-release.apk`'s
timestamp before suspecting the code.

**`tools\dev.ps1 test` is not sufficient on its own.** Dart only compiles what
the tests import, so a passing suite leaves the entire `lib/ui` tree unchecked.
Always run `analyze` as well — that is what actually type-checks the app.

**`tools\dev.ps1 format` is safe to run — that changed on 5 Sep.** The tree
used to be committed in the old `dart format` style while the bundled Dart
3.13 formatter produced the new "tall style", so a single run rewrote every
file and buried whatever the commit was actually about. It went off by
accident on 4 Sep and had to be reverted with `git checkout -- lib test`.

The style was adopted deliberately on 5 Sep in `653b0bb`, a 39-file commit
that changed nothing else, with the suite green and the analyzer clean on
both sides of it. So formatting is now a no-op on a formatted tree, and the
old hand-matching rule is gone: run `format` freely and let it settle
whitespace instead of matching the surrounding style by eye.

**Always run `analyze` after `format`.** The tall style can split a line that
used to fit, and `curly_braces_in_flow_control_structures` only tolerates a
braceless `if` while it fits on one line. That fired exactly once during the
adoption, in `timer_screen.dart`; the fix is braces, and the analyzer is what
finds it. A reformat is not verified until `analyze` and `test` have both run.

`.git-blame-ignore-revs` names the reformat commit so `git blame` walks past
it. GitHub honours the file by name; locally it needs
`git config blame.ignoreRevsFile .git-blame-ignore-revs`, which is repo-local
and so must be re-run after a fresh clone. Only ever add formatter output to
that file — a commit that changed behaviour has to stay visible in blame.

## Current state (verified, 6 Sep 2026)

- **203/203 tests pass; `analyze` reports no issues.** Both re-run after every
  change on 6 Sep, and the build on the phone matches the tree.
- Release APK is **53.1 MB**, ~90–130 s warm. (An older line here said 52.3;
  it was wrong, and 52.9–53.1 is what this project has actually built all
  along.)
- **Signed with the user's own key** since 6 Sep — `dev.ps1 signer` prints
  `CN=Siddhant`. Not `CN=Android Debug`.
- **Landscape and tablet**: a navigation rail sideways, two panes on Today,
  Plan and Subjects, capped column widths on Progress and Settings. **Seen on
  the device and confirmed good on 5 Sep** — no longer written blind.
- Release APK builds and installs on device (52.3 MB, ~120 s warm; it was
  52.9 MB before the six unused fonts came out).
- Flutter 3.47.2 / Dart 3.13.2 at `C:\src\flutter`. JDK 17 (Temurin) and
  Android Studio installed. SDK at `%LOCALAPPDATA%\Android\Sdk`: platforms
  35+36, build-tools 36.0.0, platform-tools, cmdline-tools, NDK 28.2.13676358.
- **Runs on hardware**: Xiaomi 23127PN0CG, Android 16 / API 36. Reminders
  fire on time, use the alarm-stream sound, reach the lock screen — end to
  end verified. Battery exemption granted; `SCHEDULE_EXACT_ALARM` = allow.
- Two home-screen widgets: `NextBlockWidget` (compact 2x1) and `TodayWidget`
  (wider 4x2 with two blocks + a text-based progress bar).

### Shipped on 6 Sep, all on the device

- **A week view**, third segment under Plan. Seven days *from today*, not
  Monday to Sunday — a calendar week opened on a Saturday spends five columns
  on days that cannot be filled. Upright it is a row per day with time running
  across, because 52dp of column is a colour and not a word; tapping a day
  opens it and names its blocks. Sideways it is the seven-column grid with a
  clock down the side. Busy slots sit behind the blocks in both, and the
  legend names them, which is the one thing the drawing cannot say itself.
- **Settings, redesigned.** The screen is `SettingsScreen` in
  `lib/ui/look_screen.dart` — it ran for a day as a sixth "Look" tab beside
  the original, won, and the original was deleted. `settings_screen.dart` is
  now only the subpages, `ThemeToggle` and `savePrefs`. **The filename is a
  leftover; renaming it is a tidy-up for whenever something else touches it.**
  Schedule leads, Appearance is its own page (`AppearancePage`), and every
  group uses the one amber accent.
- **The mark animates.** `AnimatedPraharMark` in `brand.dart`, 1100ms,
  `MarkMotion.unfurl` chosen from three; `bloom` and `sweep` are **archived,
  not dead** — they answer questions not yet asked. It plays on the first-run
  screen, on a **tap anywhere the mark appears**, and when the app is resumed
  after 30s or more away. `MarkMotionScreen` is unreachable and kept whole.
- **Nav icons chosen from contact sheets** at the 24dp they are actually seen
  at: Progress is `track_changes`, Subjects is `menu_book`. `tools\
  make_nav_options.ps1` renders the candidates; `make_mark_anim.ps1` renders
  animation filmstrips. Both exist because this kind of decision is made by
  looking, not by reading names.
- **Backups carry `session_log`.** Progress always survived on the topic, but
  the streak and the calibration samples did not, and those are what a student
  earns. Additive, so the format version did not move.
- **Backup and restore go through the system picker** (SAF, over a
  MethodChannel in `MainActivity.kt`). No storage permission: choosing a
  document is the grant. The hardcoded `/sdcard/Download/Prahar` path remains
  only as a desktop and test fallback.
- **Timezone assumes `Asia/Kolkata`** rather than scanning for the first zone
  with a matching offset, which was right in India by luck and a trap abroad.

Features shipped and on the device:

- Planner (greedy, critical-ratio priority), feasibility banner, exam calendar
  (month view under Plan tab), progress screen with per-subject "needs X/day".
- **Exam time** as well as date, optional per subject. A known time stops the
  exam day counting as a whole day of preparation and bars that subject's
  blocks from being scheduled after the paper starts.
- **Card style** picker (Settings > Cards): hairline / plain / lifted /
  tinted / open, each previewed as a real card. All five are keepers — the
  user's call on 4 Sep was to leave them customisable rather than pick one.
- **Study timer** (`lib/ui/timer_screen.dart`): Pomodoro 25/5 or Deep 50/10,
  opened by tapping a block on Today, logs the focused minutes into
  `actual_minutes` so calibration learns from measurement rather than from a
  slider dragged after the fact.
- **Evening digest**: one notification a night with tomorrow's blocks. On by
  default at 21:00, switchable in Settings > Notifications.
- **Today is the editorial screen** (`today_editorial_screen.dart`), chosen
  over the original on 5 Sep after both shipped side by side for an evening.
  The old `today_screen.dart` is deleted, along with the `SessionTile`
  parameters that existed only for it (`isNow`, `onStart`) and the accented
  chip they drove. Back in the nav bar's five destinations.
- Study window + busy slots (weekly and one-off, multi-day picker).
- Topic units stored with rate — pages/problems/minutes; conversion is honest.
- Undo on logged blocks; skip has a confirm; midnight rollover is handled.
- Search across subjects and topics; long-press duplicate; single link per topic.
- Post-exam archive collapse. Backup/restore to `/Download/Prahar/`.
- Calibration loop: on Progress, per-subject recommendations from finished
  topics. Only fires for >=3 samples and >15% drift.
- **PraharMark / PraharLogo** brand widget (CustomPainter). Four placements:
  the Today app bar (always, once a subject exists), the first-run Today
  screen, the top of How Prahar Works, and the Settings footer.
- Theme toggle (Light / Auto / Dark) as a custom pill slider in Settings.
- Inter, bundled and fixed. The picker is gone — see decisions below.
- **Amber accent** alongside the indigo primary: streak, "now" chip, filled
  CTAs, FAB and the two progress bars that measure effort.
- **Materials toggle** (Matte / Glass): frosted glass on the bottom nav, modal
  sheets, the Today header, the feasibility banner and the subject-detail
  status panel. Everything else stays matte.
- Notification permissions, exact-alarm request, battery-exemption prompt.

## Recent decisions worth carrying forward

Each was made after real feedback and previewed against alternatives; don't
undo without reason.

- **Font: Inter**, and only Inter. It won a live-preview picker against six
  alternatives, so on 4 Sep the picker, the `FontChoice` enum and the six
  unused TTFs came out. `PraharTheme.fontFamily` is the single answer now.
  Bundled, never fetched: the release build has no INTERNET permission, and
  a runtime fetch silently yields the system font — that was a real bug.
- **Colour: indigo is structure, amber is effort.** The icon and both
  home-screen widgets were always warm while the interior was cool indigo,
  so the app and its own icon read as two products. Rather than repaint the
  interior, the split is now by meaning: indigo carries navigation,
  selection, focus and "this is today"; amber (`PraharTheme.accent`,
  `accentInk`, `accentOnLight`) carries the streak, the "now" chip, filled
  CTAs, the FAB and the progress bars. Amber lives in the `ColorScheme`
  (`tertiary` for text, the warm `secondaryContainer` for the quiet half) so
  it is reachable from any context and cannot be half-applied.
  **Watch out:** one `FilledButtonThemeData` serves `FilledButton` *and*
  `FilledButton.tonal`, so the theme's amber fill reaches tonal buttons too.
  The two tonal call sites (SessionTile's Done, the calibration card) pass
  `secondaryContainer` back explicitly. A third tonal button will need the
  same treatment.
- **Icon: T3+K4 tuning, zoomed 1.182x.** Sun 0.26, ticks 0.0165 thick on a
  0.3545..0.4018 ring at alpha 135, hand 0.0355 ending at 78% of sun radius,
  pivot 0.0236. The zoom came from "make the sun bigger", which means the
  *whole mark* larger — same proportions and spacing, seen closer — not a
  fatter sun inside the old tick ring. Every number is the original tuning
  times 0.26/0.22; rescale all six together or the two artefacts diverge.
  Numbers live in `tools\make_icon.ps1` and are mirrored in
  `_MarkPainter`; the tuning tools are checked in
  (`make_v2_thickness.ps1`, `make_t3_tick_variants.ps1`,
  `make_v2_launcher.ps1`) so future retunes have the same ladder view.
- **Brand widget**: `PraharMark` is CustomPainter, not a bundled PNG.
  Proportions match the launcher script exactly and are commented as such;
  the two must stay in sync when the mark is retuned. Two deliberate
  departures, both because the icon is drawn once at 1024px and the widget at
  24–56px: the stroke widths have a floor in logical pixels (ticks 1.0, hand
  1.4), and the light palette uses a darker ink at near-full alpha. A
  proportional 0.0165 stroke is 0.4px at 24px, which anti-aliases to a ghost —
  the hour ticks were invisible in light mode until both were fixed. Pale
  strokes on a dark ground bloom and dark strokes on white do not, so the two
  palettes are *not* mirror images of each other.
- **Exam time is a separate optional column, not a timestamp.** `exam_date`
  stays a plain date and `exam_minute` (nullable) carries the hour, so every
  date comparison in the app — calendar grouping, the archive check, the
  planner's day loop — keeps working on a date, and "I know the day but not
  the time" stays expressible. Null means the whole exam day is preparation
  time, which is exactly what every subject did before the column existed.
  The arithmetic is `Subject.prepDaysFrom` — whole days plus the share of the
  study window that precedes the exam. It is one method because the planner's
  urgency score and both "needs X a day" figures divide by it; three copies
  would disagree and the app would tell the student two different stories
  about the same exam. `test/subject_test.dart` pins it.
- **Never quote a rate no day could hold.** Dividing remaining work by
  `prepDaysFrom` means dividing by a *fraction* of a day once an exam is
  hours away, and the figure explodes — 4h of work against a 9am exam
  reported "needs 56h a day". `Subject.examDemand` is the only place allowed
  to answer this: it returns a rate, or `impossible`, and the UI says
  "won't fit before the exam" instead of a number nobody can act on. The
  ceiling is the study *window*, not stated availability — falling short of
  what you intended is normal and the feasibility banner already reports it;
  needing more hours than a day contains is not.
- **Width decides columns, height decides where navigation goes.** Two
  separate questions, in `lib/ui/layout.dart`. Conflating them puts a rail on
  a tall tablet, where the bottom bar is the easier reach. A phone sideways is
  wide *and* short — 891 x 411 — and it is the shortness that makes the rail
  worth it: a 60dp app bar plus a 68dp bottom bar is a third of the screen.
- **`test/landscape_test.dart` is the only way to check a layout here.** MIUI
  refuses adb input injection, so nothing can rotate the phone or drive it to
  a screen; a screenshot shows whatever is already open. The test pumps the
  app at real device sizes and asks whether it threw. It found three real
  overflow bugs on its first run, one of them in the portrait layout that had
  already shipped. Note the test font draws every glyph as a fixed-width box,
  so text is wider there than on the device — which makes the tests
  conservative, not wrong: a row that only overflows in the test is one that
  overflows on a phone set to a large font scale.
- **A finished exam is not a shortfall.** Work behind an exam that has already
  happened is excluded from the planner's `work` map entirely. The day loop
  refused to schedule it anyway, so it used to arrive at the feasibility pass
  as "unscheduled" and report the plan impossible — permanently, over a
  subject nothing can be done about. Today's banner said the plan did not fit
  and there was no action that could make it fit.
- **"Archived" means the same thing everywhere.** Subjects and Progress both
  fold past-exam subjects into an Archive section off `state.archivedSubjects`,
  and Progress's headline percentage counts only what is still ahead — a
  finished subject would otherwise hold it down for good over work that can no
  longer be done, which reads as failure rather than as history.
- **Deleting a subject deletes its log too.** `session_log` carries no foreign
  key on purpose — it is an audit trail and outlives the topic it describes —
  so nothing cascades into it, and a deleted subject went on appearing in
  today's list and counting towards the streak. `AppState.deleteSubject` now
  clears it explicitly and reloads the log and streak.
- **A `Spacer` does not stop a `Row` overflowing.** Inflexible children are
  laid out first at their natural size and the spacer takes what is left,
  which can be nothing. The Progress card looked safe for exactly this reason
  and was not. Use `Expanded` on the element that should give way.
- **The timer is derived from the wall clock, never from ticks.**
  `lib/domain/study_timer.dart` is pure: given a start instant, accumulated
  pause and "now", it computes the phase, the seconds left and the focused
  time. `Timer.periodic` in the screen exists only to repaint. This is not
  fussiness — Android freezes the process when the screen goes off, which is
  precisely when a focus timer is running, so a tick-counting implementation
  loses every minute the phone spent asleep. `test/study_timer_test.dart`
  jumps the clock the way a sleeping phone does, without a tick firing.
  The end of each interval is handed to the OS as an alarm (id 3) for the
  same reason.
- **The digest is a rolling window, not a repeating alarm.**
  `matchDateTimeComponents` would repeat one body forever — correct the first
  night, and confidently wrong every night after, describing a day that had
  already happened. `syncDigests` writes one notification per evening for a
  week (ids 100+), each with its own summary, refreshed on every replan and
  every resume. If the app goes unopened for a week the digests run out,
  which is the right failure: silence beats a wrong summary.
- **Notification ids are partitioned and the partitions matter.** 1 retired
  digest, 2 test, 3 timer, 100–106 digests, 1000+ study blocks. Each sync
  cancels only its own range. `cancelAll()` in `syncFromPlan` once destroyed
  the digest and any test reminder on every single edit.
- **Do not claim irreversibility the app does not have.** The skip dialog
  warned in red that skipping "cannot be undone" while a skipped block sat in
  Today's list with an Undo button next to it. It also promised the work
  would not be offered again "this afternoon", which is only true if you skip
  in the morning. Copy that describes behaviour has to be re-read whenever
  that behaviour changes.
- **Card styles are five different ideas, not five weights.** An outline, a
  tonal step, a shadow, a colour wash, and nothing at all. Anything subtler
  is a preference nobody can see. The picker draws each one as two stacked
  Progress cards on the real scaffold colour, because a single card in
  isolation looks fine and only turns into a grid once it has a neighbour —
  which is the failure mode that made hairlines the original choice. Hairline
  is still the default.
- **Long user strings need a line of their own.** A subject called "Data
  Structures and Algorithms" collided with "49 days left" on Progress,
  because the name shared a Row with a right-aligned meta. The name is the
  one string the app does not control, so it now takes the full width and
  the deadline moved to its own wrapping line. Check any new Row that mixes
  a user string with app text.
- **Glass**: the Today app bar, the bottom nav, modal sheets, the Today hero,
  the feasibility banner and the subject-detail status panel. Surface alpha is
  **0.28**, arrived at in three steps — 0.55/0.60 had the tint carrying the
  surface with the blur as decoration, 0.42/0.45 was better, and 0.28 is the
  one that reads as glass rather than as a panel that happens to blur. The
  trade is accepted deliberately: this thin, text on the glass has to hold its
  own against what scrolls under it, which works because these surfaces carry
  short high-contrast text. Dense body copy on glass would need the
  `tintAlpha` override. Contrast between matte and glass is what carries the
  effect, so do not spread it to cards, list rows or Progress. The rule that
  emerged: glass marks a panel that *summarises*, matte is for anything that
  *lists*.
- **The Today app bar is glass and the body runs under it** — `Scaffold`'s
  `extendBodyBehindAppBar` with a `GlassSurface` in `flexibleSpace`. Today
  only: extending the body means that screen must inset its own scroll view by
  the bar height (read from `appBarTheme.toolbarHeight`, not assumed), and
  Today is the screen whose design is about content flowing under a fixed
  mark. If another screen ever wants it, it needs its own inset.
- **Every surface follows the card style.** The Today hero is a `Card` in
  matte and the rail rows are `Card`s always, so both wear whatever Settings >
  Cards is set to. A hand-rolled `Container` with `surfaceContainer` and an
  `outlineVariant` border looks identical to the Hairline style and silently
  ignores the other four — if a new surface needs a card, use `Card`.
- **Use `StyledPanel`, never a hand-rolled surface.** It is in `glass.dart`
  and it is what answers to both Settings > Materials and Settings > Cards.
  Today's hero uses it and so does the preview card on Appearance. The
  preview was a `Container` with its own gradient and border for a day, which
  meant the one surface whose job was to demonstrate the card style was the
  only one ignoring it.
- **A Card paints its outline *under* its child.** A filled child hides it,
  which is why the hairline never appeared on the glass hero until the border
  moved to a foreground `DecoratedBox`. Do not try to read the side back off
  `theme.cardTheme.shape` — that introspection returned no side at runtime
  even where the theme plainly had one. Take it from the `CardStyle`.
- **A `Stack` top-aligns anything it is not positioning.** The theme toggle's
  labels sat 14dp above the pill's centre for three rounds of "fixing" the
  horizontal arithmetic, which had been right the whole time, because the test
  asserted centres on `dx` alone and kept passing. **When a measurement and
  the user disagree, the measurement is the thing that is incomplete.** Assert
  both axes.
- **Scroll views end with `navBottomInset(context)`, not 90.** 90 is the nav
  bar's height under gesture navigation only.
- **Copy rules, learned when the user said the text read as AI-written.** No
  em-dashes — there were twenty-odd, and they are the loudest tell. Do not
  explain the reasoning to the reader: "so the plan reaches you without you
  having to open anything" and "the contrast between materials is what carries
  the effect" are design rationale wearing the costume of product copy. A
  person writing a label says what the thing does. Reasoning belongs in this
  file, which is read every session; a UI string is read by a student.
  Jargon has the same problem — a planner warning said "cycle", which is a
  graph property and not a thing a student thinks about.
- **Do not pin copy in tests.** One planner test matched the word "cycle" and
  held the rewrite hostage. Match the concept.
- **Calibration model**: uses only completed topics. In-progress work is
  tempting evidence but prorating by minutes cancels arithmetically and
  always recovers the prior rate. This bug hid in the first draft; the test
  suite pins it now — don't "improve" it back into a broken model.
- **Widget layouts: only view classes marked `@RemoteView`, and only
  pre-API-26 attributes.** RemoteViews inflates through a filter that rejects
  any class without that annotation, and `android.view.View` does not have it
  — so a bare `<View>` used as a divider takes the whole layout down. That is
  what was still breaking `TodayWidget` on 5 Sep, long after the attribute
  problems were fixed: `LinearLayout` and `TextView` throughout, and an empty
  `TextView` with a background where a divider is wanted.
  Attributes to avoid: `paddingHorizontal`, `layout_marginVertical`,
  ProgressBar `min`, `?android:attr/...` style refs. Use
  `paddingLeft/Right/Top/Bottom` and legacy variants.
  **One correction to the old note: `letterSpacing` is fine.** The 2x1 widget
  has used it since it shipped and renders correctly; it was on the banned
  list for years on no evidence.
  Every failure of any of these is the same generic "Can't load widget" with
  no line number, so adding a new view type here is a gamble that has to be
  tested on the device.

## Open feedback — start here

Nothing from any earlier review list is outstanding. The week grid shipped on
6 Sep; the Gantt-style subject timeline is the last unbuilt idea from that
pair, and the argument against it still stands — it overlaps Progress and the
exam calendar, its horizontal axis has no clean answer over a 60-day span, and
it should only be built if the week view leaves something genuinely unanswered
after a few weeks of use.

What is actually open, in order:

1. **The splash-animation decision** at the top of this file. Options 1, 2, 3;
   3 was recommended and costs nothing.
2. **Distribution.** Free route decided, not started.
3. **The copy pass was a pass, not a sweep.** The subject and topic sheets and
   some Progress strings were not gone through. See the copy rules under
   *Recent decisions*.
4. **`flutter_timezone`**, only if this app ever leaves India.
5. **A test pinning the six brand numbers** shared between `_MarkPainter` and
   `make_icon.ps1`. Still the only silent-drift hole in otherwise well-netted
   code, and now more valuable: the animation reuses those same numbers.

### The device question, answered on 6 Sep

The user asked whether the app works on all phones. The audit is worth not
repeating:

- **There is no iOS build. No `ios/` directory exists.** Adding one is a
  project, not a task: notifications differ, the battery-exemption channel has
  no equivalent, the SAF picker would be rewritten, both widgets would become
  WidgetKit extensions in Swift, **and it cannot be built on Windows at all** —
  macOS and Xcode are required. Say this plainly if it comes up again.
- Android 7+ (`minSdk` 24), targeting 36. Xiaomi, Pixel, Samsung, OnePlus,
  Motorola and Vivo are all fine as far as the code goes.
- **The real risk is OEM background killing**, not layout: Xiaomi, Vivo, Oppo
  and Samsung gate autostart behind their own settings, which the battery
  exemption does not cover. It is the most likely reason a real user would say
  reminders stopped.
- Two defects that only showed on other people's phones were found and fixed
  by `test/device_matrix_test.dart`, which pumps every screen at 320dp and at
  a 1.5x font: the theme toggle overflowed at large font sizes, and every list
  reserved a hardcoded 90 for the nav bar without consulting the system inset,
  so the last row sat under three-button navigation. **The three-button case is
  reasoned, not seen — this phone uses gestures.**

Otherwise the queue is the longer-term roadmap below.

## Architecture

Layers, strictly inward-depending:

```
ui/  ──►  state/  ──►  data/        (SQLite)
                  ──►  planner/  ──►  domain/
                  ──►  notifications/
```

### The purity rule

`lib/domain/` and `lib/planner/` must not import Flutter, touch the database,
or perform any I/O. This is the single most important constraint in the
codebase. It is what lets the planner be tested exhaustively without a device,
and what would make a future backend possible without a rewrite. If you find
yourself wanting `BuildContext` or a DB handle in `planner.dart`, the logic
belongs in `state/app_state.dart` instead.

### Never use `ConflictAlgorithm.replace`

`ConflictAlgorithm.replace` compiles to `INSERT OR REPLACE`, which does **not**
update in place — it DELETEs the conflicting row and inserts a new one. This
database sets `PRAGMA foreign_keys = ON` and declares `ON DELETE CASCADE`, so
that hidden delete cascades: saving an edited subject destroyed every topic
beneath it, and saving an edited topic destroyed its resources.

This shipped, and was only caught by watching a real device lose data. The write
reports success, no error is logged, and the schedule simply empties out — which
looks like a planner bug, not a storage one.

Every write goes through `PraharDatabase._upsert`, which does UPDATE then INSERT
if nothing was updated. `test/database_test.dart` pins the behaviour; those
tests were confirmed to fail (`Expected: <2>, Actual: <0>`) against the old
code, so they genuinely catch a regression rather than merely passing.

Explicit `deleteSubject` / `deleteTopic` still cascade, which is intended, and
is also covered.

### Migrations: bump the version, never edit a shipped one

**Once a schema version has run on a real device, editing that version's
code does nothing** — `openDatabase` believes the migration completed and
never re-runs it. I once slipped a new table into `_v2` after v2 had shipped;
every device already at v2 was permanently missing the table, and every
save into it threw silently. The bug looked like a broken feature.

Every schema change now gets a new version and a new `_vN` function.
`_upgrade` chains them (`if (from < N) await _vN(db);`). Each `_vN` is
idempotent (`CREATE TABLE IF NOT EXISTS`, `ALTER TABLE ... ADD COLUMN` guarded
by `PRAGMA table_info`) so a redundant call cannot break an install.

Current version: **5**. `_v2` records estimate provenance (unit/amount/rate)
and adds `settings`. `_v3` adds `busy_slots`. `_v4` adds `topics.link`.
`_v5` adds `subjects.exam_minute`.

### Sessions are derived, not stored

`StudySession` objects are **regenerated from scratch** on every change — they
are never persisted. The database stores subjects, topics, resources,
availability, and a `session_log` of what actually happened. The schedule is a
pure function of those inputs plus today's date.

Persisting the schedule would create a second source of truth that drifts the
moment a student edits a topic or misses a day. It also makes "replan" free: it
is just another call to `Planner.generate`.

The corollary: **anything the student did must be recorded on the Topic**
(`completedMinutes`, `status`, `firstCompletedOn`) or in `session_log`, never
only on a session object. A session is disposable.

Session ids are content-addressed (`kind|date|startMinute|topicId`), never a
running counter. A counter produced ids that pointed at a *different* block
after each replan, so anything remembering "session 3 is done" silently
referred to the wrong one. Keep them derived from content.

### The planner

`lib/planner/planner.dart` is greedy, not an optimiser, and intentionally so:

- it runs in microseconds, so replanning on every edit is free;
- its output is explainable — you can always say why a block landed where it did;
- it is **stable**, so one missed session shifts work forward instead of
  reshuffling the whole month.

Day loop: reviews due today first (short and time-critical), then new material
by `_priority`, subject to prerequisites, the subject's own exam deadline, an
interleaving cap, and a 22:00 day end.

**`_priority` is the critical-ratio (least-slack) heuristic:
`remainingWorkForSubject / daysUntilExam`** — the minutes per day a subject
demands. Do not "simplify" it back to `1 / daysToExam`. That earlier version
ignored workload and ranked a 1-hour subject due in 30 days as twice as urgent
as a 40-hour subject due in 60, which is backwards by a factor of 25 and hides
the failure until the week of the exam. `test/planner_test.dart` →
`weighs workload, not just deadline distance` pins this.

Two escape hatches exist because rigid rules were worse than the problem:

- `urgencyOverrideRatio` (3.0) lets a subject in crisis break the interleaving
  cap. Without it an exam in two days still surrendered a third of every day.
- `reviewShareOfDay` (0.4) caps reviews. Four rungs per finished topic, placed
  first every day, otherwise crowd out new material entirely.

Reach for OR-Tools CP-SAT only if these schedules turn out to be genuinely bad.
Do not add a solver to fix what is really a priority-weighting problem.

### Dates

Iterate calendar dates with `DateTime(y, m, d + 1)`, **never**
`add(Duration(days: 1))`. The latter adds 24 *hours*; across a DST boundary it
lands at 23:00 the previous evening, so two iterations report the same date and
the schedule double-books. Irrelevant in India, real anywhere with DST. The same
applies in `Availability.totalBetween` and the review ladder.

### Feasibility is a feature

`Planner` always returns a `Feasibility` alongside the sessions, and the UI
shows it prominently via `FeasibilityBanner`. When work exceeds available time
it says so bluntly and per-subject. Do not soften this or hide it behind a
tap — a planner that silently generates an impossible schedule is worse than no
planner, because the student only discovers the problem the week of the exam.

### Effort estimation

Students cannot estimate minutes but can count pages. `EffortEstimator`
converts pages / problems / video runtime into minutes, and the topic sheet
defaults to **pages**, not minutes.

`EffortEstimator.calibrate` blends observed rates with the prior, weighted
`n / (n + smoothing)`, so one interrupted session nudges the rate instead of
wrecking every future estimate. `session_log.actual_minutes` exists to feed
this — per-subject calibration is wired for data but not yet applied to
estimates (see Roadmap).

### Notifications

Local alarms only, via `flutter_local_notifications`. No FCM, no push, no cost.
The whole plan is known in advance, so reminders can be handed to the OS and
work offline and force-stopped.

### Two device findings that cost hours to isolate

**Battery optimisation decides whether the app works at all.** Without an
exemption Android freezes the process, and a correctly registered exact alarm
wakes nothing: the reminder appears only when the user next opens the app by
hand, which is precisely when it is useless. Verified on a Xiaomi device —
identical code, exemption off: nothing arrived; exemption on: it arrived to the
minute. `_BatteryWarning` on Today is the loudest thing in the app for this
reason. The prompt is a hand-written `MethodChannel` in
`android/app/.../MainActivity.kt` — not a package. `permission_handler` was
tried and removed because it requires Android SDK 37, which installs as
`android-37.0` under Android's new minor-version scheme while Gradle looks
for `android-37` and fails. Two Kotlin methods do the same job.
`tools\dev.ps1 exempt [off]` toggles it over adb for testing.

**A channel inherits the *default notification sound*, which may not exist.**
On this device `settings get system notification_sound` returns `null`, so
reminders vibrated and reached the lock screen in complete silence. Setting
`audioAttributesUsage: alarm` alone did not fix it — that changes the stream,
not the sound. The channel now names `content://settings/system/alarm_alert`
explicitly. Never rely on the default notification sound existing.

Diagnose both with `tools\dev.ps1 notif`, which reports channel importance and
audio usage, the standby bucket, the exemption, and the system sound settings.

Two further Android facts dominate this code:

1. **Exact alarms** need `SCHEDULE_EXACT_ALARM`, which the user grants on a
   separate settings screen. Without it Android batches reminders into idle
   windows and a 6pm reminder can land at 7:20pm. `Notifier.canScheduleExact()`
   drives a visible warning banner rather than failing silently.
2. **Pending-alarm limits** (iOS caps at 64; Android's exact-alarm budget is
   finite) mean a rolling 14-day window of at most 56 alarms, topped up on every
   replan and on app resume (`HomeScreen.didChangeAppLifecycleState`).

`syncFromPlan` cancels and reschedules rather than diffing. A stale reminder for
a session that no longer exists costs more trust than the milliseconds saved.

**It must not use `cancelAll()`.** Notification ids are partitioned: 1 is the
daily digest, 2 the test reminder, and session alarms start at
`_sessionIdBase` (1000). `syncFromPlan` cancels only ids at or above that base.
An earlier version called `cancelAll()`, which meant every replan — and a
replan happens on every single edit — silently destroyed the digest and any
test reminder. That class of bug is invisible in testing, because the alarm
registers correctly and simply never survives to fire.

`Notifier.scheduleTest()` fires a one-off reminder a minute out, surfaced in
Settings. It is the only way to exercise the full delivery path (alarm
registered → process woken → notification drawn) without waiting for a real
study block. Re-run it after changing any battery or autostart setting: on
aggressive vendors those silently break delivery while leaving the alarm
registered and visible in `dumpsys alarm`.

## Android build requirements

Both are already applied; do not remove them.

- `android/app/build.gradle.kts`: `isCoreLibraryDesugaringEnabled = true` plus
  `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")`. Without
  it the build fails with an opaque error about `java.time`.
- `AndroidManifest.xml`: `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`,
  `RECEIVE_BOOT_COMPLETED`, `VIBRATE`, plus the two
  `com.dexterous.flutterlocalnotifications` receivers so alarms survive reboot.

**`USE_EXACT_ALARM` is deliberately absent.** It is auto-granted, but Google
Play restricts it to alarm and calendar apps; a study planner would be rejected.
`SCHEDULE_EXACT_ALARM` plus the in-app prompt is the compliant path.

**`wakelock_plus` adds no permission.** It sets `FLAG_KEEP_SCREEN_ON` on the
window rather than taking a real wake lock; checked against the merged
manifest on 5 Sep, not assumed.

**If this is ever submitted to Play, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`
is the permission most likely to be challenged.** Google restricts it to a
narrow set of use cases. The justification here is unusually strong and
evidence-backed — reminders demonstrably do not fire without it on this
device, which is what `_BatteryWarning` exists for — but expect to argue it,
and expect the fallback to be sending the user to system settings by hand.

**The NDK must be installed even though nothing here compiles native code.**
AGP resolves an NDK while configuring `:app` regardless, and the failure is
disguised: it shells out to `sdkmanager`, the id `ndk;28.2.13676358` splits on
the `;`, and the wrapper crashes with `0xC0000409` — so the build dies with a
process-exit error that never mentions the NDK.

Two avoidance routes were tried and **both failed identically**; do not retry
them:

- removing `ndkVersion = flutter.ndkVersion` from `android/app/build.gradle.kts`
- setting `android.builder.sdkDownload=false` in `android/gradle.properties`

The fix is to install it:

```powershell
tools\dev.ps1 sdkpkg "ndk;28.2.13676358"
```

Quote the id at the call site as well — an unquoted `;` ends the statement in
PowerShell before the script sees it. `sdkpkg` handles any package id and
ignores sdkmanager's exit code, listing what actually landed instead.

### sdkmanager quirks (all three cost real time to rediscover)

- Package ids contain `;`, which `cmd.exe` treats as an argument separator when
  PowerShell invokes a `.bat`. `tools\dev.ps1 androidsdk` builds the command
  line and lets `cmd` parse it; passing the ids as ordinary PowerShell
  arguments splits `platforms;android-36` into two unknown packages and
  installs nothing.
- `sdkmanager` is deprecated and delegates to a new Android CLI that can crash
  on exit with `0xC0000409` *after* installing everything correctly. Never
  trust its exit code — `androidsdk` checks the package directories instead,
  in both directions (it also lies the other way, reporting success for
  packages it skipped).
- **`flutter doctor` reports "Android license status unknown" and this is
  cosmetic — proven, not assumed.** Flutter decides licence status by parsing
  `sdkmanager --licenses` output; the new CLI replies "The --licenses option is
  no longer needed" and writes nothing Flutter recognises. The licence file at
  `<sdk>\licenses\android-sdk-license` is real and works: during the first
  successful APK build, AGP needed SDK Platform 35, logged "License for package
  Android SDK Platform 35 accepted", and installed it. Do not chase this
  warning.
- Note that AGP's *internal* SDK installer works fine — it installed platform
  35 without trouble. It is specifically `sdkmanager.bat` that is broken, which
  is why `sdkpkg` exists.

## This machine's network is unreliable for large downloads

Three separate large downloads failed here, all in the same way — a slow link
plus a downloader with no resume and no retry:

- `Invoke-WebRequest` buffers the whole body in memory on PowerShell 5.1 and
  died with `OutOfMemoryException` on the 1.8 GB Flutter SDK.
- The Gradle wrapper uses `java.net.HttpURLConnection` and timed out twice on
  `gradle-9.3.1-all.zip`, failing the first `apk` build.

**Use `curl.exe` for anything large** — it streams to disk, resumes with `-C -`
and retries. `tools\dev.ps1 gradledist` exists precisely because the Gradle
wrapper cannot fetch its own distribution here; run it before the first build
on a fresh machine, or whenever a build fails with `ConnectException` while
"downloading artifacts from the network".

## Timezones

`Notifier._initTimeZone` resolves the device zone by matching the current UTC
offset against the `timezone` database, rather than adding another plugin.
Exact for zones without DST (India included) and correct across the two weeks
actually scheduled. Replace this if long-horizon scheduling across a DST
boundary is ever needed.

## Longer-term roadmap

Ranked, still valuable but behind the *Open feedback* list above:

1. **FSRS** instead of the fixed `[1, 3, 7, 21]` review ladder, once recall
   quality is logged. The timer is the natural place to ask "how did that
   go?" now that one exists.
2. **Full resources per topic** — the schema has a full resources table
   supporting multiple entries (book/video/pdf/url/problem-set) with
   progress; we currently expose one `link` string. Building the resource
   sheet unlocks multi-source topics without a schema change.
3. **Sound design** — a proprietary three-note chime instead of the
   system alarm tone. Distinctive without being obnoxious.
4. ~~Keep the screen awake during a timer.~~ **Done, 5 Sep.**
   `wakelock_plus` is held while the clock runs and released on pause, on
   leaving and on dispose. It adds no Android permission — it sets
   `FLAG_KEEP_SCREEN_ON` on the window rather than taking a real wake lock,
   which was checked against the merged manifest. The calls swallow their
   errors: there is no plugin behind the channel in a widget test.

Deliberately *not* on any roadmap: accounts, sync, SMS, WhatsApp. Local-first
is a design commitment. If notifications ever get more channels, they go
behind a `NotificationChannel` interface so the planner never learns about
them; the planner stays a pure function of subjects, topics, availability
and today's date.

## Version control

Git repository on `main` with a public remote at
**https://github.com/TheSidPai/Prahar**. Commits are attributed to a
noreply address (`<id>+TheSidPai@users.noreply.github.com`), set repo-local
only so the global git config is untouched. Author's real email must not
appear in any commit; the noreply is the truth.

Push cadence has been "one commit per meaningful round" rather than per file.
Follow that — the commit log is intentionally a story of decisions, not a
mechanical activity log.

`android/local.properties` is untracked deliberately — it holds machine-specific
SDK paths and is regenerated by the Flutter tool. If a fresh clone fails to
build, that file being absent is expected; running any `tools\dev.ps1` task
recreates it.

`.gitattributes` normalises everything to LF. Without it, a Windows checkout
commits CRLF and the whole tree shows as rewritten the first time it is touched
elsewhere.

`.git-blame-ignore-revs` lists commits that changed formatting only, so
`git blame` attributes a line to the decision that wrote it rather than to the
formatter. It holds one SHA today, the tall-style adoption. GitHub reads the
file by name; locally it needs `git config blame.ignoreRevsFile
.git-blame-ignore-revs`, which is repo-local and does not survive a clone.

Keystores and `key.properties` are ignored at both the root and in `android/`.
Nothing signing-related may ever be committed.

**"A lost keystore means the app can never be updated again" is only half
true, and the half that matters here is different.** That warning describes
the legacy model where the developer holds the *app signing* key. Under Play
App Signing — the default for new apps — Google holds that key and yours is
only an *upload* key, which can be reset through Play support if lost. So
losing it is recoverable once the app is published.

What is **not** recoverable is the local case, and it applies today, long
before anything is published. Android refuses to install an update signed by a
different key than the installed app. The release build currently falls back to
the machine's throwaway debug keystore, so if that file goes — new machine,
reinstalled SDK, a cleared `~/.android` — the next build cannot install over
the app on the phone. The only route in is an uninstall, and this app keeps
every subject, topic and session log in local storage and nowhere else.

That is the real argument for making a keystore now rather than at publishing
time, and it has nothing to do with the Play Store.
