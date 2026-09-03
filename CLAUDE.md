# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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
tools\dev.ps1 pubget
tools\dev.ps1 test         # full suite
tools\dev.ps1 test <name>  # one test by name substring
tools\dev.ps1 analyze
tools\dev.ps1 format
tools\dev.ps1 doctor
tools\dev.ps1 devices
tools\dev.ps1 run          # onto the connected phone
tools\dev.ps1 apk          # release APK
tools\status.ps1           # read-only: toolchain, SDK components, project sanity, devices
```

**`tools\dev.ps1 test` is not sufficient on its own.** Dart only compiles what
the tests import, so a passing suite leaves the entire `lib/ui` tree unchecked.
Always run `analyze` as well — that is what actually type-checks the app.

## Current state (verified, 3 Sep 2026)

- 39/39 tests pass; `analyze` reports no issues across all of `lib/` and `test/`.
- Flutter 3.47.2 / Dart 3.13.2 at `C:\src\flutter`.
- JDK 17 (Temurin) and Android Studio installed.
- Android SDK at `%LOCALAPPDATA%\Android\Sdk`: platform 36 (plus 35, which AGP
  pulled in for a plugin), build-tools 36.0.0, platform-tools, cmdline-tools,
  NDK 28.2.13676358. `tools\status.ps1` verifies these directly, because
  `sdkmanager` reports success even when it silently skips a package.
- **`tools\dev.ps1 apk` succeeds** — `build\app\outputs\flutter-apk\app-release.apk`,
  50.1 MB. So the Gradle build, core library desugaring, the manifest merge and
  both notification receivers are all verified as *building*. First build took
  ~7 minutes; later ones are far quicker with a warm daemon.
- **Runs on hardware**: Xiaomi 23127PN0CG, Android 16 / API 36, arm64.
  Installed, launched, no crash, `POST_NOTIFICATIONS` granted,
  `SCHEDULE_EXACT_ALARM` appop = allow.
- **The scheduling pipeline is verified on-device.** With one subject and a
  200-page topic, `tools\dev.ps1 alarms` showed 16 pending alarms, all exact
  (`window=0`, `exactAllowReason=permission`), and they matched the planner's
  intent precisely: 600 minutes of work (200 pages x 3 min) spread 120/120/240/120
  across Thu-Sun by weekday/weekend capacity, today starting at the current
  time rather than 06:00, 50-minute blocks an hour apart, then reviews at +1,
  +3 and +7 days. The +21 review was correctly absent, being outside the
  14-day window.
- **Still unproven: delivery.** An alarm being registered is not a notification
  appearing. Whether Xiaomi's HyperOS lets the process survive to handle it —
  once the standby bucket drops below 10 (ACTIVE) — is the open question, and
  the usual failure mode for reminder apps on this vendor. Autostart and
  battery "No restrictions" are likely required.

Next step: confirm a notification actually appears when a block falls due, then
leave the phone idle overnight and check the next morning's 06:00 alarm fires.
`tools\dev.ps1 check` shows liveness and logs; `tools\dev.ps1 alarms` shows what
the OS still holds.

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

Two Android facts dominate this code:

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

## Roadmap

Ordered by value, not difficulty:

1. Run on a real device and verify alarms actually fire at the right minute.
2. Apply per-subject calibration from `session_log` back into topic estimates.
3. Resource tracking in the UI (the `resources` table and estimator support it;
   no screen reads it yet).
4. FSRS instead of the fixed `[1, 3, 7, 21]` review ladder, once recall quality
   is logged.
5. Wire `Notifier.scheduleDailyDigest` — the method exists, nothing calls it.
6. Export/import for backup — still no server.

Deliberately *not* on the roadmap: accounts, sync, SMS, WhatsApp. WhatsApp needs
Meta Business verification and per-conversation fees; if ever added, it goes
behind a `NotificationChannel` interface so the planner never learns about it.

## Version control

Git repository on `main`, no remote. The initial commit (`c4006f2`) covers the
whole project at the point everything was verified on hardware.

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
