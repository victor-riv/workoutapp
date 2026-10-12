# Build checklist — first Xcode run (paste-first, no OAuth)

The app imports workouts by pasting the TrueCoach email text — no Google
Cloud project, no OAuth client, no sign-in needed. (Automatic Gmail import
can be added later; the parser and import pipeline are already built for it.)

## 1. Open the project

The project folder is already on your Mac at `~/workout-app`.

1. Open `~/workout-app/WorkoutTracker.xcodeproj` in Xcode.
2. Let it finish indexing. There are no external packages to resolve —
   everything is plain Swift + SwiftUI + SwiftData.

## 2. Run the tests (`⌘U`)

1. Select the `WorkoutTrackerTests` scheme (top toolbar, next to the Run button).
2. Press `⌘U`. Expect **48 tests**: 12 plate calculator, 11 set/rep parser,
   25 email parser (including a regression test on a real W2D3 email body).
3. All green? Move on. If the compiler complains about anything, send me the
   error text and I'll fix it.

## 3. Run the app (`⌘R`)

1. Switch to the `WorkoutTracker` scheme, pick **your iPhone** (or any
   simulator) as the destination, press `⌘R`.
2. First launch on a physical iPhone: Xcode will ask you to sign the app.
   Use your Apple ID (free personal team is fine) — Xcode guides you.

## 4. Import your first workout (paste)

1. On your phone, open the TrueCoach email for today and copy the body text.
2. In the app, Today tab → **Paste workout email** → paste → **Parse workout**.
3. Check the preview, tap **Save workout**.
4. Log your sets — weights are pre-filled from your history when available,
   and the plate button on each set tells you what to load on the bar.

## Notes

- A Google Cloud project named `WorkoutTracker` was created during setup but
  is **not used** by this build and costs nothing. It can be deleted or kept
  for the future auto-import upgrade.
- The Gmail auto-import code is still in the project (behind compiler guards)
  and compiles fine without the GoogleSignIn package. Adding it later is:
  finish the OAuth client in Google Cloud → add the GoogleSignIn package in
  Xcode → flip `ServiceFactory.useMock = false`.

## If something looks off

- **Parse finds nothing:** make sure you pasted the full email body including
  the `**A) …**` exercise lines. The subject line helps with the date but the
  body is what matters.
- **An exercise parses weirdly:** ambiguous lines are never silently guessed
  (e.g. `115 x 3` shows up flagged in the coach notes with the raw text).
  Send me the raw line and I'll extend the parser — there's a test suite
  waiting for the new case.
