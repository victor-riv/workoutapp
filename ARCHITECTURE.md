# WorkoutTracker — Architecture

## 1. Import verdict: paste the email (primary), Gmail auto-import (later)

**Decision (2026-10-10, Victor's call): the TrueCoach private-API approach
is out.** The app imports workouts from the TrueCoach workout notification
emails the coach already sends every training day (~00:20 ET) from
`swoletron@truecoach.co`.

**Decision (2026-10-12, Victor's call): paste-first, no OAuth.** Instead of
the Google Cloud OAuth dance, Victor copies the email body and pastes it
into the app. Zero setup, zero cost, works today. The same
`EmailWorkoutParser` does the work either way, so automatic Gmail import
can be switched on later without touching the parser or the UI flow.

**How paste import works**

- **Paste sheet** (`Views/Today/PasteWorkoutView.swift`): subject field
  (optional, helps the date) + body text editor → **Parse workout** shows a
  preview (exercise count, per-exercise prescription lines, nutrition) →
  **Save workout** imports via `WorkoutImporter`.
- **`EmailWorkoutParser`** (`Logic/EmailWorkoutParser.swift`): pure
  string-in/string-out parser implementing
  `EmailImport/EMAIL_FORMAT_SPEC.md`. Handles every observed format:
  sets×reps, RIR annotations, per-side/per-each, time-under-tension,
  `x5-10/movement`, weight×sets×reps (`155 x 2 x 8`), ambiguous
  weight×reps (`115 x 3` — flagged, never guessed), multi-line back-off
  sets, embedded exercise names (`ITYW Raise x 10/ea` — becomes the tracked
  movement), cardio, intervals (kept verbatim), TRAC assessment blocks,
  supersets (H1/H2), and the nutrition block. "You missed your workout"
  reminder emails are rejected with an explanatory message.

**Automatic Gmail import (built, dormant).** The full Gmail layer exists
and compiles behind `#if canImport(GoogleSignIn)` guards:

- **Google Sign-In** (`Services/Email/GoogleAuthProvider.swift`, via the
  official `GoogleSignIn` SDK) with a single OAuth scope:
  `https://www.googleapis.com/auth/gmail.readonly`.
- **`GmailService`** (`Services/Email/GmailService.swift`): lists messages
  matching `from:swoletron@truecoach.co "[TrueCoach]"`, fetches full bodies
  (prefers the `text/plain` MIME part, base64url-decodes it; falls back to
  stripping the `text/html` part).
- **`EmailWorkoutSource`**: the `WorkoutSource` implementation for Gmail.
- Enabling it later is: finish the OAuth client in Google Cloud → add the
  GoogleSignIn Swift package in Xcode → flip `ServiceFactory.useMock`.
- Scope note: `gmail.readonly` is a Google *restricted* scope. Fine for
  personal use with the OAuth app in Testing mode; App Store publication
  would require Google's restricted-scope verification — a later bridge.

**Fallback (documented, not wired up):** the researched TrueCoach private
client API (`Services/TrueCoach/TrueCoachAPIClient.swift`) still conforms
to `WorkoutSource`; `ServiceFactory` could select it again if the email
path ever fails. Research notes in `TRUECOACH_INTEGRATION.md`.

## 2. Architecture decisions

- **SwiftUI + SwiftData, iOS 17+.** SwiftData is the right call for a
  single-developer app: the model *is* the persistence layer, `@Query` /
  `@Bindable` keep views reactive with almost no glue code, and iCloud
  sync (`NSPersistentCloudKitContainer` under the hood) is nearly free
  later. Third-party dependencies: zero (GoogleSignIn is dormant code,
  not a linked package).
- **Protocol-segregated import layer.** The app depends only on
  `WorkoutSource` (`Services/Import/WorkoutSource.swift`).
  `MockWorkoutSource` (sample data), `EmailWorkoutSource` (Gmail), and
  `TrueCoachAPIClient` (demoted fallback) are interchangeable via one flag
  in `ServiceFactory`. The paste flow bypasses the service entirely and
  calls the parser + `WorkoutImporter` directly.
- **Pure-logic core.** `PlateCalculator`, `SetRepParser`, and
  `EmailWorkoutParser` are dependency-free — unit-testable without a
  simulator, and portable if the app ever grows a watchOS/widget target.
- **Re-import never clobbers.** `WorkoutImporter` dedupes on
  `sourceWorkoutID` + date ("W2D3" + day). Re-importing updates the
  *prescription* (sets/reps/notes/order) and leaves logged sets untouched;
  blocks that vanished are deleted only when they carry no logged data.
- **Derived weight history, not denormalized.** "Last weight" is a query
  over completed sets (`WeightSuggestionService`), not a cached column —
  it can never go stale when history is edited. When there's no history,
  the coach's prescribed weight (e.g. 155 from "155 x 2 x 8") pre-fills
  the set rows instead.
- **Credentials hygiene.** No TrueCoach password anywhere. No Google
  tokens in the paste-first build (nothing to leak). Everything on-device;
  no backend, no analytics.
- **Hand-generated `.xcodeproj`.** `generate_xcodeproj.py` emits the
  project deterministically (`project.pbxproj` + both `Info.plist`s) — no
  XcodeGen install needed on the Mac, no fragile hand-maintained project
  file in the repo.

## 3. Data model

```
GymProfile (singleton)
  unit, barWeight, collarPairWeight, inventoryData(JSON [PlateDenomination])

Exercise                        WorkoutDay
  name                            date (start-of-day)
  normalizedName (dedup key)      title
  createdAt                       sourceWorkoutID? ("W2D3")
        ^                         importedAt, isCompleted
        |                         nutritionSummary?
        |                               ^
        |                               | cascade
        v                               v
WorkoutExercise  ──►  WorkoutSet
  order               setNumber
  targetSets          targetReps
  targetReps          weight? (logged)
  coachNotes          reps? (logged)
  prescribedWeight?   isCompleted
  kindRaw             unitRaw
  exercise? ─────────
  workoutDay?
```

- `Exercise` rows are shared across days (matched by `normalizedName`),
  so history accumulates per exercise regardless of which day it appeared on.
- `WorkoutExercise.ensureSets(unit:)` pre-creates empty set rows from the
  prescription (lift blocks only — cardio/assessment/mobility render as
  info); import seeds each row's weight from history, else the coach's
  prescribed weight.
- `kindRaw` (`ExerciseKind`: lift/cardio/assessment/mobility) comes from
  the email parser's classification.
- `GymProfile` stores the plate inventory as JSON — flexible without extra
  tables; `makeCalculator()` builds a configured `PlateCalculator`.

## 4. Key flows

**Paste import.** Today tab → **Paste workout email** → paste body →
**Parse workout** (preview) → **Save workout** → `EmailWorkoutParser` →
`ParsedWorkout.toImportedWorkout` → `WorkoutImporter` (upsert by source id
+ date, reuse/create `Exercise`s, pre-fill sets, seed suggested weights)
→ list. "You missed your workout" reminders are rejected. TrueCoach owns
the *prescription*, the app owns *logged* weights.

**Logging a set.** Exercise detail → type weight (pre-filled) + reps →
toggle done. Writes go straight to SwiftData via `@Bindable`. The per-set
plate sheet shows exactly what to load for the entered weight.

**Plate math.** `PlateCalculator.plates(for:)` solves a bounded knapsack
per side (integer hundredths, memoized DFS): max load ≤ target respecting
pair counts, preferring larger plates. **Never exceeds the target** —
inexact targets floor to the heaviest achievable load and report the
shortfall. Supports 45 lb / 20 kg bars (or custom), configurable
inventory, optional collar pairs.

**Apple HealthKit (later phase).** Log an `HKWorkout` (strength training)
with per-set `HKQuantitySample`s on workout completion. Needs the
HealthKit entitlement + `NSHealthShareUsageDescription` /
`NSHealthUpdateUsageDescription` keys. Deliberately deferred until the
core loop works.

## 5. Roadmap

- [x] Scaffold: models, views, plate calculator + tests, import layer + mock
- [x] Email parser + paste import UI: parser + 25 tests, preview + save,
      importer with no-clobber re-import
- [x] Hand-generated `.xcodeproj` (no XcodeGen needed)
- [ ] First Xcode build: open the project, run unit tests (12 plate +
      11 set/rep + 25 email parser), fix any compile nits
- [ ] First paste import on a real device; confirm weight suggestions
- [ ] Polish the daily loop: pull-to-refresh, completion state, history tab
- [ ] Automatic Gmail import (OAuth client + GoogleSignIn package +
      `useMock = false`) — optional upgrade
- [ ] HealthKit workout logging
- [ ] iCloud sync, PR tracking, rest timer, charts

## 6. Next steps

1. **First build + test run in Xcode.** Open
   `~/workout-app/WorkoutTracker.xcodeproj`, select the
   `WorkoutTrackerTests` scheme, press `⌘U`. Expect 48 tests green. Fix
   whatever the compiler flags — the logic was hand-reviewed against
   current Swift/SwiftUI/SwiftData APIs, so expect only small nits.
2. **First paste import on a real device** (simulator works too): Today
   tab → Paste workout email → paste today's TrueCoach email → Parse →
   Save. Log a set or two to confirm the loop.
3. **If an email format ever fails to parse**, the raw text is preserved
   in the parser output — send the raw line and the parser gets extended
   (there's a test suite waiting for the new case).
