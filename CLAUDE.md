# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Where to find what

- **This file**: how to work in this repository. Commands, this machine's
  quirks, the rules for commits and permissions, the current state and the open
  work.
- **[ARCHITECTURE.md](ARCHITECTURE.md)**: how the system works. Layers, data
  model and storage, the planner, calibration, notifications and the OEM
  background gates, the Android layer, UI structure, testing and known
  limitations. **Read the section your task touches before changing it.**
- **[README.md](README.md)**: for people installing or building the app.

When behaviour changes, update ARCHITECTURE.md in the same commit. When the
project's state or the queue of work changes, update this file. Nothing about
how the system works should live only here.

## For a fresh session

Read, in order: **Where things stand**, then **Open work**, then the
ARCHITECTURE.md section your task touches. The rest of this file is reference,
and every paragraph in it was learned the hard way.

### Where things stand, as of 11 Sep

**Prahar 0.2.0 is released.** A signed APK is on GitHub Releases under tag
`v0.2.0`, at commit `4477223`. `main` is level with `origin/main`. The user
pushes, never Claude.

- 310/310 tests pass and `analyze` is clean.
- **Verified on hardware**: a Xiaomi 23127PN0CG (HyperOS, Android 16) and a
  OnePlus Pad (OxygenOS 16). Reminders reaching the lock screen with sound, the
  autostart deep link on both, the tablet two-pane layout, landscape, and the
  first-run screen.
- Signed with the user's own key: `dev.ps1 signer` must print `CN=Siddhant`.
- Release APK is about 53.2 MB and builds in 90 to 150 seconds warm.
- Version `0.2.0+2`. The number after `+` must go up on every release.

The branches `presquash-6sep` and `presquash-7sep` hold pre-squash history and
are safe to delete. Both squashes were verified with an empty
`git diff <branch> HEAD`.

**The development phone has dismissed the autostart notice for good.** The flag
lives in the app's SQLite, which a release build doesn't expose over adb
(`run-as` needs a debuggable build), so it can't be reset without clearing app
data, which would destroy the user's real subjects and history. The snooze
ladder is covered by tests instead, and the permanent row in
Settings > Notifications is still there. **The OnePlus Pad was a fresh install**
and is the device to see the card on.

**`.claude/settings.json` drifts every session** and must be reverted, not
committed. See *Run Claude from this directory*.

**Android only.** There is no `ios/` directory, and an iOS build can't be made on
Windows at all (ARCHITECTURE.md, section 12). Say so plainly if it comes up.

**One design decision is open.** The user asked whether the launcher icon can
animate on the home screen as the app is minimised. It can't: the launcher draws
the icon, adaptive icons are two static layers, and no API lets an app animate
its own. The real version of that moment is the opposite one: Android 12+ plays
an `AnimatedVectorDrawable` as the launch splash
(`windowSplashScreenAnimatedIcon`). The options put to the user:

1. Do nothing. The tap replay and the return greeting already give the mark two
   reliable moments.
2. Build the splash animation, generated from a tool script so the mark's six
   tuned numbers aren't hand-copied into vector XML a third time.
   **Recommended**, sequenced after the brand-number test (open work, item 5),
   because that test is what makes a third copy safe.
3. Play the unfurl on Today's app bar on every cold start. Free, but an
   animation on every launch turns from a delight into a tax, and it competes
   with the screen painting in.

### Also settled

- **Landscape and tablet have been seen**, not just tested: landscape on the
  Xiaomi on 5 Sep, the tablet layout on the OnePlus Pad on 7 Sep. Keep writing
  layout tests for the next visual change; that gap is still real.
- **The tree is in the tall `dart format` style**, adopted in one formatter-only
  commit on 5 Sep. `dev.ps1 format` is safe to run.
- **The permission question is closed.** See *Use these exact command shapes*.
  Don't re-test it.

### Files you will touch most

- `lib/planner/planner.dart`: the scheduler
- `lib/planner/calibration.dart` and `estimator.dart`: effort and pace learning
- `lib/state/app_state.dart`: the single `ChangeNotifier`
- `lib/data/database.dart`: SQLite and migrations (bump the version)
- `lib/notifications/notifier.dart`: alarms, digests, timezone
- `android/app/src/main/kotlin/com/siddhantpai/prahar/MainActivity.kt`: the
  battery, autostart, widget and file channels
- `lib/ui/today_editorial_screen.dart`, `layout.dart`, `theme.dart`,
  `glass.dart`, `brand.dart`
- `tools/dev.ps1`: every build and device action

## Agreed next build: the first-run tour

Prompted by a first-time user (the user's parent) who opened the app with no
context and couldn't tell what to do. The first-run screen's "How Prahar works"
link was right there and wasn't noticed, and reading an explanation wasn't what
was needed anyway. Designed with the user on 11 Sep. The ? help sheet on Today came first and is
where the tour's replay will go.

**Built, and redesigned on 12 Sep after the user tried it on the phone.** The
first build waited for real taps on some stops, which confused; everything
below the look was replaced. What stands now, agreed from an HTML preview
page and seen installed on the Xiaomi:

- A paper note (`#F3EDE3`, ink text, indigo Next), dashed arrows landing on the
  middle of the target's edge, Back from the second stop, Skip by the step
  count, the window sliding between stops.
- The main tour, eight Next-only stops, switching tabs itself, with drawings
  marked Example for what an empty app lacks, Plan and Progress as a pair of
  side notes, and a last card with Add your first subject.
- A five-stop first-block tour for Start focus, Skip and Done, once, when Today
  first has a real block.
- The Plan mini-tour idea is dropped: Plan and Progress are covered in the main
  tour.

How it works is in ARCHITECTURE.md, section 10.

Decisions the user made:

- **A do-tour, not a look-tour.** The user really adds a subject and a topic
  during it. On a fresh install Subjects and Today are empty, so a look-only
  tour has nothing to point at; doing the setup *is* the tour.
- **Starts automatically on first launch**, when there are no subjects, with
  **Skip** on every step.
- **Existing installs don't matter yet.** Too few users to design for.

The sequence (read: a bubble to tap past; do: waits for the action):

1. Welcome card: the mark, "Welcome to Prahar", two lines, Show me around or
   Skip. (read)
2. The nav bar, **one stop only**: five tabs, start with Subjects. Don't name
   all five. (read)
3. Tap Subjects. The tour waits for the tap rather than switching for them.
   (do)
4. Tap + Subject and save it. The overlay steps aside while the sheet is open
   and returns once it's saved. (do)
5. The new subject row: the exam date decides how much to do each day. One
   sentence, never the algorithm. (read)
6. Add a topic: usually a chapter, with its page count. (do)
7. Reminders: explain, then notifications, exact alarms, battery, autostart,
   and a test reminder. (do)
8. Today, two or three stops: what to study now; Start focus and Done; the rest
   of today. End on "tap Plan any time". (read)

Keep read-only bubbles to about four in total.

Things that have to be right:

- **Reminders come before Today, for two reasons.** The Android permission
  prompts currently fire at launch in `main.dart`, before the first frame, so
  they would land on top of the welcome card; that request must move into step
  7. And until battery is unrestricted, Today shows the red "Reminders will not
  arrive" card right above the block the tour is presenting.
- **Resume from the data, not a stored step number.** No subject: step 3. A
  subject but no topic: step 6. A topic but reminders not granted: step 7. The
  same principle as the derived plan.
- **Branches:** a cancelled sheet prompts again rather than breaking; a subject
  saved without an exam date gets nudged back to set one; Today with nothing
  planned (set up late at night, or an exam date that is today or past) needs
  its own wording.
- **Plan gets its own short tour on the first deliberate visit**, never inside
  the main one. At most three stops (Days, Week, Month). It must target what is
  actually on screen: a phone shows the Days/Week/Month toggle, a wide layout
  shows the week grid beside the month calendar with no toggle. Progress waits
  until it has real content, or has no tour. Settings needs none.
- **Look:** a dim overlay with a soft rounded cut-out and a thin indigo ring
  (indigo means focus); the bubble follows Cards and Glass like any surface;
  Next is amber (a call to action); plain copy, no dashes; fits 320dp at 1.5x
  text; the bubble never covers its own target; targets measured from the real
  layout, including the landscape rail, tablets and three-button navigation.
- **Testing:** both dev devices already have data, so the tour won't appear on
  either. Replay from the ? sheet ("Show me around again") is how it gets seen,
  and each step needs a widget test, since the Xiaomi can't be driven over adb.

## Open work, in order

The order is the argument, so the reasoning stays with it.

1. **Session logging: how much was covered, and how well it went.** Two linked
   gaps, one dialog, one schema change.
   - *Units covered.* Logged minutes are added to a topic's progress, while
     calibration reads the same number as effort. A student who spends 80
     minutes on 40 minutes' worth of pages is recorded as further through the
     topic than they are, and a topic can be marked done at half its material.
     The full analysis is in ARCHITECTURE.md, section 6, "Known gap". Proposed:
     minutes stay automatic from the timer, and the done dialog asks how far they
     got, in pages or problems, pre-filled with what the plan expected so the
     common case is one tap. Topics entered in minutes keep today's behaviour.
   - *Recall grade* (Again, Hard, Good, Easy, skippable). Time-sensitive: history
     can't be collected retroactively, so every week without it is a week FSRS
     will never have.

   This changes what "done" means, so it needs its own session with the user,
   not an unattended run.
2. **Autostart targets on vendors nobody here owns.** Run `dev.ps1 vendorpkgs`
   on any phone that becomes available.
   - OnePlus, Oppo, Realme: `com.oplus.battery/com.oplus.startupapp.view.StartupAppListActivity`.
     **Confirmed on OnePlus.** Realme is inferred from the same ColorOS base.
   - Xiaomi: **confirmed**, including after resolution changed to require
     exported activities.
   - Pixel, Motorola, Nothing, Sony: correct by construction. Nothing resolves
     and no card appears.
   - **Samsung: still a guess**, and the most widely used unverified vendor.
     Vivo, Huawei and Honor likewise.
3. **Back up the release keystore off this machine.** Urgent now rather than
   theoretical: 0.2.0 is public, and a lost key means no future release can
   install over anyone's existing copy. Every subject and log is local-only, so
   an uninstall loses it. Never into the repository, never into CI.
4. **Finish the copy sweep.** Done on 7 Sep: Settings > Notifications and the
   worst jargon across the app. Still untouched: the subject and topic sheets,
   the busy-slots screen and How Prahar Works. Look for Android's vocabulary
   leaking into copy ("exact alarms", "JSON", "backdrop blur") and names that
   describe implementation rather than effect ("Reschedule", "Estimate learned").
5. **A test pinning the six brand numbers** shared by `_MarkPainter` and
   `tools/make_icon.ps1`. The only silent-drift hole in otherwise well-netted
   code, and the precondition for option 2 of the splash decision.
6. **The splash decision**, above.
7. **`flutter_timezone`**, only if the app ever ships outside India.

The Gantt-style subject timeline stays unbuilt. It overlaps Progress and the
exam calendar, a 60-day horizontal axis has no clean answer, and it should only
be built if the week view leaves something genuinely unanswered after a few
weeks of real use.

### Longer term

1. **FSRS** in place of the fixed 1, 3, 7, 21 ladder, once the recall log has
   months behind it. Fitting a scheduler to three sessions is fitting it to
   nothing.
2. **Full resources per topic.** The schema and estimator already handle
   multiple books, videos and problem sets with progress; the UI exposes one
   link. No schema change needed.
3. **Sound design**: a distinctive three-note chime instead of the system alarm
   tone.

Deliberately on no roadmap: accounts, sync, SMS, WhatsApp. Local-first is a
commitment.

## Run Claude from this directory

`cd` into the project root before starting Claude. This file and
`.claude/settings.json` are only loaded when the working directory is the
project. Starting from a parent directory silently skips both, and any
permission granted lands in *global* settings instead, where it follows you into
every unrelated repository.

Which settings file holds what: `.claude/settings.json` is **tracked in git** and
so holds nothing machine-specific and no standing permission grants.
`.claude/settings.local.json` is **gitignored** and holds both, including the
`bypassPermissions` mode, so a "never ask" grant can't travel to a clone.

**Claude Code writes new grants into the tracked file by itself** whenever the
user picks "always allow". It happened four times on 5 and 6 Sep and again on 7
and 11 Sep. Move the grants to `settings.local.json` and to the global
`~/.claude/settings.json`, which the user asked to keep in step, then run
`git checkout -- .claude/settings.json`. **Check `git status` before any push**:
that file is the one that travels to a clone.

**One real cause of git prompting was found on 7 Sep, separate from the
`dev.ps1` mystery below.** Every git rule had been written as `Bash(git -C ...)`,
but git is called through the **PowerShell** tool, and a rule in one tool's
namespace can't match a call made through the other. Worse, the Bash tool on this
machine has no git on its PATH at all, so those rules could never have fired.
`PowerShell(git -C c:/Users/TheSidPai/Prahar ...)` rules are now in both files,
and git stopped prompting immediately. This says nothing about the `dev.ps1`
case; don't treat it as a reason to reopen that.

**Push is denied in both settings files**, so "never push" is enforced by the
harness and not only by behaviour. That matters because the git rule is a
catch-all that would otherwise cover `push`.

## Commands

Everything goes through `tools\dev.ps1`. Don't invoke `flutter` directly: the
script sets `JAVA_HOME` to JDK 17 (the system default is JDK 25, which the
Android Gradle plugin rejects) and puts Flutter on PATH. It's also the only
command shape that is allow-listed, so ad-hoc `flutter` calls prompt every time.

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
tools\dev.ps1 apk          # release APK
tools\dev.ps1 bundle       # release App Bundle, what Play would take
tools\dev.ps1 keystore     # create the upload key (run it yourself; it prompts)
tools\dev.ps1 signer       # print who signed the last build
tools\dev.ps1 install      # build + adb install + launch, one shot
tools\dev.ps1 licenses     # accept Android SDK licences (cosmetic; see below)
tools\dev.ps1 sdkpkg "<pkg;id>"   # install any sdkmanager package, quoting handled
tools\dev.ps1 exempt [off] # toggle the battery-optimisation exemption over adb
tools\dev.ps1 notif        # diagnose notification channel and delivery state
tools\dev.ps1 alarms       # list pending alarms with exact/inexact status
tools\dev.ps1 check        # app process alive, installed version, last log lines
tools\dev.ps1 vendorpkgs   # which autostart screen this device really has
tools\dev.ps1 screenshot   # pull the device screen to build/screen.png (ask first)
tools\dev.ps1 launch       # bring the app to the foreground
tools\dev.ps1 adb <args>   # passthrough for ad-hoc adb
tools\status.ps1           # read-only: toolchain, SDK components, project sanity, devices
tools\make_icon.ps1        # regenerate every launcher icon density
tools\make_logos.ps1       # render alternative logo concepts side by side
tools\make_v2_thickness.ps1     # T2/T3 hand-thickness ladder
tools\make_t3_tick_variants.ps1 # K1..K5 tick-thickness ladder
tools\make_v2_launcher.ps1      # any icon variant at every launcher density
tools\make_nav_options.ps1      # nav icon candidates, 7 per tab, at 96 and 24px
tools\make_mark_anim.ps1        # the mark's animation as 10-frame filmstrips
tools\make_help_options.ps1     # help icon candidates on both bar colours
```

Every `adb` call in `dev.ps1` is bare, with no `-s <serial>`, so **exactly one
device may be connected** or every device task fails with "more than one
device".

**`dev.ps1 vendorpkgs` exists because guessing autostart targets was wrong
twice.** It prints the manufacturer, which known vendor packages are installed,
anything else whose name suggests it manages startup or battery, and whether
each deep-link target actually resolves. Run it before adding a target by hand.
Its last section had a bug worth remembering: the first version grepped
`dumpsys package` for `exported=` near the class name, a flag that isn't printed
there, so every target reported "absent", including one listed two sections
above. It now asks `cmd package resolve-activity --brief -n <component>`, the same
question the app asks. **A probe that reports false negatives is worse than no
probe**, because it sends the next session hunting for something that was never
missing.

**Never pass `-t` to `dev.ps1 adb`.** PowerShell binds parameters by unambiguous
prefix, and `-t` is a prefix of the script's own `-Task`, so
`dev.ps1 adb logcat -d -t 200` sets `Task='200'` and prints the help. It looks
exactly like adb returning nothing, and an hour went into "the log buffer is
empty" before that was spotted. Use `-v brief -s <tag>`. **`-r` fails the same
way** (`dev.ps1 adb install -r <apk>` was rejected on 11 Sep), so never pass
single-letter flags through `adb`; to reinstall, just run `dev.ps1 install`.

### Use these exact command shapes, or the permission prompts come back

This cost the user a night of interruptions and three wrong theories.

**Don't try to fix this with permission patterns. It doesn't work here.**

The decisive test: `dev.ps1 testq` prompted, the user chose *always allow*, and
Claude Code wrote the rule itself, in its own format:

```
"PowerShell(& 'c:\\Users\\TheSidPai\\Prahar\\tools\\dev.ps1' testq)"
```

The very next **byte-identical** run prompted again. A plain command, no pipe, no
redirect, no chaining, a rule the tool authored for itself: still prompted.

Three theories were tried and falsified first, so don't re-derive them: it is
*not* the escaping (doubled or single backslashes), not a missing trailing
wildcard, and not prefix versus exact matching. Two further traps are real but
weren't the cause:

- **A piped command can never be permanently allowed.** Choosing *always allow*
  on `A | B` saves the rule as `A`, which never matches `A | B` again.
- **Redirects aren't offered "always allow" at all**, only a yes or no.

`"defaultMode": "bypassPermissions"` in `settings.local.json` doesn't work either;
a fresh session proved it on 5 Sep. The line stays because it costs nothing, but
it's inert. The user drives Claude through the VS Code extension by default,
which may or may not be why, and that isn't worth another session.

What does work in practice: **explicit per-task entries.** A `dev.ps1 *` wildcard
has never matched on this machine, while listing each task (`dev.ps1 check`,
`dev.ps1 vendorpkgs` and so on) in both settings files does. When a new
`dev.ps1` task is added, add its entry to both files in the same step.

**For long or unattended runs the user launches
`claude --dangerously-skip-permissions`** from a terminal in this directory; the
flag can't be passed from the VS Code sidebar. It's a deliberate, informed choice
for this repository (local, single-developer, fully version-controlled, nothing
secret in the tree), and it comes with binding conditions:

- **No WebFetch, no WebSearch in such a session.** They're the only route by which
  untrusted text could reach the context, and with no prompts there's no
  checkpoint behind them. If something genuinely needs looking up, stop and say
  so.
- **Stay inside `c:\Users\TheSidPai\Prahar`.** The flag is session-wide, not
  scoped to the repository. Only behaviour keeps it confined.
- **Still never push**, and commit after each verified step so the distance back
  to a good state stays short.

Command hygiene that applies either way:

- **One command per call. No pipes, no `;`, no `&&`.** A compound command saves
  its rule as the first part only: every git call was once issued as
  `cd <dir> && git ...`, and "always allow" saved `cd <dir>`. Use
  `git -C c:/Users/TheSidPai/Prahar <subcommand>`.
- **Prefer a new `dev.ps1` task over a novel ad-hoc command** for anything that
  will be run more than once. Every novel command string is a prompt for the
  user; a task is one stable, allow-listed shape.
- **`test` and `testq` take one word at most, or nothing.** `testq spotlight`
  ran without a prompt; `testq fits a small phone at a large font` prompted on
  11 Sep, and the user had to reject it. Otherwise run bare `testq`: the whole
  suite takes under a minute. To make one word select a file's tests, give its
  groups a shared prefix, as `spotlight_test` does.
- **Use the file tools, not shell `cat`, `sed` or `echo`**, for reading and
  editing files.
- **Commit messages:** write the message to `build\commit-msg.txt` with the file
  tools, then run `git commit -F build/commit-msg.txt`. Never pass it inline or
  through a heredoc. The path is fixed and under gitignored `build/`; never the
  scratchpad, whose path dies with the session.
- **Keep messages short: a subject line and three or four lines.** Say what
  changed and the one thing a reader couldn't infer from the diff. Reasoning
  belongs in ARCHITECTURE.md or this file, which are read every session; a commit
  body is read approximately never. The user has asked more than once.
- **Group commits by piece of work, not by file**, and squash away false starts
  rather than shipping "add it, then fix it".
- **Staging:**
  `git add -A -- lib test tools CLAUDE.md ARCHITECTURE.md README.md pubspec.yaml assets android`.
  **`.claude` is deliberately not in that list**, because `settings.json` drifts
  every session. Stage `.git-blame-ignore-revs` explicitly when it changes.
- **Tool scripts:** single quotes, lowercase drive letter, exactly
  `& 'c:\Users\TheSidPai\Prahar\tools\dev.ps1' <task>`.

### Noisy tasks log themselves

`analyze` prints its last 8 lines and `testq` its last 12, and both leave the
whole run in `build\dev.log` to read with an offset. `test` tees the full output
and a copy to the log. This replaced trimming with `| Select-Object -Last N` at
the call site.

Each test is capped at 60 seconds (`--timeout 60s`). **Except `testWidgets`,
which keeps its own 10-minute timeout** that the flag does not shorten: on 12 Sep
a database write inside a widget test's body hung `subject_delete_test` for the
full ten minutes, and the rest of that file failed with "Guarded function
conflict". Write fixtures in `setUp` or inside `tester.runAsync`. Before that, a widget test
awaiting a database write inside fake async hung and turned a one-minute run into
ten before anything failed.

Inside the script use `>`, never `*>&1`: merging a native command's stderr wraps
every line in an ErrorRecord in PowerShell 5.1 and buries the output the task
exists to show.

### Verifying a change

- **`test` alone isn't enough.** Dart only compiles what the tests import, so a
  passing suite leaves most of `lib/ui` unchecked. Always run `analyze` as well.
- **Always run `analyze` after `format`.** The tall style can split a line that
  used to fit, and `curly_braces_in_flow_control_structures` only tolerates a
  braceless `if` on one line. A reformat isn't verified until both have run.
- **A new test isn't finished until it has been seen to fail** against the broken
  code (ARCHITECTURE.md, section 11). Revert the fix, watch it fail, restore.
  **Restore the fix before anything else happens**, even if the run was declined.
- **When a measurement and the user disagree, the measurement is the thing that's
  incomplete.** A test asserting only horizontal centres passed for three rounds
  while the user could see labels sitting 14dp too high.
- **Kotlin and manifest changes are only verified by building.** Tests never touch
  them, and `MethodChannel` types are checked at runtime, not compile time. After
  changing either, `apk`, then `install`, then `check` on a device.
- **`reanchor_test` depends on the time of day.** It plans from the wall clock,
  and near the end of the day today has no blocks left, so it fails with
  `Bad state: No element` in `firstStart`. Seen just before midnight on 11 Sep;
  a rerun after midnight passed. A real failure there names something else.
- **`install` builds first.** Until 4 Sep it installed whatever APK was already in
  `build/`, silently reinstalling the previous build. If a change seems absent on
  the device, check the APK's timestamp before suspecting the code.

### Working unattended

- **Decide and record, don't ask.** Make the reasonable call, state the
  assumption, and leave anything genuinely ambiguous for the morning report.
- **Never push.** Commits accumulate locally.
- **Device work is optional at night.** `install` is fine, but a screenshot at
  3am captures a locked black screen, and `dev.ps1 exempt` doesn't survive a
  reboot.
- **Leave a morning report**: what landed, what was decided and why, what is
  waiting on a human.

### Devices

**Ask before every screenshot.** `dev.ps1 screenshot` captures whatever is on the
device, not just Prahar. On 7 Sep one was taken without asking and captured
another app and a video call. Delete `build/screen.png` afterwards.

**You can't drive the UI from adb on the Xiaomi.** `input tap` fails with
`SecurityException: Injecting input events requires ... INJECT_EVENTS`, gated
behind a developer option the phone doesn't have on. A screenshot shows
whichever screen the user left open. Don't build a tap-based verification flow;
ask the user to open the screen, or write a widget test.

**Two install failures worth recognising:**

- `INSTALL_FAILED_UPDATE_INCOMPATIBLE ... signatures do not match`: the build is
  signed with a different key from the installed app. The only way through is an
  uninstall, which destroys the local database, so export a backup first.
- `INSTALL_FAILED_USER_RESTRICTED: Install canceled by user`: MIUI, not signing.
  It appears on the first install of a *new* package, because MIUI's on-screen
  confirmation cancels itself if not tapped in time. Updates never show it. Retry
  once, and look at the phone.

**A reinstall is not a clean slate.** The manifest doesn't set `allowBackup`,
so on 11 Sep Android's Auto Backup restored the whole database after
`adb uninstall` and `install`, and the app launched as an existing install:
permission prompts at launch, no tour. `pm clear` over adb is refused on MIUI
(`CLEAR_APP_USER_DATA`). To test a first launch, clear data on the phone:
Settings > Apps > Prahar > Storage > Clear data. Whether to keep Auto Backup on
is an open decision, and it means "an uninstall loses everything" is not quite
true.

## Releasing

The route that was actually used for 0.2.0. `gh` is not installed on this
machine, so the release itself is made in the browser.

1. Bump `version` in `pubspec.yaml`, **including the number after `+`**, and
   commit.
2. The user pushes `main`.
3. `dev.ps1 apk`, then `dev.ps1 signer`. **Stop if the signer isn't
   `CN=Siddhant`**: an APK released with any other key can never be updated by a
   correctly signed one.
4. Copy `build\app\outputs\flutter-apk\app-release.apk` to
   `build\prahar-<version>.apk`. `build/` is gitignored.
5. Draft release notes in `build\` for the user to read and paste. They should
   lead with what the app is, then the two settings that decide whether
   reminders work (battery and autostart), and warn that Android's unknown-source
   prompt and Play Protect are normal.
6. The user tags and pushes the tag: `git tag -a v<version> -m "Prahar <version>"`,
   `git push origin v<version>`.
7. The user publishes at `https://github.com/TheSidPai/Prahar/releases/new`,
   choosing the pushed tag and attaching the APK.

Never publish or push on the user's behalf. Obtainium reads GitHub releases
directly, so users can get updates without a store.

## Rules for UI copy

Learned when the user said the app's text read as AI-written.

- **No em-dashes** in any string a user reads, including the README and release
  notes. There were twenty-odd, and they were the loudest tell.
- **Don't explain the reasoning to the reader.** "So the plan reaches you without
  you having to open anything" is design rationale dressed as product copy. A
  person writing a label says what the thing does. Reasoning belongs in
  ARCHITECTURE.md.
- **No implementation vocabulary.** "Exact alarms", "JSON", "backdrop blur",
  "appended" and "cycle" all reached the UI. Name the symptom or the effect:
  "Reminders aren't arriving", not "Re-request permissions"; "Refresh
  reminders", not "Reschedule", which read as "rearrange my timetable".
- **Don't claim behaviour the app doesn't have.** The skip dialog once warned that
  skipping "cannot be undone" beside an Undo button, and a "Not now" button once
  meant never. Copy describing behaviour has to be re-read whenever the behaviour
  changes.
- **Don't pin copy in tests.** Match the concept.

## Standing design decisions

The user's calls, each made by comparing real alternatives. Don't undo them
without reason. How they're implemented is in ARCHITECTURE.md, section 10.

- **Visual choices are made by looking, not by reading names.** Icons were chosen
  from contact sheets at the 24dp they're seen at (`make_nav_options.ps1`), and
  the mark's animation from filmstrips (`make_mark_anim.ps1`). The help button's
  `help_outline_rounded` came from `make_help_options.ps1`: the circle sits with
  the round mark, where a bare question mark went thin at 24dp and a speech
  bubble or lightbulb read as chat or tips. The sheets go to
  gitignored `build/`, so regenerate them to revisit a decision.
- **Inter, and only Inter.** It beat six alternatives in a live picker; the picker
  and the other fonts are gone.
- **All five card styles stay**, user-selectable. Hairline is the default.
- **Glass surface alpha is 0.28**, arrived at in three steps: 0.55 had the tint
  doing the work, 0.42 was better, 0.28 reads as glass.
- **The mark's motion is Unfurl.** `bloom` and `sweep` are archived, not dead; they
  answer questions not yet asked, and `MarkMotionScreen` is kept whole.
- **Icon tuning T3+K4, zoomed 1.182x.** Sun 0.26; ticks 0.0165 thick on a
  0.3545 to 0.4018 ring at alpha 135; hand 0.0355, ending at 78% of the sun's
  radius; pivot 0.0236. The zoom answered "make the sun bigger", meaning the whole
  mark seen closer, not a fatter sun. Every number is the original tuning times
  0.26/0.22, so **rescale all six together**. They live in `tools/make_icon.ps1`
  and are mirrored in `_MarkPainter`; the ladder tools that produced them are
  checked in.
- **Settings screen file names are a leftover.** `SettingsScreen` lives in
  `look_screen.dart` and its subpages in `settings_screen.dart`, from a redesign
  that ran side by side for a day and won. Rename whenever something else touches
  them.

## Toolchain and this machine

- Flutter 3.47.2 and Dart 3.13.2 at `C:\src\flutter`. JDK 17 (Temurin) and Android
  Studio installed. SDK at `%LOCALAPPDATA%\Android\Sdk`: platforms 35 and 36,
  build-tools 36.0.0, platform-tools, cmdline-tools, NDK 28.2.13676358.
- `android/app/build.gradle.kts` enables core library desugaring
  (`desugar_jdk_libs:2.1.4`). Without it the build fails with an opaque `java.time`
  error. Don't remove it.

**The NDK must be installed even though nothing compiles native code.** AGP
resolves one while configuring `:app` regardless. The failure is disguised: it
shells out to `sdkmanager`, the id `ndk;28.2.13676358` splits on the `;`, and the
wrapper crashes with `0xC0000409`, so the build dies with an exit code that never
mentions the NDK. Two workarounds were tried and **both failed identically**:
removing `ndkVersion = flutter.ndkVersion`, and setting
`android.builder.sdkDownload=false`. Install it instead:

```powershell
tools\dev.ps1 sdkpkg "ndk;28.2.13676358"
```

Quote the id at the call site too; an unquoted `;` ends the PowerShell statement.

### sdkmanager quirks

- Package ids contain `;`, which `cmd.exe` treats as an argument separator when
  PowerShell runs a `.bat`. `dev.ps1 androidsdk` builds the command line and lets
  `cmd` parse it; ordinary PowerShell arguments split `platforms;android-36` into
  two unknown packages and install nothing.
- `sdkmanager` delegates to a new CLI that can crash on exit with `0xC0000409`
  *after* installing everything. Never trust its exit code: `androidsdk` and
  `sdkpkg` check the package directories instead, in both directions, because it
  also reports success for packages it skipped.
- **"Android license status unknown" in `flutter doctor` is cosmetic, and
  proven so.** The new CLI answers `--licenses` with "no longer needed", which
  Flutter can't parse. The licence file is real: AGP logged "License for package
  Android SDK Platform 35 accepted" and installed it. Don't chase this warning.
- AGP's own SDK installer works fine. It's specifically `sdkmanager.bat` that's
  broken, which is why `sdkpkg` exists.

### The network is unreliable for large downloads

Three large downloads failed the same way: a slow link and a downloader with no
resume or retry. `Invoke-WebRequest` buffers the whole body in memory on
PowerShell 5.1 and died with `OutOfMemoryException` on the 1.8 GB Flutter SDK;
the Gradle wrapper timed out twice on its own distribution.

**Use `curl.exe` for anything large.** It streams to disk, resumes with `-C -` and
retries. `dev.ps1 gradledist` exists because the Gradle wrapper can't fetch its
own distribution here; run it on a fresh machine or whenever a build fails with
`ConnectException`.

## Version control

`main`, with a public remote at **https://github.com/TheSidPai/Prahar**. Commits
use a noreply address (`<id>+TheSidPai@users.noreply.github.com`), set
repository-local so the global config is untouched. The author's real email must
never appear in a commit.

The commit log is meant to read as a story of decisions: one commit per
meaningful round of work.

**Rewriting unpushed history:** use `git read-tree -u --reset <sha>` followed by
`git commit` for each group, from a reset to `origin/main`. `git merge --squash`
is the wrong tool: a squashed commit has no ancestry link to the range it
replaced, so the next merge takes its base from origin and conflicts. Keep a
safety branch, and confirm `git diff <safety-branch> HEAD` is empty afterwards.
Only ever rewrite what hasn't been pushed.

`.git-blame-ignore-revs` lists formatter-only commits so `git blame` walks past
them. It holds two: the tall-style adoption and a later whitespace settlement.
GitHub reads the file by name; locally it needs
`git config blame.ignoreRevsFile .git-blame-ignore-revs`, which doesn't survive a
clone. Only ever list formatter output; a commit that changed behaviour must stay
visible. **Any history rewrite gives those commits new SHAs**, so repoint the
file afterwards, in a separate commit from the one it names. The 7 Sep squash
left it pointing at a revision that no longer existed.

`android/local.properties` is untracked on purpose (machine-specific SDK paths,
regenerated by any `dev.ps1` task). `.gitattributes` normalises line endings to LF,
without which a Windows checkout rewrites the whole tree.

**Keystores and `key.properties` are gitignored at the root and in `android/`.
Nothing signing-related may ever be committed.**

"A lost keystore means the app can never be updated" is half true, and the half
that matters here is different. Under Play App Signing, Google holds the app
signing key and yours is only an upload key, which Play support can reset. This
app isn't on Play. It ships signed APKs, and Android refuses to install an update
signed by a different key from the installed app. So losing this keystore means
no future release can install over **anyone's** existing copy, and the only way
in is an uninstall that destroys their local data. That's why backing it up is
open work, item 3.
