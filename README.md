# Prahar

A study planner that tells you the truth about whether your plan is possible.

You enter your subjects, their exam dates, the topics you need to cover, and
how much time you actually have each day. Prahar builds a day-by-day schedule,
reminds you on your phone when each block starts, and quietly reshuffles
everything when you miss a day.

Everything runs on your device. No account, no server, no subscription, and it
works with no network at all.

## What makes it different

**It will tell you when the plan doesn't fit.** Most study apps happily
generate a schedule that cannot possibly be finished, and you discover the
problem the week of the exam. Prahar compares the work you've entered against
the time you've actually got and says, per subject, exactly where the shortfall
is and how many extra minutes a day would close it.

**You never estimate minutes.** You can't, and neither can anyone else. You
enter pages, problems, or a video's runtime, and it converts. Then it watches
how long things really take you and adjusts the rate per subject — after a
couple of weeks it knows you read Organic Chemistry at 5 min/page and Maths
at 2.

**Missing a day is normal.** The schedule is regenerated from scratch every
time anything changes, so a missed session moves forward instead of turning
into a red overdue badge. Skipping a block means "not today", and the work
lands tomorrow.

**Reviews are scheduled, not hoped for.** When you finish a topic, short review
blocks are automatically placed 1, 3, 7 and 21 days later, and they take
priority over new material because a review three days late is barely a review.

## Getting started

Requires the Flutter SDK and, to run on a phone, the Android SDK.

```bash
flutter pub get
flutter test           # the planner is pure Dart — no device needed
flutter run            # onto a connected phone
```

## How it works

The scheduler is a pure function: subjects + topics + availability + today's
date produce a list of study blocks. It's greedy rather than an optimiser,
which means it runs instantly, always has an explainable reason for putting a
block where it did, and — importantly — stays stable, so one missed session
shifts work forward instead of reshuffling your whole month.

Reminders are local OS alarms rather than push notifications, so they fire
offline and cost nothing to run.

See [CLAUDE.md](CLAUDE.md) for the architecture in detail.

## Status

Early, and honest about what that means.

The planner and effort estimator are covered by 39 tests and the whole project
passes static analysis, so the scheduling logic is well exercised. The UI, the
database layer and the notification scheduling compile but have **never run on
a real device** — alarm delivery in particular is unproven, and Android's
battery optimiser is where apps like this usually fail.

Resource tracking (books and links per topic) exists in the data model and the
estimator supports it, but no screen reads it yet. Per-subject calibration is
recording data without yet feeding back into estimates.
