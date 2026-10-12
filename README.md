# WorkoutTracker

An iOS workout-logging app for Victor: paste the day's programmed workout
from his coach's TrueCoach **email** straight into the app, log only the
weights per set, get last-weight suggestions automatically, and see exactly
what plates to load on the bar.

**Status:** builds in Xcode (iOS 17+, zero dependencies), paste import
working, 49 unit tests. SwiftUI + SwiftData.

## Requirements

- macOS with Xcode 16+ (iOS 17 SDK)
- No package dependencies, no API keys, no accounts — open and run.

## Getting started

```bash
git clone https://github.com/victor-riv/workoutapp.git
cd workoutapp
open WorkoutTracker.xcodeproj
```

In Xcode: run the `WorkoutTracker` scheme on a simulator or device (`⌘R`),
and the `WorkoutTrackerTests` scheme for the unit tests (`⌘U`).

> `WorkoutTracker.xcodeproj` is committed directly — no XcodeGen needed.
> `project.yml` + `generate_xcodeproj.py` are kept as a backup generator.

## How the import works

1. The coach's TrueCoach app emails one workout per training day from
   `swoletron@truecoach.co` (~00:20 ET).
2. Victor copies the email body and pastes it into the **Today** tab →
   **Paste workout** (no subject line needed — the app doesn't care about
   it).
3. `EmailWorkoutParser` turns the pasted text into a structured workout —
   sets/reps, RIR, per-side, coach-prescribed weights, supersets, cardio,
   nutrition — per `EmailImport/EMAIL_FORMAT_SPEC.md`. Plain-text labels
   like `B) Exercise Name` work; the `**bold**` markers are optional.
4. The workout is logged under **today's date**. Re-pasting the same day
   updates the prescription without ever clobbering logged sets.

## Project layout

```
WorkoutApp/
  App/                  @main app, ContentView (tab bar)
  Models/               SwiftData models: Exercise, WorkoutDay,
                        WorkoutExercise, WorkoutSet, GymProfile
  Logic/                PlateCalculator, SetRepParser, EmailWorkoutParser
                        (pure, testable)
  Services/
    ServiceFactory.swift        mock ↔ Gmail switch (mock is active)
    WeightSuggestionService.swift  "last weight" lookup
    Import/
      WorkoutSource.swift       import protocol + app-facing models
      WorkoutImporter.swift       parsed workouts → SwiftData (no-clobber)
      MockWorkoutSource.swift     sample data
    Email/                      DORMANT: Gmail auto-import, behind
      GoogleAuthProvider.swift    `#if canImport(GoogleSignIn)` guards.
      GmailService.swift          Future upgrade — needs a Google Cloud
      EmailWorkoutSource.swift    OAuth client + the GoogleSignIn package.
    TrueCoach/                  DEMOTED fallback: private-API client,
      TrueCoachAPIClient.swift    DTOs, Keychain helper, research notes.
      TrueCoachDTO.swift          Not wired up (see TRUECOACH_INTEGRATION.md).
      KeychainHelper.swift
      TRUECOACH_INTEGRATION.md
  Views/
    Today/              today's workout list + PasteWorkoutView
    Exercise/           set-by-set logging
    Calculator/         plate calculator UI
    Settings/           gym profile
  EmailImport/          (repo root) email format spec + real fixtures
WorkoutAppTests/
  PlateCalculatorTests.swift
  SetRepParserTests.swift
  EmailWorkoutParserTests.swift
```

## Docs

- [`BUILD_CHECKLIST.md`](BUILD_CHECKLIST.md) — first-build notes (mostly
historical now that the project builds; kept for reference).
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — decisions, data model, flows,
roadmap, next steps.
- [`EmailImport/EMAIL_FORMAT_SPEC.md`](EmailImport/EMAIL_FORMAT_SPEC.md) —
the exact TrueCoach email format the parser implements.
- [`WorkoutApp/Services/TrueCoach/TRUECOACH_INTEGRATION.md`](WorkoutApp/Services/TrueCoach/TRUECOACH_INTEGRATION.md) —
the (demoted) TrueCoach private-API research, kept as a fallback.

## Notes

- `gmail.readonly` is a Google *restricted* scope: fine for personal use
with the OAuth app in Testing mode, but App Store publication would need
Google's verification. (Only relevant if the dormant Gmail auto-import
is ever revived.)
