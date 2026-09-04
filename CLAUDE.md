# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## For a fresh session

If you are just picking this up, read in this order: **Current state** →
**Open feedback (4 Sep)** → **Recent decisions worth carrying forward** →
whatever section your task touches. The whole file is here because every
paragraph was learned the hard way, but the state + feedback + decisions
are what let a new session act, not just understand.

Files you will touch most:

- `lib/planner/planner.dart` — the greedy scheduler
- `lib/planner/calibration.dart` — the per-subject rate learning
- `lib/state/app_state.dart` — the single `ChangeNotifier`
- `lib/data/database.dart` — SQLite DAO + migrations (bump the version!)
- `lib/ui/brand.dart` — `PraharMark`, `PraharLogo` CustomPainters
- `lib/ui/glass.dart` — `GlassSurface`, `SheetBackground`
- `lib/ui/theme.dart` — one place for every visual token
- `tools/dev.ps1` — the only command shape allow-listed for this session
- `tools/make_icon.ps1` — the launcher-icon generator (T3+K4 numbers live here)

## Run Claude from this directory

`cd` into the project root before starting Claude. This file and
`.claude/settings.json` are only loaded when the working directory is the
project. Starting from a parent directory (a home folder, say) silently skips
both, and any permission granted lands in *global* settings instead of the
project's, where it follows you into every unrelated repo.

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
tools\dev.ps1 test         # full suite
tools\dev.ps1 test <name>  # one test by name substring
tools\dev.ps1 analyze
tools\dev.ps1 format
tools\dev.ps1 doctor
tools\dev.ps1 devices      # also diagnoses "no device" causes on MIUI
tools\dev.ps1 run          # onto the connected phone
tools\dev.ps1 apk          # release APK
tools\dev.ps1 install      # apk + adb install + launch, one shot
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
```

**Screenshots capture whatever is on the phone**, not just the Prahar app.
Ask before taking one if the user might have other content open, and delete
the file from `build/` afterwards if you did. `build/screen.png` is
gitignored.

**`tools\dev.ps1 test` is not sufficient on its own.** Dart only compiles what
the tests import, so a passing suite leaves the entire `lib/ui` tree unchecked.
Always run `analyze` as well — that is what actually type-checks the app.

## Current state (verified, 4 Sep 2026)

- 77/77 tests pass; `analyze` reports no issues.
- Release APK builds and installs on device (~53 MB, ~90 s warm).
- Flutter 3.47.2 / Dart 3.13.2 at `C:\src\flutter`. JDK 17 (Temurin) and
  Android Studio installed. SDK at `%LOCALAPPDATA%\Android\Sdk`: platforms
  35+36, build-tools 36.0.0, platform-tools, cmdline-tools, NDK 28.2.13676358.
- **Runs on hardware**: Xiaomi 23127PN0CG, Android 16 / API 36. Reminders
  fire on time, use the alarm-stream sound, reach the lock screen — end to
  end verified. Battery exemption granted; `SCHEDULE_EXACT_ALARM` = allow.
- Two home-screen widgets: `NextBlockWidget` (compact 2x1) and `TodayWidget`
  (wider 4x2 with two blocks + a text-based progress bar).

Features shipped and on the device:

- Planner (greedy, critical-ratio priority), feasibility banner, exam calendar
  (month view under Plan tab), progress screen with per-subject "needs X/day".
- Study window + busy slots (weekly and one-off, multi-day picker).
- Topic units stored with rate — pages/problems/minutes; conversion is honest.
- Undo on logged blocks; skip has a confirm; midnight rollover is handled.
- Search across subjects and topics; long-press duplicate; single link per topic.
- Post-exam archive collapse. Backup/restore to `/Download/Prahar/`.
- Calibration loop: on Progress, per-subject recommendations from finished
  topics. Only fires for >=3 samples and >15% drift.
- **PraharMark / PraharLogo** brand widget (CustomPainter). Three placements:
  first-run Today, top of How Prahar Works, Settings footer.
- Theme toggle (Light / Auto / Dark) as a custom pill slider in Settings.
- Font picker with seven bundled variable-font TTFs (Settings > Font).
- **Materials toggle** (Matte / Glass): frosted-glass surface applied to
  bottom nav, Today header, and modal sheets. Everything else stays matte.
- Notification permissions, exact-alarm request, battery-exemption prompt.

## Recent decisions worth carrying forward

Each was made after real feedback and previewed against alternatives; don't
undo without reason.

- **Font: Inter** won a live-preview picker against six alternatives. Ship
  the app on Inter. Feedback on 4 Sep asked to remove the picker now that
  the choice is made — dropping the six unused fonts saves ~2 MB.
- **Icon: T3+K4 tuning**. Hand stroke 0.030s ending at 78% of sun radius,
  ticks 0.014s at alpha 135, pivot 0.020s. Sun radius currently 0.22 but
  latest feedback asks for it to be **bigger — try 0.26**. Numbers live in
  `tools\make_icon.ps1`; the tuning tools are checked in
  (`make_v2_thickness.ps1`, `make_t3_tick_variants.ps1`,
  `make_v2_launcher.ps1`) so future retunes have the same ladder view.
- **Brand widget**: `PraharMark` is CustomPainter, not a bundled PNG.
  Proportions match the launcher script exactly and are commented as such;
  the two must stay in sync when the mark is retuned.
- **Glass**: applied only to bottom nav, Today header, modal sheets. Contrast
  between matte and glass is what carries the effect; do not spread it to
  cards, list rows or Progress. Feedback asked to **increase transparency**
  slightly (surface alpha from 0.55/0.60 to ~0.40/0.45) and consider two more
  surfaces: feasibility banner, subject-detail header.
- **Calibration model**: uses only completed topics. In-progress work is
  tempting evidence but prorating by minutes cancels arithmetically and
  always recovers the prior rate. This bug hid in the first draft; the test
  suite pins it now — don't "improve" it back into a broken model.
- **Widget layouts must use pre-API-26 XML only.** MIUI's widget host has a
  stripped-down RemoteViews inflater that rejects `paddingHorizontal`,
  `layout_marginVertical`, `letterSpacing`, ProgressBar `min`, and
  `?android:attr/...` style refs — with a generic "Can't load widget" error.
  Use `paddingLeft/Right/Top/Bottom` and legacy variants only; the
  `TodayWidget` layout was rewritten twice before this rule stuck.

## Open feedback (4 Sep) — start here

Ordered by ratio (impact / effort). Full discussion in the last chat's
handoff message; short version:

1. **Colour harmonisation**. Launcher icon is warm (navy → amber); app
   interior is cool indigo with no amber. Two identities. Shift accent
   colours warm — amber for streak, "now" pill, primary CTAs — while
   keeping indigo as structural primary. Biggest visual impact per line
   of code.
2. **Persistent Prahar mark on Today**. Today has the mark only on the
   first-run empty state; after first subject it disappears and the screen
   feels generic. Put a small `PraharLogo(markSize: 24, filled: false)`
   in the Today app bar (or a tight top strip) so the brand is always
   visible.
3. **Sun bigger + remove font picker**. Cheap. Sun radius 0.22 → 0.26 in
   `make_icon.ps1`; pivot up to 0.024 to match. Drop `FontChoice` enum,
   the picker page, the font row in Settings, and the six unused TTFs
   from `assets/fonts/` (keep Inter). Update `pubspec.yaml` fonts block.
4. **Glass tuning**: alphas down to ~0.42/0.45, add glass to the
   feasibility banner and the subject-detail header. Don't add elsewhere.
5. **Pomodoro / Study Timer**. New capability, not a menu of options —
   two modes (Pomodoro 25/5, Deep 50/10), starts from the current block
   tile on Today, runs full-screen (glass), auto-logs `actual_minutes` on
   completion. Feeds calibration honestly.
6. **Editorial Today screen**. The bigger design bet — Today is currently
   a list dressed up. A single hero card for the current block, a smaller
   "and after" row, a compressed strip of what's done, plus the persistent
   header from #2. Fewer surfaces, more hierarchy. This is the answer to
   *"looks standard, very common"*.
7. **Landscape / tablet layout**. Two-pane splits: Subjects (list ↔
   topics), Plan (days ↔ month), Today (current block ↔ rail of next up).
   `LayoutBuilder`, not a whole new codebase. Horizontal-conducive extras:
   a week timetable grid, a subject timeline (Gantt-style).

Recommended order for a fresh session: **1, 2, 3, 4 together** (one round,
mostly cosmetic), then **5** on its own, then **6** as a considered
redesign, then **7** when the phone experience is settled.

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

Current version: **4**. `_v2` records estimate provenance (unit/amount/rate)
and adds `settings`. `_v3` adds `busy_slots`. `_v4` adds `topics.link`.

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
   quality is logged.
2. **Wire `Notifier.scheduleDailyDigest`** — an evening "tomorrow's plan"
   summary. The method exists, nothing calls it. Depends on the digest
   channel id being separate from session ids (already is).
3. **Full resources per topic** — the schema has a full resources table
   supporting multiple entries (book/video/pdf/url/problem-set) with
   progress; we currently expose one `link` string. Building the resource
   sheet unlocks multi-source topics without a schema change.
4. **Sound design** — a proprietary three-note chime instead of the
   system alarm tone. Distinctive without being obnoxious.

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

Keystores and `key.properties` are ignored at both the root and in `android/`.
Nothing signing-related may ever be committed: a leaked keystore is worse than a
lost one, and a lost one means the app can never be updated again.
