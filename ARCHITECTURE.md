# Architecture

How Prahar is built: what the parts are, how data moves between them, and the
rules that keep it working. Most rules here exist because breaking them caused
a real bug, and where that's true the bug is described, because the reason is
what stops someone "simplifying" the rule away.

This file describes the system. [CLAUDE.md](CLAUDE.md) describes how to work in
this repository: the build commands, the machine's quirks, the current state
and the queue of open work. When behaviour changes, update this file in the
same commit.

## Contents

1. [Principles](#1-principles)
2. [System overview](#2-system-overview)
3. [The update cycle](#3-the-update-cycle)
4. [Data model and storage](#4-data-model-and-storage)
5. [The planner](#5-the-planner)
6. [Effort estimation and calibration](#6-effort-estimation-and-calibration)
7. [Today, the clock and the running block](#7-today-the-clock-and-the-running-block)
8. [Notifications and background delivery](#8-notifications-and-background-delivery)
9. [Android platform layer](#9-android-platform-layer)
10. [UI architecture](#10-ui-architecture)
11. [Testing](#11-testing)
12. [Known limitations](#12-known-limitations)

---

## 1. Principles

These are commitments, not preferences. Everything else follows from them.

**Local-first.** No backend, no account, no network client. The release build
has no `INTERNET` permission. All state is one SQLite file plus alarms handed to
the OS. Adding sync would be an architectural change, not a feature.

**The schedule is derived, never stored.** The database holds what the student
entered and what they did. The plan is a pure function of that plus the current
time, regenerated from scratch on every change. Persisting it would create a
second source of truth that drifts the moment a topic is edited or a day is
missed.

**Pure core.** `lib/domain/` and `lib/planner/` import no Flutter, touch no
database and do no I/O. This is the most important constraint in the codebase:
it's what lets the planner be tested exhaustively without a device. If planner
code seems to need a `BuildContext` or a database handle, the logic belongs in
`state/app_state.dart`.

**Tell the truth about feasibility.** The planner always returns an assessment
of whether the work fits. A planner that silently produces an impossible
schedule is worse than none, because the student finds out the week of the
exam.

**Fail soft at the platform edge, never silently in the plan.** A check that
couldn't complete (exact alarms, battery state, the notification plugin being
absent in a test) must not crash an edit or raise a false warning. But when the
plan itself doesn't work, the app says so plainly.

**Simple over optimal.** The planner is greedy. It runs in microseconds, can
explain every decision, and stays stable when a day is missed.

---

## 2. System overview

```
 ui/              screens, widgets, theme, layout
  |
  v
 state/           AppState: the single ChangeNotifier
  |
  +--> data/            SQLite, backup, file exchange
  +--> planner/  --->   domain/   (pure: models, schedule, prefs, timer)
  +--> notifications/   local alarms, digests, widget updates
                          |
                          v
 android/ (Kotlin)  MethodChannels, home-screen widgets, manifest
```

Dependencies point inward only. `domain/` depends on nothing in the app.

| Folder | Responsibility | Key files |
|---|---|---|
| `lib/domain/` | Pure types and arithmetic | `models.dart` (Subject, Topic, Resource), `schedule.dart` (Availability, BusySlot, StudySession, LoggedSession, Plan, Feasibility), `preferences.dart`, `study_timer.dart`, `today_focus.dart`, `background_limits.dart`, `format.dart` |
| `lib/planner/` | Scheduling and estimation | `planner.dart`, `estimator.dart`, `calibration.dart` |
| `lib/data/` | Persistence | `database.dart`, `backup.dart`, `file_exchange.dart` |
| `lib/state/` | The app's single source of truth | `app_state.dart` |
| `lib/notifications/` | Everything handed to the OS | `notifier.dart`, `widget_bridge.dart` |
| `lib/ui/` | Screens and the design system | see [section 10](#10-ui-architecture) |
| `android/app/src/main/kotlin/` | Platform code | `MainActivity.kt`, `WidgetBridge.kt`, `NextBlockWidget.kt`, `TodayWidget.kt` |
| `tools/` | Build, device diagnostics, icon generation | `dev.ps1`, `make_icon.ps1` |
| `test/` | 306 tests across 24 files | see [section 11](#11-testing) |

### Startup

`lib/main.dart`, in order:

1. Open the database (running any pending migrations).
2. `Notifier.init()`: resolve the timezone, initialise the notification plugin.
3. `AppState.load()`: read subjects, topics, availability, preferences, the
   streak, today's log, the running block and the device's autostart gate,
   then build the plan.
4. Ask for notification permissions, before the first frame, so the alarm sync
   that follows actually lands, unless the first-run tour is running. The tour
   asks at its reminders stop instead (section 10).
5. `refreshAlarms()`, then `runApp` with `AppState` provided at the root.

---

## 3. The update cycle

Every mutation in `AppState` has the same shape:

```
write to SQLite  ->  _rebuild()  ->  notifyListeners()
```

`_rebuild()` does, in order:

1. **Capacity for today.** Today's available minutes, minus minutes already
   logged as done or skipped. The planner is stateless, so time already spent
   has to be expressed as reduced capacity.
2. **The plan.** `Planner.generate(...)` with `todayStartMinute` set to the
   current clock time, so a replan at 3pm never offers a 6am block.
3. **Calibration suggestions**, recomputed from finished topics
   ([section 6](#6-effort-estimation-and-calibration)).
4. **Alarms and digests**, unless the caller opted out: check exact-alarm and
   battery state, then `_syncReminders` (the block alarms, or cancelling them
   if reminders are switched off) and `_syncDigests`. Wrapped so a failure
   to write alarms still leaves a correct plan on screen.
5. **Home-screen widgets**, updated with the next blocks and today's progress.

Because the planner runs in microseconds, replanning on every keystroke-level
edit costs nothing.

Other triggers:

| Event | What runs |
|---|---|
| App resumed | `refreshIfDayChanged` (midnight rollover), `refreshAlarms`, `reanchorIfIdle` |
| Today's one-minute tick | repaint, `reanchorIfIdle` |
| Focus timer started | `beginSession` |
| Block logged done or skipped | log write, `endSession` if it was running, `_rebuild` |

**Derived values live on `AppState`, never in `build()`.** The Progress screen
once passed `state.calibrationSuggestions()` to a `FutureBuilder` from inside
`build`. Every `notifyListeners` rebuilds Progress, so that was a database read
per edit, per tap and per minute tick, and each rebuild handed the builder a new
future, so the card blinked out and back on unrelated changes. Anything computed
from state is computed in `_rebuild` and read synchronously.

---

## 4. Data model and storage

### Domain types

**`Subject`**: name, colour, weight (1 to 5), an optional exam date and an
optional exam start time.

The exam time is a **separate nullable column, not a timestamp**. The date stays
a plain date, so every date comparison in the app (calendar grouping, the
archive check, the planner's day loop) keeps working on dates, and "I know the
day but not the time" stays expressible. Null means the whole exam day counts
as preparation, which is what every subject did before the column existed.

Two methods on `Subject` are the only places allowed to answer their questions:

- **`prepDaysFrom(day)`**: whole days until the exam, plus the share of the
  study window that comes before the exam starts. The planner's priority score
  and both "needs X a day" figures divide by this, so it's one method. Three
  copies would disagree and tell the student different stories about the same
  exam.
- **`examDemand`**: the minutes per day still needed, or `impossible`. Dividing
  by a fraction of a day as an exam approaches makes the rate explode: 4 hours
  of work against a 9am exam once reported "needs 56h a day". The ceiling is the
  study *window*, so the UI says "won't fit before the exam" instead of quoting
  a number no day can hold.

**`Topic`**: belongs to a subject. Carries `estimatedMinutes`,
`completedMinutes`, difficulty (1 to 5), prerequisites, status, the date it was
first completed, and an optional link.

- `remainingMinutes = estimatedMinutes - completedMinutes`, clamped at zero.
- `isDone` is true when status is done *or* nothing remains.
- The estimate's **provenance** is stored: `estimateUnit` (minutes, pages,
  problems), `estimateAmount` (what the student typed) and `estimateRate`
  (minutes per unit at the time). Recorded rather than re-derived, so changing a
  default rate later can't silently rewrite an existing estimate.

**`Resource`**: books, videos, PDFs, URLs and problem sets with page ranges,
durations and progress. Fully modelled and supported by the estimator, but the
UI currently exposes only one link per topic.

**`Availability`** and **`BusySlot`**: minutes available per weekday, per-date
overrides, and busy intervals (weekly or one-off) inside the study window.
`freeIntervals(day)` returns the window minus busy slots.

**`StudySession`**: one planned block. Never persisted. Its id is
**content-addressed**, `kind|date|startMinute|topicId`, never a counter. A
counter pointed at a different block after every replan, so anything that
remembered "session 3 is done" silently referred to the wrong one.

**`LoggedSession`**: what actually happened to a block: planned minutes, actual
minutes, done or skipped. The audit trail.

**`Plan`**: the sessions plus a `Feasibility`.

Anything the student *did* must be recorded on the `Topic` or in the log. A
session object is disposable and gone on the next replan.

### Storage

SQLite through `sqflite`, with `PRAGMA foreign_keys = ON`. Schema version **5**.

| Table | Holds | Notes |
|---|---|---|
| `subjects` | subjects | `exam_minute` added in v5 |
| `topics` | topics | FK to subjects, `ON DELETE CASCADE`. Estimate provenance in v2, `link` in v4 |
| `resources` | per-topic resources | FK to topics, cascade |
| `availability` | weekday to minutes | |
| `availability_overrides` | date to minutes | |
| `busy_slots` | busy intervals | added in v3 |
| `session_log` | the audit trail | **no foreign key, on purpose** |
| `settings` | key/value strings | added in v2 |

**`settings`** holds preferences (`day_start`, `day_end`, `block_minutes`,
`break_minutes`, `theme`, `material`, `card_style`, `timer_mode`, `digest`,
`digest_minute`, `reminders`), the autostart notice state (`autostart_dismissed`,
`autostart_snoozed_until`, `autostart_snooze_count`) and `running_session`.
`Prefs.fromMap` is tolerant: a missing or corrupt value falls back to a working
default and never stops the app starting.

**`session_log` has no foreign key** because it's history and must outlive the
topic it describes. The consequence is that nothing cascades into it, so
`AppState.deleteSubject` clears a subject's log explicitly. Before it did, a
deleted subject kept appearing in today's list and counting towards the streak.

#### Never `ConflictAlgorithm.replace`

`INSERT OR REPLACE` doesn't update in place: it deletes the conflicting row and
inserts a new one. With foreign keys on, that hidden delete **cascades**. Saving
an edited subject destroyed every topic under it, and saving a topic destroyed
its resources. The write reported success and the schedule simply emptied,
which looked like a planner bug.

Every write goes through `_upsert`, which runs `UPDATE` and then `INSERT` only if
nothing was updated. `test/database_test.dart` pins this, and those tests were
confirmed to fail against the old code.

#### Migrations

Once a schema version has run on a real device, editing that version's code
does nothing: `openDatabase` believes the migration already ran. A table once
slipped into `_v2` after v2 had shipped was permanently missing on every device
already at v2, and every write to it failed silently.

So:

- Every schema change gets a **new version** and a new `_vN` function.
- `_upgrade` chains them: `if (from < N) await _vN(db)`.
- Each `_vN` is **idempotent** (`CREATE TABLE IF NOT EXISTS`, `ADD COLUMN`
  guarded by `PRAGMA table_info`), so a redundant run can't break an install.
- `onCreate` runs the base schema and then every `_vN`, so fresh installs and
  upgraded ones end up identical.
- Migrations are additive and backfill; they never rewrite existing data.

State that is "about right now" rather than history (the running block, the
autostart snooze) goes in `settings` and needs no migration.

### Backup and restore

`lib/data/backup.dart` writes everything the app persists, including
`session_log`, as one JSON document with a `format` version (currently 1). The
log was added later without changing the format, because the change is
additive. It matters: progress always survived on the topic, but the streak and
calibration history are what a student earns, and they live in the log.

**Restore is an exact replacement, not a merge.** `clearAll` empties every
user-owned table first, because a merge with colliding ids would produce data
the user never exported.

The file itself moves through the **Storage Access Framework**
(`file_exchange.dart`, the `prahar/files` channel). The user picks where to save
and which file to restore, which needs no storage permission: choosing the
document is the grant. A fixed path under `/sdcard/Download` would be blocked by
scoped storage from Android 11 and isn't the app's to choose anyway.
`FileExchange.available` is false on desktop and in tests, where the caller
writes a path directly instead.

---

## 5. The planner

`lib/planner/planner.dart`. A greedy, constructive, day-by-day scheduler.

### Why greedy

- **It runs in microseconds**, so the plan can be rebuilt on every change.
- **It's explainable.** Every block landed where it did for a reason that can
  be stated.
- **It's stable.** Miss a session and that work shifts forward. An optimiser
  would happily reshuffle the whole month.

Reach for a solver such as OR-Tools CP-SAT only if these schedules turn out to
be genuinely bad. Don't add one to fix what is really a priority-weighting
problem.

### Interface

```dart
Plan generate({
  required List<Subject> subjects,
  required List<Topic> topics,
  required Availability availability,
  required DateTime today,
  int? todayStartMinute,   // earliest start on the first day only
})
```

### Configuration

`PlannerConfig`, with the window and block lengths overridden from the
student's preferences:

| Setting | Default | Meaning |
|---|---|---|
| `dayStartMinute` / `dayEndMinute` | 06:00 / 22:00 | the study window; a block must *end* by the end |
| `maxSessionMinutes` | 50 | longest block |
| `minSessionMinutes` | 20 | shortest block worth placing |
| `breakMinutes` | 10 | gap after every block |
| `maxConsecutiveSameSubject` | 2 | interleaving cap |
| `reviewOffsetDays` | 1, 3, 7, 21 | review ladder after first completion |
| `reviewMinutes` | 15 | length of a review |
| `reviewShareOfDay` | 0.4 | ceiling on reviews per day |
| `urgencyOverrideRatio` | 3.0 | how much more pressed a subject must be to break the cap |
| `horizonDays` | 180 | how far to plan when no exam bounds the work |

### Setup

1. **Work map**: remaining minutes per topic, **excluding** finished topics and
   any topic whose exam has already passed. A finished exam isn't a shortfall.
   That work used to reach the feasibility check as "unscheduled" and declare
   the plan impossible, permanently, over a subject nothing could be done
   about.
2. **Satisfied prerequisites**: every topic already done.
3. **Remaining work per subject**, kept in step with the work map as blocks are
   placed.
4. **Horizon**: the latest exam date, or 180 days out if any subject has no
   exam date.
5. **Reviews already owed** for topics finished before this plan. Rungs that
   fell due before today are **dropped, not piled onto day one**: someone coming
   back to a topic finished last month shouldn't get four overdue reviews in one
   sitting.

### The day loop

For each day from today to the horizon:

**Capacity and position are separate limits.** Free intervals (the window minus
busy slots) say *where* a block may go. The minute budget says *how much* the
student intends to study, which is usually far less than the time they're
technically free. On the first day, nothing starts before `todayStartMinute`.

A cursor walks through the free intervals. When a block won't fit in the
current interval, it moves to the next one.

**Pass 1: reviews.** Reviews due today go first, oldest first, because a review
three days late is barely a review. Each is 15 minutes. They're capped at 40% of
the day's capacity: four rungs per finished topic accumulate fast, and without a
ceiling a student with a backlog would spend every session revising. A review
that would run past its subject's exam start is skipped but kept in the queue,
in case the topic also belongs to a later exam.

**Pass 2: new material.** Until capacity drops below the minimum block:

1. Pick the next topic with `_pickNext` (below).
2. Move the cursor to where a minimum-length block fits.
3. Block length is the smallest of: 50 minutes, the topic's remaining work, the
   day's remaining capacity, the room left in this interval, and the time left
   before the subject's exam starts (on its exam day, when the time is known).
4. **Avoid slivers.** If this block would leave less than 20 minutes of the
   topic, shrink it so the remainder is at least 20, or take the whole topic if
   it fits. Better than emitting a 5-minute fragment tomorrow.
5. Place the block, add a 10-minute break, and reduce the subject's remaining
   work. If the topic is now finished, it satisfies its dependents and queues
   its review ladder.

Dates are stepped with `DateTime(y, m, d + 1)`, **never** `add(Duration(days: 1))`.
Adding 24 hours lands at 23:00 the previous day across a daylight-saving change,
so two iterations would share a date and double-book it. The same rule applies
in `Availability.totalBetween` and the review ladder.

### The priority score

The whole behaviour rests on `_priority`:

```
score = (subject's remaining minutes / prep days until its exam)
        x weight
        x (1 + (difficulty - 3) x 0.1)
```

The first term is the **critical ratio**, or least-slack heuristic: how many
minutes per day this subject demands from here. Weight is the student's stated
importance, and difficulty is a gentle nudge of 10% per step.

An earlier version scored on `1 / daysToExam` alone, which is wrong in a way
that matters:

| Subject | Exam in | Work left | Demands |
|---|---|---|---|
| A | 60 days | 100 hours | 100 min/day |
| B | 30 days | 2 hours | 4 min/day |

Deadline-only scoring ranks B as twice as urgent as A. The ratio ranks A 25
times more urgent, which is the honest answer, and getting it wrong means
finding out about A the week of the exam. `test/planner_test.dart`,
`weighs workload, not just deadline distance`, holds this in place.

Two details matter more than they look:

- It uses **subject-level** remaining work, and that figure drops as blocks are
  placed, so a subject's pressure falls during the day. That produces natural
  interleaving before the cap is involved.
- Prep days are floored at 0.1, so the ratio stays finite on the morning of an
  exam, when that subject genuinely is the most pressed thing available.

### Choosing the next topic

`_pickNext` considers every topic with work remaining and skips any that:

- belongs to a subject whose exam has started today,
- is past its subject's exam date, or wouldn't finish before today's exam start,
- has an unfinished prerequisite. A prerequisite id that doesn't exist is
  treated as met, so a typo can't deadlock the plan.

It tracks two candidates: the best topic that **respects** the interleaving cap,
and the best topic **ignoring** it.

- If every eligible topic is capped out, the uncapped best is used, so the day
  doesn't stall with hours left.
- If the uncapped best scores more than **3 times** the capped best, it wins
  anyway. An exam in two days against one in three months shouldn't surrender a
  third of every day to interleaving.

**Exam day.** When a subject's exam time is known, work for it is only placed
before the exam starts. If the cursor has passed that point, the subject is
retired **for the rest of that day only**, so the afternoon stays available to
everything else.

### Feasibility

After the loop, any work left in the map is a shortfall. `_assess` reports:

- per subject, the unscheduled time and the exam it won't fit before,
- the overall shortfall and roughly how many minutes a day would close it,
- if *every* leftover topic is waiting on another leftover topic, a warning to
  check whether two topics depend on each other.

The UI shows this through `FeasibilityBanner`, condensed when the plan fits and
in full when it doesn't. It is never hidden behind a tap.

### Known weaknesses

- **No lookahead.** Filling today with subject A can create a crunch for B on
  Thursday. The planner only reacts as B's ratio climbs. In practice the ratio
  catches this early, but the plan isn't optimal and doesn't claim to be.
- **The constants were tuned by judgement**, not measured: 3.0, 0.4, the
  interleaving cap.
- **Difficulty barely matters.** Ten percent per step against a ratio that can
  vary 25 to 1 is close to cosmetic.
- **The review ladder is fixed** and ignores how well anything was remembered.

---

## 6. Effort estimation and calibration

### Estimation

Students can't estimate minutes but can count pages. `EffortEstimator` converts
countable material into minutes, and the topic sheet defaults to pages.

| Unit | Default rate |
|---|---|
| page | 3 minutes |
| problem | 6 minutes |
| video | runtime x 1.3 (pausing, rewinding, notes) |

Converting between units preserves the underlying effort. That arithmetic lives
in the estimator rather than in the topic sheet: when it lived in the widget it
broke the purity rule and inflated estimates threefold when the unit was
switched.

### Calibration

`Calibrator.analyse` turns logged work into per-subject rate recommendations:

- Topics are grouped by **subject and unit**. Per-topic recommendations would
  starve for evidence and bury the student in prompts.
- **Only finished topics are samples.** One sample per finished topic: the
  amount the student entered, against the total minutes logged for it.
  In-progress topics are excluded because prorating their minutes cancels out
  arithmetically and always returns the prior rate. That bug existed in the
  first draft and is pinned by tests.
- Samples are blended with the prior using **shrinkage**: the observed rate gets
  weight `n / (n + 5)`, so a few sessions nudge the estimate and twenty nearly
  replace it. One interrupted session can't wreck every future estimate.
- A recommendation is only made with **at least 3 samples** and a change of at
  least **15%**. Smaller corrections aren't worth interrupting anyone for.

The results live on `AppState.calibration`. Progress shows them as "Your actual
pace" cards, and applying one rewrites the rate and estimated minutes on every
unfinished topic in the group, keeping minutes already completed.

### Known gap: what logged minutes mean

Marking a block done asks how long it took, and `markDone` adds that number to
the topic's `completedMinutes`. So the app reads it as **progress**: log 80
minutes for a 40-minute block and the topic is 80 minutes closer to done.

The calibrator reads the same number as **effort**: more minutes for the same
entered amount means a slower rate.

Those can't both be right, and the progress reading fails in the worst
direction. Take 40 pages at 5 minutes per page, 200 minutes in all. A student
who spends 80 minutes getting through 8 pages is recorded as 80 of 200 done,
with 24 pages left, when 32 pages are left. The topic is marked done after 20
pages. A struggling student is told they have less work remaining than they do.

It also blunts calibration: a topic finished purely by accumulating minutes has
total minutes roughly equal to its estimate, so it returns the prior rate.

The direction is to record **units covered** separately from minutes spent, so
progress advances by pages and each session becomes its own rate sample. The
calibrator's own comment notes that in-progress sessions can't be used "without
asking" how much was covered. This naturally ships together with recall-grade
logging, in the same dialog and schema change.

---

## 7. Today, the clock and the running block

### What Today is about

`domain/today_focus.dart` decides which single block Today leads with: one
running **now**, the **next** one, **all done**, or **nothing planned**. It's
pure because "what am I meant to be doing right now" has more edge cases than it
looks (a block under way, a gap, a finished day, an empty day, an app left open
for hours), and discovering them inside a `build` method means discovering them
one bug report at a time.

### Keeping the day current

A plan is generated from the moment it's made. Without intervention it goes
stale: opened at 11:16, a block reads 11:16; left open, the same block still
reads 11:35 at 11:46.

Re-anchoring on every tick would be worse. The block would restart at "now"
forever, never elapse, and its countdown would never move.

So `AppState.reanchorIfIdle` rebuilds the plan only when:

- **nothing is running**, and
- an unfinished block today started at least **2 minutes** in the past
  (`reanchorAfterMinutes`).

A block that has been started keeps its original start time, because that's what
makes "29m left" mean something. Tests pin both halves, including that
re-anchoring twice in a row doesn't keep shifting the day.

Knowing which block is running needed new state. `session_log` only learns about
a block once it's over, and sessions are regenerated on every replan, so neither
can hold it. `runningSessionId` lives on `AppState` and is persisted in
`settings`, because the process is killed mid-block routinely on these phones.
The focus timer sets it; logging the block done or skipped clears it.

It runs on Today's one-minute tick and on resume, since the tick doesn't run
while the app is paused.

### The focus timer

`domain/study_timer.dart` computes the phase, seconds left and focused time from
a **start instant, accumulated pause and the current time**. It never counts
ticks. Android freezes the process when the screen turns off, which is exactly
when a focus timer runs, so a tick counter would lose every minute the phone
spent asleep. `Timer.periodic` in the screen only repaints, and
`test/study_timer_test.dart` jumps the clock the way a sleeping phone does.

The end of each phase is also handed to the OS as an alarm (notification id 3),
so the boundary still sounds with the process frozen. The screen stays on while
the timer runs, via `wakelock_plus`, which sets `FLAG_KEEP_SCREEN_ON` on the
window and adds no permission. Modes are 25/5 and 50/10, and the last one used
is remembered.

---

## 8. Notifications and background delivery

All reminders are **local alarms** through `flutter_local_notifications`. No
push service, no server. The whole plan is known in advance, so reminders work
offline and after a force stop.

### Channels

| Channel | Name | Delivery |
|---|---|---|
| `prahar_sessions_v3` | Study sessions | exact where allowed, alarm-stream sound |
| `prahar_digest` | Evening summary | inexact |

The session channel names `content://settings/system/alarm_alert` as its sound
explicitly. A channel otherwise inherits the default notification sound, which
**may not exist**: on the development phone it's null, and reminders reached the
lock screen in complete silence. Setting the audio usage to alarm alone didn't
fix it, because that changes the stream, not the sound.

A channel's id is permanent once created, so changing a channel's behaviour
means a new id. Older ids are listed as retired.

### Notification ids are partitioned

| Id | Used for |
|---|---|
| 1 | the original repeating digest (retired, still cancelled) |
| 2 | test reminder |
| 3 | focus-timer phase end |
| 100 to 106 | one evening summary per night, a week ahead |
| 1000 and up | study blocks, derived from the block's day and start minute |

Each sync cancels **only its own range**. An earlier `syncFromPlan` called
`cancelAll()`, and since a replan happens on every edit it silently destroyed
the digest and any pending test reminder every time. That class of bug doesn't
show in testing, because the alarm registers correctly and simply never survives
to fire.

### Session reminders

`syncFromPlan` cancels every id from 1000 up and schedules the upcoming blocks
in the next **14 days**, at most **56** alarms, because the exact-alarm budget is
finite. It cancels and reschedules rather than diffing: a reminder for a block
that no longer exists costs more trust than the milliseconds saved. It runs on
every replan and on resume.

**Reminders can be switched off.** Settings > Notifications leads with a Study
reminders switch (`Prefs.remindersEnabled`, stored as `reminders`, on by default
and on when absent). Off cancels the session range and schedules nothing new.
`AppState._syncReminders` is the only place that decides, so a replan, a resume
and the Settings page can't disagree; a second, unguarded call to `syncFromPlan`
anywhere would be how "off" quietly turns back on after the next edit, and
`test/reminders_toggle_test.dart` watches for exactly that. The evening summary,
the focus timer's alarm and a test reminder are separate and keep working.

A switch flipped "for now" and forgotten looks exactly like the app being
broken, so Today shows `RemindersOffNotice`, a quiet line with a one-tap
**Turn on**, for as long as reminders are off. "Refresh reminders" is hidden
meanwhile, since it would set nothing and report zero.

### The evening summary

A **rolling window, not a repeating alarm.** A repeat carries the same text
forever, correct the first night and wrong every night after. `syncDigests`
writes one notification per evening for the next 7, each describing the
following day, refreshed on every replan and resume. If the app goes unopened
for a week they run out, which is the right failure: silence beats a wrong
summary.

### Timezone

`Notifier._initTimeZone` tries the device's zone name as an IANA location, which
occasionally works, and otherwise falls back to **Asia/Kolkata**. If the device
offset isn't +05:30 it logs that reminders are assuming IST. India has no
daylight saving, so this is exact for every current user. If the app ever ships
outside India, the fix is `flutter_timezone` for the real zone name, and nothing
else changes.

### Three gates between an alarm and a notification

An alarm can be registered correctly and still never produce a notification.
Three separate things decide that, and the app has to handle each one.

**1. Exact alarm permission.** Android 12+ requires `SCHEDULE_EXACT_ALARM`,
granted on its own settings screen. Without it reminders are batched into idle
windows and a 6pm reminder can arrive at 7:20. `canScheduleExact()` drives a
visible warning on Today. `USE_EXACT_ALARM` is deliberately not used: it's
granted automatically, but Play restricts it to alarm and calendar apps.

**2. Battery optimisation.** Without an exemption, stock Android freezes the
process, and a correctly registered alarm wakes nothing: the reminder appears
when the student next opens the app, which is exactly when it's useless.
Verified on hardware, with identical code: exemption off, nothing arrived;
exemption on, it arrived to the minute. `BatteryWarning` is the loudest card in
the app for this reason. The request is two hand-written Kotlin methods rather
than `permission_handler`, which requires an Android SDK version that breaks the
Gradle build here.

**3. The vendor autostart list.** Xiaomi, Oppo, Realme, OnePlus, Vivo, Huawei,
Honor, Samsung and the Transsion brands each keep a separate list of apps allowed
to start on their own, and a new install isn't on it. The battery exemption says
nothing to that list. The alarm stays registered and visible in
`dumpsys alarm`, and nothing ever wakes to post it. This is the most likely
reason a real student would say reminders stopped.

### Handling the autostart gate

**No API reports whether an app is on any of these lists.** The app can find out
that a phone *has* the gate, never whether it's currently blocked. That
asymmetry shapes the whole design: the notice is advice, not a warning that
claims to have checked.

**What resolves decides; the brand only chooses the words.**
`BackgroundGate.resolve(manufacturer, hasScreen)` returns a gate only if a vendor
autostart screen actually resolves on the device. The manufacturer picks the
wording ("Autostart on Xiaomi"), and an unrecognised maker with a real screen
gets generic wording and a working link. This was once the other way round,
decided by brand alone, and it was wrong twice: an unknown brand with a gate got
no notice, and a known brand without the screen got a button that opened nothing
useful. Google, Motorola, Nothing and Sony run stock Android, nothing resolves,
and no notice appears, which is correct.

**Resolution, on the Kotlin side.** `MainActivity` holds an ordered list of
package and activity pairs. A target counts only if
`resolveActivityInfo(packageManager, 0)` finds it **and** it's exported. No
flags, because `MATCH_DEFAULT_ONLY` drops activities without `CATEGORY_DEFAULT`,
which a vendor's internal settings page has no reason to declare. Exported,
because a non-exported activity throws on launch.

**The `<queries>` block in the manifest is load-bearing.** From Android 11 an app
can't see another package's activities unless it declares that package, and
resolution returns null rather than failing. Without those entries every link
would quietly degrade on exactly the devices the feature is for.

**Opening reports what happened.** `openAutoStartSettings` returns `vendor`,
`fallback` or `none`. Landing on the generic App info page isn't what the button
promised, so the app says so. It once returned plain `true` for the fallback,
which is why a OnePlus user would land on the wrong screen with no explanation.

Targets confirmed on hardware:

| Maker | Target | Status |
|---|---|---|
| Xiaomi, Redmi, Poco | `com.miui.securitycenter/com.miui.permcenter.autostart.AutoStartManagementActivity` | verified |
| OnePlus, Oppo, Realme | `com.oplus.battery/com.oplus.startupapp.view.StartupAppListActivity` | verified on OxygenOS 16 |
| Samsung, Vivo, Huawei, Honor, others | listed in `MainActivity.autoStartTargets` | not verified on a device |

The OnePlus entry is worth remembering. `com.oplus.safecenter` is installed on
OxygenOS 16 but contains no such activity; the list moved into the battery app.
The package being present is what made the wrong guess look plausible.
`tools\dev.ps1 vendorpkgs` asks a connected device which packages and activities
it actually has. Use it before adding a target.

**The notice itself** (`AutostartNotice` on Today):

- Waits until the battery exemption is granted. Two cards competing for the same
  attention means the more important one loses.
- **"Show me"** opens the vendor screen and retires the notice. The app can't
  verify the result, so asking again would be nagging.
- **"Not now" snoozes**: 1 day, then 3, then 7, then it retires. At most four
  showings over eleven days. A button that says "later" has to come back, and
  because the app can't tell whether autostart was ever turned on, something has
  to bound how often it asks.
- Settings > Notifications keeps a **permanent row** for the same link wherever
  the gate exists. A one-time card is the right shape for a prompt and the wrong
  shape for the only route to a setting.

---

## 9. Android platform layer

### MethodChannels (`MainActivity.kt`)

| Channel | Methods | Purpose |
|---|---|---|
| `prahar/battery` | `isIgnoringBatteryOptimizations`, `requestIgnoreBatteryOptimizations`, `backgroundVendor`, `hasAutoStartSettings`, `openAutoStartSettings` | battery exemption and the autostart gate |
| `prahar/widget` | `update` | push today's blocks to the home-screen widgets |
| `prahar/files` | `save`, `open` | backup and restore through the system picker |

The files channel has two traps worth knowing. A Java exception escaping a
handler doesn't become a Dart error: the engine aborts the process on a pending
JNI exception, leaving a tombstone that names nothing useful. So handlers catch
`Throwable` and reply with an error. And the pending-result cleanup is called
`clearPending`, not `release`, because `FlutterActivity` already has a
`release()` that tears down the engine; calling it by accident destroyed the
engine and then replied through it.

A cancelled picker returns null, not an error.

### Home-screen widgets

`NextBlockWidget` (2x1, the next block) and `TodayWidget` (4x2, two blocks and a
text progress bar), updated through `WidgetBridge` on every replan.

Widget layouts inflate through `RemoteViews`, which only accepts view classes
annotated `@RemoteView` and only older attributes:

- Use `LinearLayout` and `TextView`. A bare `<View>` as a divider takes the whole
  layout down; use an empty `TextView` with a background instead.
- Avoid `paddingHorizontal`, `layout_marginVertical`, ProgressBar `min` and
  `?android:attr/...` style references. `letterSpacing` is fine.
- Every failure shows the same "Can't load widget" with no line number, so any
  new view type has to be checked on a device.

### Manifest

Declared: `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`,
`RECEIVE_BOOT_COMPLETED`, `VIBRATE`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, the
notification plugin's receivers (so alarms survive a reboot), both widgets, and
the `<queries>` package list.

Deliberately absent:

- `INTERNET`. Fonts are bundled for the same reason: a runtime font fetch once
  failed silently and every screen fell back to the system font.
- `USE_EXACT_ALARM`, restricted by Play policy.
- Any storage permission. The picker is the grant.

If the app is ever submitted to Play, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` is
the permission most likely to be challenged. The justification is strong and
backed by evidence, but expect to argue it.

### Build and release

- Core library desugaring is required for `java.time`, and the NDK must be
  installed even though nothing compiles native code. The toolchain details are
  in CLAUDE.md.
- `minSdk` 24 (Android 7.0), target 36.
- Releases are signed with a key kept outside the repository. Keystores and
  `key.properties` are gitignored and must never be committed.
- The number after `+` in `pubspec.yaml`'s version is Android's versionCode. It
  must increase on every release, or the installer can't tell builds apart.
- Releases are signed APKs on GitHub Releases, installable with Obtainium for
  updates.

---

## 10. UI architecture

### Shell

`HomeScreen` holds five destinations: **Today, Plan, Progress, Subjects,
Settings**. They live in an `IndexedStack`, so every tab keeps its scroll
position. `HomeScreen` also observes the app lifecycle: resume triggers the
refreshes in [section 3](#3-the-update-cycle), and returning after 30 seconds or
more replays the brand mark.

| Destination | Files | Notes |
|---|---|---|
| Today | `today_editorial_screen.dart` | hero block, rail of the rest, warnings, first-run screen |
| Plan | `plan_screen.dart`, `week_screen.dart`, `calendar_screen.dart` | Days, Week and Month on a phone; grid beside the month calendar when wide |
| Progress | `plan_screen.dart` (`ProgressScreen`) | per-subject standing, "needs X a day", calibration cards |
| Subjects | `subjects_screen.dart`, `subject_detail_screen.dart` | subjects, topics, search |
| Settings | `look_screen.dart` (`SettingsScreen`), `settings_screen.dart` (subpages) | the file names are a leftover from a redesign |

Also: `timer_screen.dart`, `busy_slots_screen.dart`, `how_it_works.dart`, and
`mark_motion_screen.dart`, which is unreachable and kept for the animation
variants.

**Help is one tap from Today.** A **?** at the trailing edge of Today's top bar,
and only Today's, opens `showHowItWorksSheet` in `help_sheet.dart`: the four
steps in a line each, and a link to the full How Prahar works page. It exists
because a first-time user couldn't tell what to do, and the full guide (a small
link on the first-run screen, and a row in Settings) wasn't found.

The step titles live once, in `howPraharWorksSteps` in `how_it_works.dart`, and
both the sheet and the full page read them, so the two can't drift apart. The
button sits away from the logo, which replays its animation when tapped, and is
drawn in the quiet secondary grey rather than amber, because it's help, not a
call to action. The icon, `help_outline_rounded`, was chosen from a contact sheet
(`tools/make_help_options.ps1`). The first-run tour's replay will live in this
sheet.

**The spotlight engine** (`spotlight.dart`) is the drawing half of the first-run
tour, and knows nothing about Prahar. `SpotlightOverlay` sits as the top child of
a Stack over the app: a dim scrim with a rounded window cut round one widget,
found by `GlobalKey`, a thin ring in the primary indigo, and a bubble. Which step
is showing, and when it is finished, belongs to whatever places it.

- **Two kinds of step.** A `next` step has a Next button and the target can be
  seen but not touched. An `action` step has no Next, and the window is the only
  touchable part of the screen. It works by a render box that reports no hit
  inside the window, which hands the tap to the app underneath; everywhere else
  an empty gesture detector catches it.
- **The bubble never covers its target.** It goes above or below, whichever has
  more room, or beside a target too tall for either, like the navigation rail,
  and clamps to the screen. A step with no target, or a target not on screen,
  gets a centred card instead of an error.
- **Only the words scroll.** The buttons stay pinned under them. The first
  version scrolled the whole card, and at 320dp with 1.5x text the welcome
  card's Next ended up out of sight inside it, so a tap on it landed on the
  scrim.
- **It follows the target without a loop of its own.** It re-measures after
  every frame that happens anyway, through a chain of post-frame callbacks, which
  never schedule a frame. So it tracks a rotation or a sheet sliding away, and
  costs nothing on a still screen, where a Ticker would repaint forever.
- **The bubble is its own surface, not `StyledPanel`.** Under the Open card style
  in Glass, StyledPanel draws nothing, which is right for a list row and wrong
  for words floating over a dimmed screen.

**The first-run tour** (`tour.dart`, with its step logic in `domain/tour.dart`)
is built on the engine, and it is a do-tour: on a fresh install there is nothing
to point at, so the student makes a subject and a topic during it. It starts
with a welcome card and one stop on the tabs, then waits for Subjects to be
tapped, for a subject to be saved, shows what the subject's exam date does, and
waits for a topic. Then comes a card for setting up reminders, one stop on
Today's main card, and a last one on the Plan tab.

- **The stop is derived, never stored.** `tourStepFor` takes whether a subject
  and a topic exist, whether Subjects is showing, and which read-only stops have
  been tapped past. A restart, a cancelled sheet or a deleted subject lands on
  the right stop with no bookkeeping, for the same reason the plan is derived.
  Settings hold only `tour_started` and `tour_done`. `AppState.load` starts the
  tour when `tour_done` is unset and there are either no subjects or
  `tour_started` is set, so an install that had subjects before the tour existed
  never sees it. Passing the last stop, or Skip, sets `tour_done`.
- **Targets register themselves.** `TourTarget` marks the nav bar or rail, the
  Subjects destination, the Subject button, the first subject's card and "Add a
  topic". Each marker owns its GlobalKey, so the same target on a page being
  pushed and the page beneath can't collide, and each records whether its route
  is on top.
- **The host sits in `MaterialApp.builder`**, above the navigator, so the tour
  stays up on the subject's own page, where a phone adds topics. A stop that
  waits for a tap disappears while its target's route isn't on top, which is
  exactly what an open sheet does, and returns when the sheet closes, saved or
  not.
- **The reminders stop is the one fact stored**, as `tour_reminders`. Android
  reports nothing about autostart, so whether reminders are set up is not
  something the data can answer. The card has a row each for Android's
  notification prompts, the battery exemption, the vendor autostart screen
  where the phone has one, and a test reminder. Continue asks for
  notifications if that row was never used, then bumps
  `AppState.todayRequests`, which HomeScreen answers by closing any pushed page
  and switching to Today.
- **Launch doesn't ask while the tour runs.** `main.dart` skips
  `requestPermissions` when `tourActive`, so the OS dialogs arrive with the
  reminders card's explanation rather than over the welcome card. Skip before
  that stop asks at once, so skipping never means no reminders.
- **Replay** is "Show me around again" in the ? sheet. It clears the stops seen
  and shows the welcome and the tabs again even with data, then reminders,
  Today and Plan. The subject stops are passed, because the data already has
  what they would make. Nothing is written, so a restart ends a replay.
- Widget tests that pump `HomeScreen` without `TourHost` never draw the tour,
  and `AppState` built without `load()` never starts it.

The week view shows seven days **from today**, not Monday to Sunday: a calendar
week opened on Saturday wastes five columns on days that can't be filled.
Upright it's a row per day with time running across, because a 52dp column is a
colour, not a word. Sideways it's a seven-column grid with a clock down the side.
Blocks draw only the lines of text that fit their height and clip the rest; they
once painted over their neighbours.

**"Archived" means the same thing everywhere.** Subjects and Progress both fold
subjects whose exam has passed into an Archive section, from
`state.archivedSubjects`, and Progress's headline percentage counts only work
still ahead. A finished subject would otherwise hold that figure down for good,
over work that can no longer be done, which reads as failure rather than
history.

### Layout

`lib/ui/layout.dart` is the only place breakpoints live.

| Rule | Value |
|---|---|
| Two columns | width at least 720dp |
| Short screen | height under 500dp |
| Navigation rail | wide **and** short |
| Readable column cap | 620dp, via `ReadableColumn` |

**Width decides columns; height decides where navigation goes.** A phone sideways
(about 890 by 410) is wide and short, and a 60dp app bar plus a 68dp bottom bar
would take a third of the screen, so it gets a rail. A tablet is wide but tall,
so it keeps the bottom bar, which is easier to reach. Conflating the two
questions puts a rail on a tall tablet.

**Insets come from the system, never constants.** Scroll views end with
`navBottomInset(context)`. A fixed 90 is only right under gesture navigation;
under three-button navigation the last row sat behind the bar. Anything *pinned*
above the bar needs the inset too: the week grid's legend is a fixed footer
rather than part of a scroll view, and it sat behind the bar until it asked.

Today's app bar is glass and the body runs underneath it
(`extendBodyBehindAppBar`), so Today insets its own scroll view by the bar
height, read from the theme rather than assumed. Only Today does this.

### Theme and surfaces

`lib/ui/theme.dart` is the single place for visual tokens.

- **Type**: Inter, bundled, one variable font file.
- **Colour has meaning.** Indigo is structure: navigation, selection, focus,
  "this is today". Amber is effort: the streak, the "now" chip, filled buttons,
  the add button and progress bars. Amber lives in the `ColorScheme` (`tertiary`
  for text, `secondaryContainer` for the soft half), so any widget can reach it
  and it can't be half-applied. One `FilledButtonThemeData` serves both
  `FilledButton` and `FilledButton.tonal`, so a tonal button inherits amber unless
  it passes `secondaryContainer` explicitly.
- **Surfaces answer to two settings**, Materials (matte or glass) and Cards (five
  styles). `StyledPanel` in `glass.dart` respects both; list rows use `Card`. A
  hand-rolled `Container` looks like one card style and silently ignores the
  other four.
- **Glass summarises, matte lists.** Glass is used on the bottom bar, sheets,
  Today's app bar and hero, the feasibility banner and the subject status panel,
  at a surface alpha of 0.28. Spreading it to cards or rows removes the contrast
  that makes it read as glass.
- **Card styles are five different ideas**, not five weights: an outline, a tonal
  step, a shadow, a colour wash, and nothing. The picker previews each as two
  stacked cards, because a card only turns into a grid once it has a neighbour.

### The brand mark

`PraharMark` is drawn by a `CustomPainter` (`brand.dart`), not a bundled image.
Its proportions mirror the launcher icon generator, `tools/make_icon.ps1`, and
**the six tuned numbers must change together in both places**. Nothing enforces
that yet; a test pinning them is on the open list.

Two deliberate departures from strict proportion, because the icon renders at
1024px and the widget at 24 to 56dp: stroke widths have a minimum in logical
pixels, and the light palette uses darker ink. A proportional tick is 0.4px at
24dp, which anti-aliases to nothing.

`AnimatedPraharMark` plays a 1100ms "unfurl" on the first-run screen, when the
mark is tapped, and on returning to the app.

### Layout rules learned the hard way

- **A `Spacer` doesn't stop a `Row` overflowing.** Fixed children are laid out
  first and the spacer gets whatever is left, which can be nothing. Put
  `Expanded` on the element that should give way.
- **A `Stack` top-aligns anything it doesn't position.** A test that checked only
  horizontal centres passed for three rounds while the labels sat 14dp too high.
  Assert both axes.
- **A `Card` paints its outline under its child**, so a filled child hides it.
  Draw the border in a foreground `DecoratedBox`, and take its colour and width
  from the `CardStyle`: reading them back from `theme.cardTheme.shape` returned
  no side at runtime even where the theme plainly had one.
- **User-entered strings get their own line.** A long subject name shared a row
  with "49 days left" and collided. Any row mixing a user string with app text
  needs checking.

Rules for writing UI copy are in CLAUDE.md.

---

## 11. Testing

306 tests in 24 files. `flutter analyze` is required alongside them, because a
test run only compiles what the tests import and leaves the rest of `lib/ui`
unchecked.

| Kind | Files |
|---|---|
| Pure logic | `planner_test`, `estimator_test`, `calibration_test`, `subject_test`, `study_timer_test`, `today_focus_test`, `preferences_test`, `digest_test`, `layout_test` |
| Storage | `database_test`, `backup_roundtrip_test` |
| State | `reanchor_test`, and the logic groups in `autostart_test` and `reminders_toggle_test` |
| Screens and layout | `device_matrix_test`, `landscape_test`, `glass_inset_test`, `first_run_test`, `week_grid_test`, `theme_toggle_test`, `progress_query_test`, `help_sheet_test`, `spotlight_test`, `tour_test`, and the UI groups in `autostart_test` and `reminders_toggle_test` |

### Principles

**A test isn't finished until it has been seen to fail.** The `database_test`
cases were confirmed to fail against the `INSERT OR REPLACE` code. The first test
written for the Progress query bug passed against the broken code and was thrown
away; its replacement was confirmed failing first.

**Widget tests are how layouts get checked.** The development phone refuses
input injection over adb, so nothing can rotate it or drive it to a screen.
`device_matrix_test` pumps every screen at 320dp with a 1.5x font;
`landscape_test` and the tablet cases pump real device sizes. The test font draws
every glyph as a fixed-width box, wider than Inter, so these tests are
conservative: a row that only overflows in a test overflows on a phone with large
text. Insets such as three-button navigation are supplied explicitly, since
neither development device uses it.

**Match concepts, not copy.** A test that matched the word "cycle" held a copy
rewrite hostage.

### Test harness traps

- **A widget test can't write to the database on fake time.** sqflite schedules
  a real timer, which never fires inside `testWidgets`. The symptom never names
  the cause: "A Timer is still pending", or if the write is awaited, a guarded
  function conflict blaming the next `pumpWidget` after the suite hangs.
  Set state directly instead of awaiting a method that writes. When the tap
  being tested must write, wrap it in `tester.runAsync` and wait until the value
  reads back, not for a fixed delay.
- **`pumpAndSettle` never settles on Today**, which runs a periodic timer. Use
  `pump`.
- **There is no notification plugin in tests.** `Notifier` fails soft, so
  anything that replans still works.
- Test runs cap each test at 60 seconds, so a hang fails fast and names itself.

### What tests can't cover

Real alarm delivery, OEM autostart behaviour, home-screen widget inflation and
three-button navigation on hardware. For those, the device tools in `dev.ps1`:
`notif` (channel and delivery state), `alarms` (pending alarms), `check` (process
and logs), `vendorpkgs` (autostart targets), and the in-app **Send a test
reminder**, which exercises the whole path from alarm to notification.

---

## 12. Known limitations

- **Android only.** An iOS version would be a project, not a port: notifications,
  battery handling, the file picker and both widgets would all be rewritten, and
  it can't be built on Windows.
- **Timezone assumes India.** See [section 8](#timezone).
- **Logged minutes are read as progress.** See
  [section 6](#known-gap-what-logged-minutes-mean).
- **Fixed review spacing.** The planned direction is to log a recall grade at
  the end of each session first, then replace the ladder with FSRS once there's
  enough history. The logging is the time-sensitive half, since history can't be
  collected retroactively.
- **Resources are modelled but not exposed** beyond one link per topic.
- **The planner has no lookahead.** See [section 5](#known-weaknesses).
- **Autostart targets are unverified** on Samsung, Vivo, Huawei and Honor.

Not planned: accounts, sync, or messaging channels. If notifications ever gain
more channels, they go behind an interface so the planner never learns about
them.
