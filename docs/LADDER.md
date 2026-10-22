# The house ladder (draft, 22 Oct 2026 — for Josh's approval)

Rags to riches with your cat. The world map goes. You design your cat, watch the cutscene, and start in the
run-down terrace. Climb the ladder one house at a time with Beans, never skipping a rung.

## First run
1. Design your cat (cat builder).
2. Cutscene: rain on a run-down terrace at dusk; the door opens and *your* cat comes out to meet you.
3. Reveal: the camera rises through every rung, bottom to top, ending on the London mansion flat ("one day").
4. Back to the bottom rung, inside; the room tour starts.

## Rungs (city is fixed; its real weather is used)
| # | House | City | Price (Beans) | Also needs | Opens room | Rough time to reach* |
|---|---|---|---|---|---|---|
| 1 | Run-down terrace (new art) | Manchester | start | — | Living room | day 1 |
| 2 | Houseboat | Amsterdam | 1,500 | level 3 + 3 house tasks | Bedroom | day 3–4 |
| 3 | Woodland cabin | Oslo | 4,000 | level 5 + 4 tasks | Kitchen | week 2 |
| 4 | Cottage | Cotswolds | 9,000 | level 8 + 5 tasks | Garden | week 3–4 |
| 5 | New-build balcony flat | Toronto | 18,000 | level 11 + 5 tasks | Study | week 6 |
| 6 | Mediterranean rooftop | Barcelona | 32,000 | level 14 + 6 tasks | Attic | month 2–3 |
| 7 | Georgian townhouse | Bath | 55,000 | level 17 + 6 tasks | — | month 4 |
| 8 | Mansion flat | London | 90,000 | level 20 + 7 tasks | — | month 6 |

\*For a player who plays daily without buying Beans. These prices are placeholders, to be tuned against
real Bean income in `PathPacingTests` before they're locked in.

## Rules
- Rooms now open with the house, not with the player's level. Furniture and rooms carry up the ladder.
- The current house's tasks (decorate X, play Y, keep a streak…) show in the goal tracker and must be done
  before the next house is for sale. The same rule as Clash of Clans town halls: each rung costs more and takes longer.
- No moving back down and no skipping. The real weather follows the current house's city; the season control
  moves to Settings.
- Old saves: an existing player keeps their furniture. They are put on the rung that matches the rooms they
  already have, so nobody loses a room.

## Build order (one Xcode build at a time)
1. Ladder model + prices (core, unit tests).
2. Remove the world map; a city per rung; weather from it.
3. Cat design first in onboarding.
4. Cutscene + ladder reveal.
5. "Your next home" screen (price, tasks, Buy), no skipping.
6. Tasks per house + pacing tests.
7. Full build, UI tests, check on the iPad.

New art needed: the run-down terrace (outside, in the rain), and one city each for the other houses, so each
home pack shrinks to a single city's four seasons.
