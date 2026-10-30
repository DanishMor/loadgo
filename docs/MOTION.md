# Motion, haptics and sound (E9)

Principles are in `docs/BRAND_GUIDE.md` sections 6 to 8. Code: `lib/core/widgets/ds/motion.dart`, `haptics.dart`, `feedback_kit.dart`, `skeleton.dart`, `route_ribbon.dart`. Tests: `test/motion_budget_test.dart`, `test/ds_states_test.dart`, `test/ds_motion_haptics_test.dart`.

## Pieces
| Piece | Use | Reduced motion / LowEndMode |
|---|---|---|
| `DsMotion` fast 120 / normal 200 / slow 320 ms, `standard`, `emphasized` curves | every duration goes through `DsMotion.duration(context, d)` | zero |
| `SpringCurve.gentle` | sheets, cards, hero flights; at most one small overshoot (under 5%) | not used (durations are zero) |
| `FadeSlideIn` + `staggerDelay` | list items arriving; stagger capped at 6 steps | child shown at once |
| `PopIn` | a badge or tick that just changed | shown at once |
| `RouteRibbon(drawIn: true)` | pickup-to-drop line draws once (560 ms); pin and truck appear at the end | complete at once |
| `Skeleton` | gentle pulse (0.7 to 1) plus a highlight drifting over each box; one controller per tree | flat grey, still |
| `SuccessMoment` | tick in a soft circle, 420 ms pop, one success haptic, announced to TalkBack | shown at once, haptic kept |
| `DsHeroTag` | an element that flies between two screens | no Hero |

## Animation budget per screen (`MotionBudget`)
- Entrance motion finishes within **700 ms** (longest stagger 360 ms + slow 320 ms).
- At most **1** repeating animation per screen (a skeleton or, later, the driver radar pulse). `.repeat(` is allowed only in reviewed files; the budget test fails on a new one.
- A success moment stays under **600 ms**. No confetti, no loops.
- Painters repaint only when their inputs change (`shouldRepaint` compares every field).

## Haptic map (`Haptics.on(HapticEvent)`)
| Event | Strength | Examples |
|---|---|---|
| select | selection click | tab, chip, row |
| press | light | main button |
| confirm, success | medium | slide-to-confirm, bid sent, booking confirmed, delivered |
| error | light | form error, failed send (never a jolt) |
| sos | heavy | SOS only (existing delete / cancel prompts keep `Haptics.warning`) |
Touch feedback can be switched off in Settings (`Haptics.enabled`); then nothing vibrates.

## Sound
- `FeedbackKit` plays the phone's own short alert sound (no audio file, no plugin) only for events that need attention (new load, offer accepted).
- Silent in quiet hours (default 22:00 to 06:00, `QuietHours`), in LowEndMode and when touch feedback is off; the vibration still marks the event.
- Never loop a sound, except the SOS alarm.
