# The house ladder (draft, 22 Oct 2026 — for Josh's approval)

Rags to riches with your cat. The world map goes. You design your cat, watch the cutscene, and start in the
run-down terrace. Climb the ladder one house at a time with Beans, never skipping a rung.

## First run
1. Design your cat (cat builder).
2. Cutscene: rain on a run-down terrace at dusk; the door opens and *your* cat comes out to meet you.
3. Reveal: the camera rises through every rung, bottom to top, ending on the London mansion flat ("one day").
4. Back to the bottom rung, inside; the room tour starts.

## Rungs (city is fixed, round the world; its real weather is used — Josh, 22 Oct: "make it world wide places")
| # | House | City | Price (Beans) | Also needs | Opens room | Rough time to reach* |
|---|---|---|---|---|---|---|
| 1 | Run-down terrace (new art) | Puddlebury (made up) | start | — | Living room | day 1 |
| 2 | Houseboat | Amsterdam | 200 | the tutorial | Bedroom | day 1 (end of the tutorial) |
| 3 | Woodland cabin | Vancouver | 700 | level 5 + 4 house tasks | Kitchen | day 8 |
| 4 | Cottage | Queenstown, NZ | 1,500 | level 7 + 5 tasks | Garden | day 22 |
| 5 | New-build balcony flat | Tokyo | 2,500 | level 9 + 5 tasks | Study | day 43 |
| 6 | Mediterranean rooftop | Santorini | 3,800 | level 12 + 6 tasks | Attic | day 75 |
| 7 | Georgian townhouse | New York | 5,200 | level 15 + 6 tasks | — | day 120 |
| 8 | Mansion flat | London | 7,000 | level 18 + 7 tasks | — | day 170 |

\*A regular player who plays daily without buying Beans, as `PathPacingTests.theLadderSlowsAsItClimbs` simulates
it (HOUSECAT_LADDER=1 prints it: a light player reaches New York around day 160, a keen one London around day 163).
House tasks count feeds, games, days, stars, presents, strokes, new pieces and wallpapers since moving in
(`Tuning.Ladder.houseTasks`); feeding once a day sets the pace, so buying Beans can't skip the climb.

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
