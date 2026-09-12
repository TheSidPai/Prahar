# Prahar

A study planner that tells you the truth about whether your plan is possible.

You enter your subjects, their exam dates, the topics you need to cover and how
much time you actually have. Prahar builds a day-by-day schedule, reminds you
when each block starts, and moves the work forward when you miss a day. If the
work doesn't fit before an exam, it says so, and by how much.

Everything stays on your phone. There is no account and no server, and the app
has no internet permission at all.

## Install

Android 7.0 or newer. There is no iPhone version.

1. Download the APK from the
   [latest release](https://github.com/TheSidPai/Prahar/releases/latest).
2. Open it. Android will ask you to allow installs from wherever you downloaded
   it, and Play Protect will warn about an app it hasn't seen before. Both are
   normal for an app from outside the Play Store.
3. Open Prahar and allow notifications.

Prahar doesn't update itself. To get new versions automatically, add this
repository to [Obtainium](https://github.com/ImranR98/Obtainium).

### Two settings decide whether reminders work

With either one off, reminders are scheduled but never arrive, and nothing on
screen tells you. Prahar asks for both.

- **Battery: unrestricted.** Otherwise Android freezes the app in the
  background and a reminder only shows up when you next open it.
- **Autostart**, on Xiaomi, Oppo, Realme, OnePlus, Vivo, Huawei, Honor and
  Samsung. These phones keep their own list of apps allowed to start on their
  own, and a new install isn't on it. Prahar shows a card that opens the right
  screen, and the same link stays in Settings > Notifications.

To check, go to Settings > Notifications > **Send a test reminder**, lock the
phone and wait a minute.

## What it does

- **Plans from your exams backwards.** Each subject gets time in proportion to
  how much work it still needs per day before its exam, not just how soon the
  exam is.
- **Warns when the plan can't work**, per subject: which exam it won't fit
  before, and how many extra minutes a day would close the gap.
- **You enter pages or problems, not minutes.** Prahar converts, then learns
  your real pace per subject from finished topics and offers to update the
  estimates.
- **Missed days move forward.** The schedule is rebuilt whenever anything
  changes, so a skipped block lands later instead of turning into an overdue
  pile.
- **Reviews are scheduled** 1, 3, 7 and 21 days after you finish a topic.
- **A focus timer** (25/5 or 50/10) that logs the minutes you actually studied.
- **Busy slots** for classes, meals or a shift, weekly or one-off, and an
  optional exam start time.
- A week view, an exam calendar, an evening summary of tomorrow's blocks, and
  two home-screen widgets.
- Backup and restore to a file you choose.
- Light and dark, five card styles, a glass or matte finish. Works sideways and
  on tablets.

## How the planning works

The planner walks forward one day at a time. Reviews that are due go first,
capped at 40% of the day. The rest of the day is filled by repeatedly picking
the topic whose subject needs the most minutes per day to be ready for its
exam, while respecting prerequisites, your busy slots, and a limit of two
blocks of the same subject in a row. A subject that is far more pressed than
anything else is allowed to break that limit.

It's deliberately simple: it runs in microseconds, so it can rebuild the plan
on every edit, and you can always see why a block landed where it did.

[ARCHITECTURE.md](ARCHITECTURE.md) covers the whole system in detail.

## Building from source

You need Flutter 3.47 (Dart 3.13), the Android SDK, and JDK 17. Newer JDKs are
rejected by the Android Gradle plugin.

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

The planner and domain code are plain Dart, so most of the test suite runs
without a device. Signing keys are not in this repository.

On Windows, `tools\dev.ps1` wraps all of this and sets up JDK 17 and the SDK
paths: `tools\dev.ps1 test`, `tools\dev.ps1 apk`, `tools\dev.ps1 install`.

## Status

Version 0.2.0, the first public release.

Tested on real hardware: a Xiaomi phone on Android 16 and a OnePlus Pad on
OxygenOS 16, covering reminders on the lock screen, the autostart link, the
tablet layout and landscape. 311 automated tests, including every screen at
320dp wide with large text.

Known limitations:

- **Android only.**
- **Built for India.** If the phone isn't on India Standard Time, reminder times
  may be off.
- **The autostart link is unverified on Samsung and Realme.** If it opens the
  wrong screen on your phone, please open an issue with the model.
- **Logged time counts as progress.** If a 40-minute block took you 80 minutes,
  Prahar treats that as twice the work done, not as slower going. If a topic is
  taking longer than expected, increase its size in Subjects.
- Review spacing is fixed rather than adapting to how well you remembered.
