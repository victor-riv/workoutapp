# TrueCoach Integration Plan

> **DEMOTED TO DOCUMENTED FALLBACK (2026-10-10, Victor's decision).**
> The app now imports workouts by parsing TrueCoach workout notification
> emails from Gmail (`Services/Email/` + `Logic/EmailWorkoutParser.swift`) —
> no TrueCoach credentials, no private API. This document is kept as the
> research record and as the re-activation plan if the email path ever
> needs a backup. `TrueCoachAPIClient` still conforms to `WorkoutSource`
> and `ServiceFactory` could select it again, but nothing wires it up today.

How the app gets Victor's programmed workouts out of TrueCoach and into
`WorkoutDay` rows. Status: **scaffolded, not yet verified against a live
account** — the app currently runs on `MockWorkoutSource`.

## 1. Verdict (from research, 2026-10-09)

- **No official public API.** TrueCoach (by Xplor) offers no developer portal,
  OAuth app registration, or documented client API. Their GitHub org
  (`github.com/truecoach`) publishes only internal tooling (Sidekiq/JS
  helpers) — nothing for workout data.
- **The private client API is community-documented and works.** The open
  source project [`truecoach-local`](https://github.com/tgriozel/truecoach-local)
  (a Python scraper for personal workout archives) documents the exact flow
  the TrueCoach web/mobile clients use:
  - **Auth:** `POST /proxy/api/oauth/token`, form-encoded
    `grant_type=password&username=<email>&password=<password>` →
    `{ access_token, user_id }`.
  - **Client id:** `GET /proxy/api/users/{user_id}` resolves the `client_id`.
  - **Workouts:** `GET /proxy/api/clients/{client_id}/workouts?states=…&order=…&page=N&per_page=50`
    returns a **compound document**: `workouts[]`, `workout_items[]`,
    `comments[]`, `meta{}`.
  - **History search:** `GET /proxy/api/v2/workout_items?client_id=…&query=<name>&state=completed`.
  - **Required headers** (endpoints 404 without them):
    `Role: Client`, `X-Requested-With: XMLHttpRequest`.
- **Data model facts:** `WorkoutItem` is the unit of work — `name` (exercise),
  `info` (coach instructions), `result` (athlete's logged performance).
  `is_circuit` marks block headers ("WARM UP", "METCON"). There are no
  "programs"; history is a flat workout list.

### Recommended approach (ranked)

1. **Private client API with the user's own credentials (implemented as
   `TrueCoachAPIClient`).** Read-only access to Victor's own data, using his
   own login, with his consent. Best UX: one sign-in, then automatic daily
   import. Risks: undocumented → can break if TrueCoach changes it;
   technically against their ToS for automated access (low practical risk
   for personal, read-only, human-scale use, but Victor should know).
2. **Manual export / copy-paste fallback.** If the API breaks: the coach's
   workout is visible in the TrueCoach app; a "paste workout text" importer
   (same `SetRepParser` + importer pipeline) keeps the app usable. Cheap to
   add later since `TrueCoachService` is a protocol.
   > Observed 2026-10-10: TrueCoach also emails each workout (subject
   > "[TrueCoach] Victor, here's your workout for W2D3 …"), with the same
   > per-exercise text the API's `info` field carries (e.g. "3 x 10/side
   > RIR 2-3", "x5-10/movement", "20 minutes"). So the email itself is a
   > ready-made paste source — and that email's lines are now the regression
   > fixture in `SetRepParserTests.testTodaysW2D3Lines`.
3. **Ask TrueCoach / the coach.** Worth one email to TrueCoach support asking
   about API access, and asking the coach whether they can share programming
   another way (e.g. a shared doc). Unlikely to yield an API, but zero cost.

## 2. What's already built

- `TrueCoachService` protocol — the app depends only on this.
- `TrueCoachDTO.swift` — Codable models for the compound document.
- `TrueCoachAPIClient.swift` — full sign-in + fetch implementation following
  the documented flow. Token → Keychain, never UserDefaults; password is
  used once and never stored.
- `MockTrueCoachService.swift` — realistic sample workout for development.
- `ServiceFactory.useMock` — one flag switches between them.
- `TrueCoachImporter` — maps `ImportedWorkout` → SwiftData, de-duplicates
  re-imports by TrueCoach workout id, reuses `Exercise` rows by normalized
  name, pre-fills sets, and seeds each set's weight from history.
- `SetRepParser` — turns coach text ("4x8 @ RPE 8", "3 sets of 10") into
  (sets, reps).

## 3. Verification steps (do these on a Mac with Victor's account)

Each `VERIFY` comment in the code maps to one of these steps. Do them in
order; stop and fix the code before moving on.

1. **Confirm the base host.** The documented paths are `/proxy/api/…`,
   which implies the TrueCoach web host. Sign in at the TrueCoach web app
   in a desktop browser, open devtools → Network, and confirm the host and
   the token endpoint path. Update `TrueCoachAPIClient.baseURL`.
2. **Token exchange.** Replicate the password-grant POST with `curl` (or a
   scratch Swift script) using Victor's credentials. Confirm you get
   `access_token` + `user_id`. If the grant needs extra fields (client_id/
   client_secret copied from the web app), note them — the web app's own
   login request in devtools shows exactly what's sent.
3. **Resolve client_id.** `GET /users/{user_id}` with the two required
   headers + bearer token. Confirm the JSON key holding the client id.
4. **List workouts.** `GET /clients/{id}/workouts` with `states=completed`
   first (known-good), then try `scheduled`, `upcoming`, `pending`,
   `active` to find which value returns *future/programmed* workouts —
   that's what "today's workout" needs. Record the exact `states` values.
5. **Confirm JSON keys.** Check `due_date` format, the item→workout link
   key (`workout_id`?), `is_circuit`, `position`, and `state` strings.
   Update `TrueCoachDTO` coding keys accordingly.
6. **End-to-end in app.** Flip `ServiceFactory.useMock = false`, sign in
   from Settings, import from the Today tab. Verify exercises, set counts,
   and coach notes match what the TrueCoach app shows.
7. **Backfill history (optional, high value).** Page through
   `states=completed` history and import past workouts as completed days —
   this seeds the "last weight" suggestions from day one instead of waiting
   weeks. `TrueCoachImporter` already de-duplicates by workout id.

## 4. Sync strategy

- **When:** on Today-tab appear + pull-to-refresh (add `refreshable`).
  Daily is plenty; the coach programs days ahead.
- **What:** fetch programmed workouts for a ±7 day window, upsert by
  TrueCoach workout id.
- **Conflicts:** TrueCoach is the source of truth for the *prescription*;
  the app is the source of truth for *logged* weights. Re-import updates
  prescription fields only, never overwrites logged sets. (Current
  importer replaces same-day imports wholesale — refine to prescription-only
  updates once real data flows.)
- **Write-back:** out of scope for v1. Logging stays local; the coach still
  sees results in TrueCoach if Victor logs there too, or not at all.

## 5. Security notes

- Password: in-memory only, one request, never persisted or logged.
- Token: Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
- On 401: wipe the token and prompt to sign in again.
- No analytics, no servers — everything stays on device.
