# TrueCoach Workout Email — Format Spec (for the Gmail import parser)

Derived from real emails pulled 2026-10-10. Raw bodies saved under
`~/workspace/email/gmail/`.

## Envelope

- **From:** `Jonathan Renninger <swoletron@truecoach.co>` — the local part is
  the coach's TrueCoach handle (`swoletron`); the display name is the coach.
  Filter on `from:swoletron@truecoach.co` (or more loosely `from:truecoach.co`).
- **Workout subject:** `[TrueCoach] <FirstName> , here's your workout for <WnDm> for <Weekday Mon D, YYYY>`
  - Note the stray space before the comma: `Victor ,`.
  - `WnDm` = week/day code, e.g. `W2D3`.
- **Missed-workout subject:** `[TrueCoach] You missed your workout for <Weekday Mon D, YYYY>`
  - These are reminders; the parser should **skip** them (no workout payload needed).
- One email per training day, sent ~00:20 ET the morning of the workout.

## Body structure (plain-text/Markdown rendering)

1. Header boilerplate (`TrueCoach Email`, `You've received a workout.`, `Here's your training`).
2. `Hey <Name> ,` + `Here's your workout for <Weekday, Month D, YYYY>:` — the
   canonical workout date lives here.
3. `**WnDm**` week/day marker.
4. Exercise blocks, each starting with a bold label line:
   `**<LETTER>) <Exercise Name>**`, e.g. `**D) Dumbbell Romanian Deadlift**`.
   - Supersets share a letter with numeric suffixes: `**H1) ...**`, `**H2) ...**`.
   - Prescription lines follow the label (1..n lines).
   - Some exercises have sub-lines that are NOT prescriptions
     (e.g. `Front` / `Lateral` / `Rear` under `Dumbbell Shoulder 3-way Raise`).
5. Nutrition block: `** Nutrition **` then `- Protein: 155 g`, `- Carbs: 275 g`,
   `- Fat: 65 g`, `- Total Calories: 2305`.
6. Sign-off: `- Your Coach,` + coach name; footer links.

## Prescription formats observed (the parser must handle all of these)

| Format | Example | Meaning |
|---|---|---|
| sets x reps | `3 x 15` | 3 sets of 15 |
| sets x reps RIR | `3 x 10 RIR 2-3` | 3x10, reps-in-reserve 2–3 |
| per-side | `3 x 10/side RIR 2-3` | 3x10 each side |
| per-each | `3 x 10/ea RIR 2-3` | 3x10 each (arm/shoulder) |
| time under tension | `3 x 30s` | 3 sets of 30 seconds |
| reps per movement | `x5-10/movement` | 5–10 reps per movement, sets implied |
| weight x sets x reps | `155 x 2 x 8` | 155 lb, 2 sets, 8 reps |
| weight x reps (ambiguous) | `115 x 3` | 115 lb x 3 reps; set count implied — flag as ambiguous, don't guess |
| multi-line prescription | `115 x 3` newline `100 x 3 x 5` | back-off sets on separate lines |
| embedded exercise | `ITYW Raise x 10/ea` | prescription names its own movement |
| cardio duration | `20 minutes` + `HR 120-140` | steady-state cardio with HR zone |
| intervals | `30 seconds sprint, 2:30 minute walk - 5 rounds` | free-text interval prescription |
| assessment | TRAC Report block | soreness 1–5 (Push/Legs/Pull) + readiness 1–5; sums to a metric — not a lift, store as `type: assessment` |

## Parser guidance

- Split body into blocks on the `**X) ...**` label pattern; keep label letter for superset detection.
- Classify each exercise: `lift` (default), `cardio`, `assessment`, `mobility`.
- Never silently reinterpret ambiguous prescriptions (`115 x 3`): keep the raw
  text on the model and surface it verbatim in the UI.
- RIR annotations (`RIR 2-3`, `RIR 3`) are intensity notes, not set/rep data — store separately.
- Dedupe: same `WnDm` + date re-imported must not duplicate; update prescription, never clobber logged sets.
- "You missed your workout" emails: skip entirely.
