# HouseCat, cat virtual pet — build plan

Oct 16, 2026 · @Josh

The app is HouseCat (name chosen 17 October 2026; see Decisions). Companion to the sector deep dive of 15 October.

## The concept

The app is a cat virtual pet for iPhone (your own cat, built your way; the black cat is the mascot and the default) where every visit starts outside your own front door, in today's weather. You picked the home at the start (a London terrace, a mansion-block flat or a cottage). You tap the door, step inside, and your cat, with the personality you chose for it, comes to meet you, or doesn't, depending on that personality and how much it trusts you yet. It speaks in meows and text boxes, never a voice. Inside you feed it, fuss it, collect whatever it brought you, and furnish a living room and a bedroom; the cat uses what you place. More rooms open as you level up; looks are what you pay for. Between visits it lives on your Lock Screen. If you let it, it knows when you slept and how far you walked.

The arrival is the signature moment. It is 3–4 seconds, skippable, and it is the thing people will screen-record: "coming home to my cat" is a content format on its own, and it makes the home, not a stat bar, the thing you invest in.

**What this changes from the 15 October recommendation.** The home is now a real 2D scene, not a widget with a small room, so the engine is SpriteKit inside a SwiftUI shell rather than SwiftUI alone. Furniture carries cat behaviours (a sofa is somewhere to sit, a box somewhere to hide), which is the Neko Atsume mechanic and the reason decoration stays interesting. The cat has a chosen personality that changes its lines and its behaviour. Extra cats and looks are the premium hooks; rooms are earned. The health side (steps, sleep, workouts) is an optional, opt-in layer that only ever rewards. Nothing is ever lost: no death, no lost points; a missed day shows only as a sulk. Because time and budget are not the constraint, the **plan is the full scope with no staging and no dates: ten defined build steps with exit tests, then beta, submission and launch, shipping when it is finished**. Art, engine and store work run in parallel lanes; all art is made between us in Higgsfield, with no freelancers.

**Where it gets built.** The app is built in Claude Code on your Mac: Xcode, signing, device testing and TestFlight cannot run from this chat. This document is the spec it builds from; the last section is the kickoff prompt and the CLAUDE.md for the repo. The art is generated in Higgsfield from this chat and dropped into the repo's assets folder.

## Decisions, locked

Every parameter below is a decision, not an option, so the Claude Code session never has to guess. Three still need you: the public name, the art style sign-off from the Higgsfield tests, and the currency name (Beans or Pads; it is a one-line constant).

| Decision | Locked value | Why |
| --- | --- | --- |
| Name | **HouseCat** (chosen 17 October 2026). Bundle id `com.lostlambs.housecat`, product IDs `housecat.*`. Domains to register: housecatgame.com, housecatgame.app, housecat.homes (housecat.app and .com are taken). Manual UK IPO and EUIPO search in classes 9, 41 and 42 before anything is registered; file the logo with the word as a figurative mark, since the word alone is descriptive | Reads as a cat game at a glance; no App Store app, game or brand with the name was found in a web check on 17 October 2026 (the earlier shortlist of Soot, Pip, Inky, Sable and Jet all had collisions). Reserve the App Store name by creating the app record the day the developer account exists |
| Audience | Adults 25–40 first, cat-lovers, UK and US; children can play. Rated 4+, not in the Kids Category | Adult tone, adult pricing, no kids' UI; 4+ outside the Kids Category can sell IAP without a parental gate (Apple 1.3, 5.1.4) |
| Voice | No voice. Meows plus text boxes; the lines change with personality | Cheaper, funnier, localisable |
| Personality | Chosen at adoption from four: Aloof, Velcro (clingy), Gremlin (chaos), Loaf (sleepy). One free re-pick; each extra cat has its own | The user's own choice drives attachment; four line packs is tractable for v1 |
| Cats | **Full cat builder at adoption** (decided 17 Oct, Josh: "full like character customisation"): body and breed (shorthair or longhair with the slim-to-chunky weight slider, Persian, Siamese, Maine Coon, Sphynx), ears, tail, any coat colour, pattern, white markings, eye colour (odd eyes allowed), eye size, nose colour, whiskers, age; one-tap presets (Midnight, Ginger Tabby, Calico, Seal Point Siamese, British Blue…). Midnight, the black cat, is the mascot and the default. Every field editable again later for free. Every builder option is free at launch (decided 17 Oct); extra cats are the paid item. The player always names their own cat | Thousands of looks from white-painted part sets, pattern masks and a coat-colour shader; no painting per look |
| Homes | **8 exteriors at launch**: London terrace, mansion-block flat, cottage, Georgian townhouse, new-build flat with balcony, houseboat, Mediterranean rooftop flat, woodland cabin; 4 more in v1.1 (lighthouse, Japanese house, brownstone, treehouse). The house starts empty with one room open and a Bean allowance to furnish it; bedroom, kitchen, garden or balcony, study and attic unlock by level and cost Beans above the allowance, painted at launch and shown as silhouettes | "Full house or flat" with real choice; rooms are the level reward |
| Streak | **Visit streak, Duolingo-style**: a day counts when you arrive in the app or act from a widget; one free miss per rolling week; pause mode up to 14 days a quarter; milestones at 7, 30, 100, 365; longest streak kept | A widget-only day keeps the streak, which is the rule Duolingo found lifts D14 retention |
| Widgets | Streak number and cat mood on every size: small, medium with Feed/Pet/Visit buttons, Lock Screen circular and rectangular, StandBy | Duolingo's widget users retained about as well as push users; half hold a six-month streak |
| Perspective | Corner rooms in 2:1 isometric: two walls (left and right) meeting at the back, a 10 × 10 floor grid, wall height 5 cells, a door in one wall showing the next room; exterior is a façade with a door (changed 17 Oct from side-on) | Rooms read as places the cat moves through in depth; walls and floors are tiles plus a painted light map, so every wallpaper and floor works in every room |
| Art style | Painterly and colourful: the Mediterranean-pastel test (E) is the master palette direction, saturated and high-key, with jewel tones for dusk. The cat is slim-bodied with a round head and big amber eyes, slightly stylised (painted-animation, not cartoon mascot), both ears upright. The mascot is locked: the approved style test of 16 October (Higgsfield job 9e4615cc). No witch props, no red bow, no Ghibli palette | Chosen from nine style tests on 16 October; the slight stylisation is what lets the cat builder compose looks from parts |
| Animation | Cut-out puppet in SpriteKit (painted parts) animated in code; Kling loops as a week-1 test for hero moments | Painterly frames from AI video drift between clips; a puppet keeps one painting consistent |
| Higgsfield spend | Free rein. Plan 1,500–2,000 credits through launch (2,713 in hand; Ultra at $129/month or a 4,000-credit top-up at $211 if needed) | Credits are not the constraint; review time is, so generation runs in weekly batches with a one-glance acceptance rule |
| Weather | You search or tap a place on a painted world map; the pin sets the terrain (8 biomes), the sky's local time, the weather (WeatherKit by coordinate) and the season, which you can also fix to any of the four. Every room has a window showing the same time, season and weather. No device location permission at all | Your feature; it also removes the location prompt entirely and gives every home a different view |
| Engine | SwiftUI shell + SpriteKit scenes; WidgetKit; no Unity, no Flutter; iOS 26 minimum (iPadOS 26, watchOS 26, macOS 26) | Native, Claude Code handles Swift well, no ad SDKs |
| Revenue | No ads. Earned currency only in v1. Direct-priced sets, adopt-a-cat (offered in context by the stray), a season pass with a free and a paid track, Cat Club, starter pack, founders' pack, lifetime, and gifting of all of these. Full design in Monetisation | What the adult cosy titles do; keeps Apple 3.1.1 and the EU virtual-currency principles trivial |
| Currency name | **Beans** (toe beans), alternative Pads | A constant in code |
| Neglect | Never dies, never loses points, trust or items. A missed day: sulk and lines, no gift that day | Your rule; the most-praised design decision in the category |
| Social | Co-owning a cat is in v1 via CloudKit sharing (invite link, shared household, both owners' arrivals count). Groups of up to 12 friends by invite link, with profile cards (cat, home, level, streak) and read-only visits; cat-sitting and gifting happen inside a group. No public map | The Pengu growth loop |
| Health | Steps, sleep, workouts via HealthKit in v1; opt-in on day 3; rewards only | Your scope |
| Mini-games | Laser Pointer, Knock It Off and String Chase, all at launch; 5 plays a day | Small, cat-shaped, under 30 seconds |
| Platforms | iPhone first; the iPad dollhouse view, the Apple Watch complication and the Mac menu-bar cat are all in the full build (one universal purchase) | Apple-first |
| Sync | SwiftData with CloudKit private database from v1; no accounts | "Lost my cat" is a one-star review |
| Notifications | Local only, user-chosen times, pre-permission screen after the first feed | Apple 4.5.4 |
| Analytics | PostHog and Sentry | Needed for the day-60 decision |
| Company | Ship under Lost Lambs Ltd; Small Business Program in November | 15% flat |
| Launch | No date. Launch when every step passes its exit test: UK-only first, then worldwide. Launch event: a 14-day Housewarming gift track with a real end date; the Christmas event runs every December the app is live | Your call: everything in, date follows the work; event timers must be real (UK DMCC) |

## The session loop, moment by moment

A visit is under a minute. The arrival earns the open; feeding and the gift make it a daily habit; decorating is where the time (and money) goes.

1. **Outside.** Cold open on your home's exterior, sitting in its terrain (coast, city, mountain, forest and so on, from where you pinned it on the world map), at that place's time of day (dawn, day, dusk, night) in its real weather (rain, snow, fog, sun, overcast from WeatherKit). From trust tier 3 the cat is visible in the window. Shown only if the app was last in the foreground more than 60 minutes ago; otherwise you go straight inside. Auto-advances after 2.5 s or on tap.
2. **The door.** Tap the door; it opens and the camera pushes into the living room. 1.2 s.
3. **Greeting.** The cat is wherever its brain put it for this time of day (sofa, box, windowsill, or asleep in the bedroom, in which case it pads through the doorway). How it greets you is personality × trust: a Velcro cat runs to you from tier 1; an Aloof cat glances up until tier 3 and only ever walks; a Gremlin ambushes from behind the sofa; a Loaf lifts its head and goes back to sleep. A text box carries one line from that personality's pack ("Oh. It's you. Fine."). Three seconds at most, tap to skip. If it has not been fed today it walks to the bowl and looks back.
4. **The gift.** If a gift is pending, the cat drops it at your feet during the greeting. Tap to collect: it goes in the collection book and pays out Beans and XP.
5. **Care.** Bottom bar: Feed (once per day; a second tap gets "full"), Pet (first of the day gives XP, then diminishing; six taps in a row and the cat walks off, except a Velcro cat), Play (the mini-games, 5 plays a day), Nap (a 20-minute wind-down timer as a Live Activity; complete it for XP), Decorate, Shop, Book.
6. **Rooms.** Swipe between the living room and the bedroom (and later the kitchen, garden, study and attic). The cat moves between rooms on its own schedule; the bedroom is where it sleeps after bedtime.
7. **Decorate.** Grid overlay on the floor and wall rail; drag items from the inventory; rotate, flip, store. The cat reacts to a new item within 30 s (sniffs, then sits on it if it can). This is the loop that makes furniture worth buying.
8. **Leaving.** No leave button; closing the app is leaving. Back within the hour and you skip the exterior, so there is no arrival fatigue.
9. **Between visits.** The widget shows the cat's state (breakfast, loaf, box, windowsill, gift waiting, zoomies at 22:00, asleep after bedtime, sulking if yesterday was missed) with Feed and Pet buttons. Local notifications at the times you chose: breakfast, "brought you something", an optional evening nudge, written in the cat's personality.

The first visit is the onboarding, in four steps: a landing page (one line and Start) → cat creation (the builder opens on Midnight, the black cat, with the presets in a row above; then body, coat, markings, eyes, age, then name and personality, with the cat live on a sofa as you change it) → geography (the world map with search, then the season) → house selection and design (choose the house style, the first wallpaper and floor, place three starter items) → the first arrival. Seven screens, no paywall; the starter pack and Cat Club live in the shop from day one and are offered once at trust tier 1.

## Systems spec

Every number here is a tunable constant in one file (`Tuning.swift`); the Claude Code session implements the rule, you tune the value in beta.

**Two progressions, deliberately separate.** *Trust* belongs to each cat and only ever rises: it is the count of days that cat was fed. Tiers at 3, 7, 14, 30, 60 and 100 care days (Wary → Curious → Comfortable → Bonded → Devoted → Soulmate) change the greeting, the lines, how close it sits and which gifts it brings. *Level* belongs to you and unlocks rooms and catalogue tiers. Neither ever goes down.

**XP and levels.** Feed 10, first pet 5, each play 5 (max 25), gift collected 5, nap timer 10, arrival 5, furniture placed 3 (max 9), cat used new furniture 3 (max 6), steps ≥ 8,000 10, sleep ≥ 7 h 10, workout logged 10. Typical day 45–60 XP, ceiling 98. Level thresholds (cumulative): L2 100, L3 250, L4 450, L5 700, L6 1,000, L7 1,350, L8 1,750, L9 2,200, L10 2,700, L11 3,250, L12 3,850, then +650 per level. Rooms: kitchen at L3 (about day 5), garden or balcony at L6 (about day 18), study at L9 (about day 40), attic at L12 (about day 70). Each room also costs Beans to open (300 / 800 / 1,500 / 2,500), the Sims Mobile dual gate, so decorating and playing both matter.

**Personality.** Four archetypes, each a `Personality` value with four sliders (affection, energy, mischief, independence, 0–1) plus a line pack of about 120 lines keyed by event (greet, fed, full, petted, over-petted, gift, missed day, bedtime, zoomies, new furniture, level up, weather). Sliders drive the brain: greeting distance and speed, how often it seeks you out, favourite affordances (Loaf: sleep and sun; Gremlin: knock-off and hide; Velcro: sit near player; Aloof: perch and windowsill), play eagerness, and the chance of a reaction line. Chosen at adoption, one free re-pick, then changeable in settings.

**Cat builder.** Any cat can be built; Midnight, the black cat with amber eyes, is the mascot, the default and the first preset. Every field can be edited again later from the cat's profile for free. Fields, in builder order:
- **Body**: Shorthair or Longhair, each with the weight slider (slim to chunky: the puppet scales body and leg parts and swaps to the chunky body set past the midpoint), or a breed body: Persian, Siamese / Oriental, Maine Coon (drawn 1.15× larger), Sphynx (hairless: the coat colour is the skin colour). Breed bodies have no weight slider and keep their own ears and tail.
- **Ears** (Shorthair and Longhair): pointed (their own), rounded, folded (Scottish Fold), tufted (lynx tips), oriental (very large). **Tail**: long (their own) or bobtail.
- **Coat colour**: 16 named colours (black, smoke, blue, lilac, chocolate, cinnamon, fawn, brown, red, ginger, cream, white, silver, seal, golden, rose) or a free colour picker.
- **Pattern**: solid, mackerel tabby, classic tabby, spotted, tortoiseshell (patched), colourpoint, plus a pattern colour (the stripes, patches or points).
- **White markings**: none, mitts and boots, tuxedo, bicolour, van. Pattern and white combine (calico = tortoiseshell + bicolour; ragdoll = colourpoint + mitts).
- **Eyes**: one colour for both or odd eyes (amber, gold, copper, green, hazel, blue, aqua, lilac), eye size slider. **Nose**: pink, brick, black, grey, chocolate.
- **Whisker length** (slider), **age** (kitten that grows to adult at day 21, or adult), then **name** and personality. The player always types their cat's own name: required, up to 20 characters (Tuning), editable later from the profile, through the profanity filter because groups show it; three suggestions and a shuffle button from catbuilder.json. Preset names such as "Ginger Tabby" name the look, never the cat.
Presets are one tap and fully editable after: Midnight, Bombay, Tuxedo, Ginger Tabby, Silver Tabby, Brown Tabby, Tortoiseshell, Calico, British Blue, Russian Blue, Scottish Fold, Bengal, Oriental Havana, Seal Point Siamese, Himalayan, White Persian, Maine Coon, Ragdoll, Turkish Van, Smoke Longhair, Japanese Bobtail, Sphynx, Lilac Sphynx. The data (bodies, options, palettes, presets, file paths) is `assets/cat/custom/catbuilder.json`; the Swift `CatLook` model mirrors its `look_fields` and is what groups, co-owning and the stray share. Every option is free at launch (decided 17 Oct, Josh); the paid item is more cats (`housecat.cat.slot<n>`, one extra slot inside Cat Club). The `rare` flags in catbuilder.json are all off; switching some on later is how paid looks (`housecat.look.<name>`) would come back, with no new art. Outfits are layered over any look and never painted per cat: each body gets a one-off fit per view (`outfits.fit` in catbuilder.json, set by eye), and hats sit higher on tall ears. The builder is the second screen of onboarding and the model for extra cats.

**Coat recipe.** Every cat sprite in `assets/cat/custom/base` is painted white; the look is applied per pixel in a shader (a SpriteKit `SKShader` or a Core Image kernel), never by repainting. Per sprite there are optional masks of the same size: `masks/<pattern>/` (255 = pattern colour), `masks/white_<style>/` (255 = this fur stays white), `masks/features/` (red = iris of the eye on the image's left, green = the other eye, blue = nose leather; a side view has one eye, in red). With L the luminance of the white painting (0.3 R + 0.55 G + 0.15 B), all colours 0–1:
1. `shade = L^1.15`; `col = mix(coat, patternColour, patternMask)`; `fur = shade × col`.
2. Keep a little of the painted highlight: `k = 0.35 × clamp(lum(coat) / 0.7, 0.3, 1)`, `h = clamp((L − 0.85) / 0.15, 0, 1)`, `fur = mix(fur, painted, k × h)`.
3. White markings show the painting itself: `fur = mix(fur, painted, whiteMask)`.
4. Pink inner ears, paw pads and nose keep their painting (a pink-hue test, except within 7 px of the silhouette edge, which is always fur); irises are kept out of the fur.
5. Irises: `mix(.., eyeColour × clamp(L / 0.62, 0, 1.35), irisMask)`; nose: `mix(.., noseColour × clamp(L / 0.72, 0, 1.3), noseMask)`.
`tools/asset-pipeline/tint.py` is the reference implementation and `prevgrid.py` renders any look for comparison: port it and check the Swift output against it pixel for pixel on a few sprites. Swap ears and the bobtail take the pattern masks but never white markings. Pre-render the widget poses for the player's look into the App Group (the widget cannot run the shader).

**Age and time together.** Requested by Josh on 17 October. The cat's profile shows how long you have had it: "Together 43 days" (then "1 year, 12 days"), counted in streak days (the local calendar day at the wake time) from the adoption event in the save. A co-owned cat counts from its original adoption; an adopted stray counts from the day it came in. It also shows the cat's own age, which is its age at adoption plus the time since: a kitten starts at 12 weeks and becomes an adult at day 21 as before; an adult starts at 2 years unless the player sets an age (both in Tuning). Kitten-forever freezes the look, not the counter. The counter only ever rises: a missed day, a lost streak or pause mode never touch it, and it is not the streak. Gotcha day: on each adoption anniversary the cat gets its own line and the player a share card ("A year with Pip"), with a smaller line on each monthly anniversary in the first year. Milestones at 100 days, 1 year and each year after add a badge to the profile card. Lifetime stats beside it, all derived from the event log: days together, visits, meals, pets, gifts found, rooms opened, longest streak. Groups show the together-count on the profile card. Everything is derived from the event log and `DaySeed`; there is no stored counter.

**Cat brain.** A state machine per cat: idle, walk-to(target), sit, loaf, sleep, eat, play, greet, sulk, knock-off, perch. Targets are chosen from furniture affordances weighted by time of day and personality: morning eat then windowsill; midday sunbeam or perch; afternoon box or hide; evening sofa or near you; night bed. A new day's schedule is generated from a seed so the widget and the app agree without talking. Between rooms it walks through the doorway.

**Care and the visit streak.** The day starts at your wake time (default 06:00). The streak counts days with a visit: arriving in the app, or tapping Feed or Pet on a widget, so a widget-only day keeps it. One free miss per rolling week, a pause mode up to 14 days a quarter, and a lost streak restarts at 1 while the longest streak is kept and shown. Milestones at 7, 30, 100 and 365 days pay 100 / 300 / 1,000 / 3,000 Beans and a badge the cat wears for a day. Feeding is the daily care action (once a day; the bowl is the only must) and the main XP source; a visit without feeding keeps the streak but the cat says so. A missed day is a sulk and no gift, nothing else. The cat never dies and nothing is ever deducted.

**Gifts.** One per day when fed, dropped at a random time between an hour after feeding and 22:00 (next morning if fed late). Forty items in four rarities (common 60%, uncommon 28%, rare 10%, legendary 2%; each trust tier shifts 3 points from common to rare and legendary). Beans value 5 / 10 / 25 / 100. The gift is earned only, never bought, which keeps it outside every loot-box rule.

**Home and furniture.** Eight exteriors at launch, each a façade painted once at noon and colour-graded in code for time of day, with weather as particle and tint layers on top; four more in v1.1. **First arrival: the house is empty apart from the cat.** A housewarming allowance (Tuning: 150 Beans) buys the first three or four items from the Bean catalogue, and every item shows its price. One room (the living room) is open at the start; every further room needs a level AND Beans above the allowance (Tuning: bedroom L2 + 200, kitchen L3 + 300, garden or balcony L6 + 800, study L9 + 1,500, attic L12 + 2,500), tuned so the second room is earned around day 3–4 of normal play, never given. All six rooms are painted for launch so a locked room shows as a lit silhouette with its level and price. Floor grid 10 × 10 in a two-wall corner room (wall items hang on either wall); every item exists in two orientations, R (along the right wall) and L (along the left wall), so it can be rotated; items have a footprint (1–3 cells), a layer, and affordances: sit, sleep, hide, perch, scratch, eat, none. Five wallpapers and five floors per room, three of each free. The cat uses furniture by affordance; a room with nothing to sit on gets a cat loafing on the floor and a line about it. Catalogue at launch: 80 items (30 in the Bean catalogue, 50 across six paid sets), growing by about 20 a month, plus one season-pass set a season.

**Season pass.** Four-week seasons back to back, each with a theme, a name and its real end date on the pass screen. Pass points come from daily actions (Tuning: visit 10, feed 10, play 5, place furniture 5, mini-game 5, Sunday card 20; cap 60 a day) and fill 20 tiers on two parallel tracks. Free track: Beans, common furniture, a basic outfit. Paid track (`housecat.pass.<season>`, a non-consumable per season, $4.99 / £4.99): the season's exclusive set of 6–8 items, an outfit, a wallpaper and floor, and a cat look at tier 20; the exclusive set never returns to the shop. Buying mid-season unlocks every tier already earned at once (the Clash of Clans rule); unclaimed tiers can be claimed until the season ends; the last week shows the days left and nothing else. Cat Club includes the paid track. Every reward is fixed and visible from day one of the season: nothing random, no timers beyond the real end date.

**Groups.** Up to 12 members by invite link, built on a CloudKit share of a small group zone: each member's profile card is a few KB of JSON (cat parameters, house layout, level, streak, personality) rendered on the viewer's phone. Members visit each other's homes read-only, leave one paw print a day, and see each other's progress. Cat-sitting is a member feeding another member's cat for up to 14 days; gifts are gift links posted into the group. No public map, no free-text chat (nothing to moderate), no backend; a player can be in several groups.

**The stray.** A second cat appears at the window on a monthly cadence (DaySeed picks the day; weekly once three or more cats live in the house), and only once a second room is open and furnished; adopting needs a spare bed in a room beyond the first, so the sequence is level up, open a room, furnish it, meet the stray. The stray is always a visibly different cat from yours (another body, coat or eyes, usually one of the builder presets; its look is deterministic from the seed), your cat reacts to it, and if you don't adopt it comes back another month. Adoption is `housecat.cat.slot<n>`; the shop lists it plainly as well, the stray is just the offer in context.

**Economy.** Beans are earned (gifts, plays, daily arrival 10, level-ups 100) and spent on the standard catalogue (15 items at launch at 50–600 Beans, growing monthly) and room openings. Beans are never sold for cash in v1 and never expire. Paid items are priced in money, deterministic, never random.

**World map, search and seasons.** The geography step opens on a painted, zoomable world map with a search box: type any place (a city, a street, a postcode) and MapKit local search resolves it to coordinates, drops the pin and labels it ("Elephant and Castle, London"); or tap anywhere. The pin decides the terrain (8 biomes from a hand-painted mask under the map), the sky's local time (from the place's time zone), the weather, and which hemisphere's season applies. Season is editable: Auto (the real season for that hemisphere and date) or a fixed Spring, Summer, Autumn or Winter. With a fixed season the weather is simulated from that biome's seasonal weather table instead of WeatherKit, so a winter Lisbon gets cool rain, not July sun; real weather (WeatherKit by coordinate, no device location permission) drives the scene only on Auto. Location and season can be changed any time from the Home menu: season is free; moving home is free once, then 500 Beans (free for Cat Club). Co-owners' and friends' houses appear on the map from launch.

**Sky, season, weather and windows: one layered scene.** The exterior is composed in layers: a sky (gradient, sun and moon driven by the home's local time, continuous, in code); the terrain backdrop (painted once per biome per season at noon, colour-graded in code for dawn, day, dusk and night); the house (painted once at noon and graded the same way, with a lit-windows overlay at night and a snow-cap overlay in winter); and weather on top (rain, snow, fog, sun, overcast as particles and tints), with season particles (blossom, falling leaves, snow). The same layered scene is rendered through a mask into every room's window at the right scale, and the room's lighting takes a tint from the time of day, so every house and every room shows the real time, season and weather outside. During the Christmas event snow falls past the window whatever the season.

**Widgets, the Duolingo layer.** The streak number sits on every widget as a paw-print count, and the cat's pose answers one question at a glance: have you visited today? Before a visit: waiting by the door (06:00–12:00), looking out of the window (12:00–20:00), sitting by the door looking straight at you from 20:00 with "Still waiting." (the gentle version of Duo's midnight panic). After a visit: content, then loaf (10–14), box (14–18), sofa (18–22), zoomies (22–23), asleep (bedtime to wake). A waiting gift overrides with the cat holding it; a missed yesterday shows a sulk until you visit. Sizes: small (cat pose and streak), medium (cat in a room strip, streak, Feed / Pet / Visit buttons), Lock Screen circular (paw and number) and rectangular (cat, "Day 14 · fed"), StandBy (night room, streak small). Mechanics: timeline entries every 30 minutes (48 a day, inside the 40–70 refresh budget), poses rendered at build time from the puppet for every cat look, state computed from timestamps and the day seed so the app and the widget always agree, App Intents for the buttons (reloads are free and immediate), transitions under 2 s. The "add the widget" guide runs in onboarding and again at the day-3 trust moment, because the widget is the retention product.

**The home widget.** The medium and large widgets are a miniature of the player's own main room: their furniture, their cat in its current pose (asleep at night), and the window showing the real weather and time at the home's pin, with the temperature and the cat's one-line take. The room is rendered from the same layout data as the app when the timeline is built and cached per layout change, so the widget never draws live; Lock Screen and StandBy use crops of the same render. Because it is their room, every player's widget is different, which is what makes it worth showing.

**Live Activity.** The 20-minute Nap timer: start it at bedtime, the cat curls up on the Lock Screen, complete it for XP. Live Activities cannot start themselves in the background, so this is user-started.

**Health layer.** HealthKit read-only for steps, sleep and workouts; asked on day 3 with the benefit stated; each threshold pays XP and a line ("You ran. I watched from the window."). Never a penalty.

**Notifications.** Local only: breakfast at the chosen time, gift drop, optional evening nudge, all in the personality's voice; pre-permission screen after the first feed.

**Mini-games.** Laser Pointer: drag the dot for 30 s, the cat chases, catches score. Knock It Off: items slide onto a shelf, tap to knock them off before they settle, 20 s. Five plays a day across both; each pays 5 XP and 10–20 Beans. String Chase joins in v1.1.

**Data model (SwiftData, CloudKit-mirrored, App Group).** Household (homeType, city, settings), Room (type, wallpaper, floor, unlockedAt), PlacedItem (itemID, room, cell, rotation), Cat (name, variant, personality, careDays, lastFedAt, adoptedAt), InventoryItem, GiftEntry, Ledger (Beans, XP, level), Streak (lastCountedDay, graceUsedWeek, pausedUntil), HealthFlags per day, Entitlements (from RevenueCat). Household is the share root for co-owning in v1.1.

## Monetisation and the shop

Sell looks and cats for money, earn rooms with play, never sell randomness, and never sell a currency in v1. That is what the adult-facing cosy titles do, it keeps every Apple and UK rule trivial, and it is what the research says converts adults.

**What the field does** (App Store ladders read on 16 October 2026):

| App | Model | Space gating | Cheapest | Top SKU | Subscription | Signal |
| --- | --- | --- | --- | --- | --- | --- |
| [Cats & Soup](https://apps.apple.com/us/app/id1581431235) | Small packages and passes $0.99–$11.99, gems earn-or-buy, rewarded ads | Soft currency build chain | $0.99 | Daily Missions Pass $11.99 | None; 7-day/30-day passes | Top sellers are sub-$5 recurring packs; US \~$57K/week peak Sep 2025 ([Sensor Tower](https://sensortower.com/blog/2025-q3-unified-top-5-cat%20games-revenue-us-608810b928293296047965a0)) |
| [Neko Atsume 2](https://apps.apple.com/us/app/id6499131935) | Silver fish earned, gold fish 70/$0.99 to 400/$3.99 | Yard expansion with earned fish | $0.99 | 400 gold fish $3.99 | Cat's Club $0.99 / $1.99 / $2.99 a month (custom cats) | Reviewers praise the cheap sub and "you can save for what you want" |
| [Pocket Love](https://apps.apple.com/us/app/id1575412509) | Dogllar packs $0.99–$9.99, first-purchase doubling, $1.99 First Pack | Rooms cost Dogllars, no level gate | $0.99 | 1,600 Dogllars $9.99 | None | Cash-only clothing sets at $2.99 (Goth, Kawaii) |
| [Tsuki's Odyssey](https://apps.apple.com/us/app/id1564146071) | Carrots $0.99–$7.99; each pack carries an exclusive item | Homecoming expansion $14.99 one-off | $0.99 | Homecoming $14.99 | None | Permanent content sells at $14.99; no sub for adults |
| [Widgetable](https://apps.apple.com/us/app/id1641107226) | Diamonds 10 per $, Premium | Features by level and Premium | $0.99 | Premium annual $19.99 | $4.99/month, $1.99 intro, $19.99/year | Ad-gated pet food is its worst-reviewed feature |
| [My Cat](https://apps.apple.com/us/app/id1480397119) / Tamadog | Weekly VIP paywall after a 3-day trial | Everything behind VIP | $4.99/week | Boosters $79.99 | $4.99–$12.99 a week | The anti-pattern for adults; \~$43K/week US on volume |
| [Pocket Camp Complete](https://apps.apple.com/us/app/id6547834967) | Paid app $19.99, no IAP since Dec 2024 | Progression | $19.99 | — | None | "No paywalls" is the praise; F2P era grossed $255.7M by 2021 |
| The Sims Mobile | Rooms by level + Simoleons + timer, or SimCash to skip | Dual gate | — | — | — | The documented dual-path template for room gating |
| [Duolingo](https://www.sec.gov/Archives/edgar/data/0001562088/000162828026053299/q2fy26duolingo6-30x26share.htm) | Gems + Super | — | $0.99 | Super family $119.99/yr | Super $9.99–$12.99 | Subscriptions 86.5% of Q2 2026 revenue; gems 2.7% |

**Benchmarks for the model.** AppsFlyer 2026: casual D90 in-app ARPPU $7.26, ARPU $1.34, 38% of D60 IAP revenue lands on day 1 ([AppsFlyer](https://www.appsflyer.com/resources/reports/app-marketing-state-of-gaming/)). RevenueCat 2026, gaming subscriptions: download-to-paid 1.0% median, 2.3% top quartile, LTV per payer $11.22 at one year, median app $56/month at year one ([RevenueCat](https://www.revenuecat.com/state-of-subscription-apps)). GameAnalytics 2026: D1 22% median, 40% top decile ([GameAnalytics](https://www.gameanalytics.com/reports/2026-mobile-pc-gaming-benchmarks)). Adults' purchase regrets are "limited gameplay impact" (46%) and value mismatch (34%); what they want is loyalty bonuses (67%) and exclusive items (50%) (Mistplay/AppsFlyer survey, May 2025). Seasonal events lift December revenue 16–45% for well-planned games and over 90% of the top-100 grossing run one ([Sensor Tower, Dec 2025](https://sensortower.com/blog)); the pattern is a free advent track in the first fortnight and a paid seasonal package opening around 18–19 December.

**The design.**

| SKU (product ID) | USD / GBP | What it is | Rule it follows |
| --- | --- | --- | --- |
| Outfit (`housecat.outfit.<name>`) | $0.99 / £0.99 | One costume, non-consumable | Pocket Love / Cats & Soup entry price |
| Rare look (`housecat.look.<name>`): **not at launch** | — | Every cat-builder option is free at launch (decided 17 Oct). The SKU pattern and the `rare` flags in catbuilder.json stay so paid looks can be added later; do not create these products yet | Neko Atsume 2's custom cats are its praised premium |
| Furniture set (`housecat.set.<name>`) | $2.99 / £2.99 | 6–8 themed items + wallpaper + floor (Rainy London, Cottagecore, Midnight, Cosy Study, Riviera, Cabin) | Themed sets are the decor-game staple; "exclusive items" are what adults want |
| Room theme bundle (`housecat.bundle.<name>`) | $4.99 / £4.99 | A set + its outfit + 300 Beans | Bundle one step above the set |
| Adopt a cat (`housecat.cat.slot<n>`) | $4.99 / £4.99 | A second (third, fourth) cat built in the cat builder with its own personality | The best premium hook in the category |
| Starter pack (`housecat.starter`) | $1.99 / £1.99 | Once only: 1 outfit + 1 set + 500 Beans, shown from day 1, no countdown | Homescapes' top seller is its $1.99 starter |
| Launch pack (`housecat.season.housewarming`) | $4.99 / £4.99 | The Housewarming pack: fireplace, record player, string lights, a welcome mat, 300 Beans; on sale for the first 31 days after launch with the real end date shown. After that, seasonal content rides the season pass (the December season is the Christmas one every year) | Cats & Soup's Season Exclusive Package; the date must be true (UK DMCC) |
| Cat Club monthly (`housecat.club.monthly`) | $2.99 / £2.99 | Monthly exclusive outfit, an extra cat slot included, +20% Beans on everything earned, exclusive widget styles, rooms at half the Bean cost, early access to seasonal sets | Neko Atsume 2's $0.99–$2.99 club is the only cosy sub reviewers like; currency grants inside a sub are allowed (Apple 3.1.2(a)) |
| Cat Club yearly (`housecat.club.yearly`) | $19.99 / £19.99, 7-day trial | Same, the anchor price | Widgetable and Focus Friend anchor at $19.99 |
| Forever Home (`housecat.lifetime`) | $39.99 / £39.99 | Cat Club forever, non-consumable | Focus Friend's $29.99 lifetime; Tsuki's $14.99 permanent content |
| Season pass (housecat.pass.\<season>), a non-renewing subscription | $4.99 / £4.99 a season | Paid track of a four-week season: the exclusive 6–8 item set, an outfit, a wallpaper and floor, a cat look at tier 20; 20 tiers earned by daily actions on a free and a paid track; buying mid-season unlocks earned tiers at once; included in Cat Club. Sold as a non-renewing subscription with the end date stated before purchase (Apple's own type for a battle pass); everything earned is kept forever; the entitlement is stored in the iCloud save because StoreKit does not restore non-renewing subscriptions | Clash of Clans Gold Pass pattern; every reward fixed and visible, nothing random; the end date is real (UK DMCC) |
| Founders' pack (housecat.founders) | $29.99 / £29.99 | Numbered plaque on the house, one exclusive outfit, Cat Club forever. On sale from launch day for 30 days, then retired for good with the end date shown. It cannot be sold in TestFlight (beta purchases are free and do not carry over), so TestFlight testers receive a free offer code for it at launch | Early adopters pay for permanence; the plaque is social proof in groups later; Forever Home takes over at $39.99 when the window closes |
| Gifts (housecat.gift.club.yearly, housecat.gift.cat, housecat.gift.set.\<name>, housecat.gift.pass), consumables | Same price as the item | A Gift button on Cat Club yearly, adoptions, sets and the season pass: the giver buys the gift SKU (a consumable, so it can be bought many times) and receives a one-time CloudKit share link; the recipient opens it once, the gift is marked redeemed on acceptance, and their cat delivers the wrapped item at the next arrival. The item is keyed to the recipient's iCloud save so it restores on their devices; never re-giftable. Family Sharing on for the subscription. A Gift tab in the shop, never a prompt | Apple allows gifting in-app purchases (3.1.1); Finch sells a one-year gift; pet apps are gifted at Christmas and birthdays |

No weekly plan, no premium currency, no paid randomness, no countdown that is not an event's real end. Beans stay earn-only and never expire; if a purchasable currency is ever added (v1.2 at the earliest, only if people ask for à la carte), it is priced in money next to every item, never random, never expiring. Rooms are earned (level + Beans); Cat Club discounts them but cannot skip the level. All paid cosmetics are also visible in the catalogue with their real-money price, and the standard catalogue keeps growing for free, so nobody feels the "limited gameplay impact" regret.

**Year-one model** (50,000 installs; gross before Apple's 15%; assumptions from the benchmarks above, with the subscription and pack mix lifting ARPPU above the IAP-only $7.26):

|  | Low | Base | High |
| --- | --- | --- | --- |
| Install-to-payer | 1.5% | 3% | 5% |
| Payers | 750 | 1,500 | 2,500 |
| ARPPU (year) | $7 | $12 | $18 |
| Gross | \~$5.3K | \~$18K | \~$45K |
| Net of 15% | \~$4.5K | \~$15K | \~$38K |

Installs are the weakest input, as in the deep dive; the model doubles with installs. The December event and the Cat Club yearly are the two levers that move ARPPU.

**Compliance, built in** (details and citations in the rules notes):

- Apple 3.1.1: Restore Purchases button, Beans never expire, no odds disclosure needed because nothing random is sold; 3.1.2: the paywall shows name, duration, full local renewal price, trial length and post-trial price, with Terms of Use and Privacy Policy links in the app and in App Store Connect ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)).
- Small Business Program: a flat 15% on everything, including year-one subscriptions; enrol in November so the rate applies from launch ([Apple](https://developer.apple.com/app-store/small-business-program/)).
- UK DMCC unfair-practice rules (in force 6 April 2025): no fake urgency or resetting timers, no nagging, no exhortations aimed at children; the Christmas pack's end date is real and shown; real-money prices sit next to every item ([CMA guidance](https://www.gov.uk/government/publications/unfair-commercial-practices-cma207)).
- UK Age Appropriate Design Code: assume in scope (a 4+ game a UK company publishes); neutral purchase buttons, no nudges, no behavioural data, a one-page conformance note in the repo ([ICO](https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/childrens-information/childrens-code-guidance-and-resources/)).
- UK subscription-contract rules land in January 2027: Apple's renewal reminders and online cancellation cover most of it; keep a visible "manage subscription" link.
- Refunds: Apple decides; add the in-app refund request sheet; RevenueCat's refund-control webhooks answer consumption requests.
- App Review notes: no accounts; the IAP list; "the daily gift is earned only and never purchasable"; where Restore, Manage Subscription, Privacy and Terms live; the Christmas event's real end date.

## v1 content list

Everything below ships on 7 December. Counts are the floor; the catalogue grows monthly after launch.

| Asset | Count at launch | Notes |
| --- | --- | --- |
| Cat puppet parts | 8 bodies (4 standard + Persian, Siamese, Maine Coon, Sphynx) × 4 views × 11 parts, painted white, + 4 swap ear shapes, a bobtail, expression heads, resting poses (with ear and tail variants for the standard bodies), 9 pattern and white-marking masks and iris and nose masks per sprite, + kitten scale | The coat recipe tints them in code to any colour, pattern and eye colour; see ASSETS.md "Cat builder" |
| Cat animations (code-driven) | 14 + 4 personality greetings | Idle, blink, walk, trot, run, sit, loaf, sleep, eat, greet/headbutt, sulk, knock-off, zoomies, perch |
| Exteriors | 8 house styles painted once at noon + a lit-windows night overlay + a winter snow-cap overlay + a door-open frame each = 32 images; time of day by colour grading in code | Terrace, mansion-block flat, cottage, Georgian townhouse, new-build flat, houseboat, Mediterranean rooftop, cabin; painted on transparent ground so a house sits on any terrain |
| Interiors | 6 rooms × 3 layers + 5 wallpapers + 5 floors each | Living room and bedroom free; kitchen, garden/balcony, study, attic painted and level-locked |
| Furniture | 80 items | 30 in the Bean catalogue, 50 across 6 paid sets; every item tagged with affordances and a cat-on-it pose where it has one |
| Outfits | 16 | 6 earnable, 9 paid singles, 1 Christmas |
| Gifts | 60 icons | 4 rarities; a line for each |
| Text lines | \~600 | 4 personalities × \~150 events; spreadsheet → JSON |
| Widget renders | 10 states × 3 sizes × every cat look | Generated by a build script from the puppet, not painted |
| Christmas pack | 12 decor items, 1 outfit, snow overlay, advent gift set (24) | Event 1 Dec–6 Jan |
| Sounds | 16 | Meows × 6 moods, purr, door, rain, snow hush, gift chime, level-up, streak milestone, three room tones |
| Onboarding | 7 screens | Home, cat builder, personality + name, arrival, feed, widget guide, reminders |
| App Store | 6 screenshots, 1 preview video, icon | The arrival sequence is the preview |

Added with the world map and seasons: one painted, zoomable world map with its biome mask, and 8 biome backdrops × 4 seasons = 32 paintings at noon, colour-graded in code for time of day, drawn behind the house and through every room's window, with weather and season particles on top. About 300 credits. The sky, sun, moon and grading are code, not paintings.

## Art pipeline

Paint once, animate in code. A painterly cat cannot be generated frame by frame without drifting, so the cat is a cut-out puppet of painted parts that SpriteKit moves, and every environment is a painting with layers.

**Style bible (one page, in the repo as `docs/STYLE.md`).** Reference: the approved mascot image (Higgsfield job 9e4615cc, 16 October) and the Mediterranean-pastel room around it. Rules: visible brush texture; high-key saturated colour with violet-blue simplified shadows; bold warm key light with a cool fill; rim light on the black fur so the silhouette always reads; amber eyes with a white catchlight; slim body, round head a touch large for it, big eyes, both ears upright; palette per home (terrace: cobalt and terracotta; Mediterranean: mint, peach and turquoise; cottage: moss and honey; dusk everywhere: jewel tones); no Ghibli greens-and-cream, no red bow, no white sclera almond eyes, no crescent mark, no witch props. Black-fur rule: never pure black; a dark navy-brown base with a lit edge, so it survives dark mode and a 16 px widget.

**Higgsfield, step by step** (costs read from your account on 15 October; you have 2,713 credits on Plus):

1. Style tests: three one-off cat-in-room images with Nano Banana Pro, 2 credits each. You pick one; that image becomes the Reference Element every later generation is anchored to.
2. Character sheet: the `character-sheet` workflow with the chosen image as reference, turnaround (side, three-quarter, back) and a six-expression sheet (2 credits). Save as a Reference Element.
3. Puppet parts: generate the cat in a neutral standing pose per view, then isolate parts (body, head, ears, eyes, front legs, back legs, tail) with `remove_background` and a quick mask pass; paint-over the joins so parts overlap cleanly. 20–40 credits with retries.
4. Variants: four recolours of the same parts (void, tuxedo, smoke, white-locket) by prompt from the reference; kitten proportions as a separate head and body scale in code, not new art.
5. Exteriors: 8 house styles painted once at noon on transparent ground from one prompt skeleton ("same house, same angle, same light"), then a door-open variant, a lit-windows overlay and a snow-cap overlay each. Terrain: 8 biomes × 4 seasons at noon. Time of day is colour grading in code, never a repaint. About 300 credits for both.
6. Interiors: each room as three layers (back wall, floor, props) at 3× iPhone width; wallpapers and floors as tiles. About 40 credits.
7. Furniture: a fixed template (same angle, same light, transparent background via `remove_background`, same scale marker) and batch prompts; 40 items at 2–6 credits each with retries, about 150 credits. Review in batches of ten against the style bible before accepting.
8. Outfits and gifts: outfits as overlay parts on the head/body; 40 gift icons from one prompt skeleton. About 100 credits.
9. Christmas pack: 10 items, 1 outfit, snow overlay. About 40 credits.
10. Week-1 test only: two Kling 3.0 loops (10 credits per 5 s, same still as start and end frame) of the greeting run and the zoomies, to see whether a hero clip can sit alongside the puppet. If it jars, drop it.

Budget with free rein: about 1,500–2,000 credits through launch (cat sets and overlays \~200; 32 exteriors plus door frames \~250; 6 rooms with wallpapers and floors \~300; 80 furniture \~450; 16 outfits \~120; 60 gifts \~150; Christmas \~80; Kling tests and iteration \~300). The 2,713 in hand cover it; a 4,000-credit top-up ($211) or a month of Ultra ($129, 3,000 credits) is the backstop. The real limit is review: about 500 accepted assets at roughly a minute each plus retries is 15–20 hours of your eyes across weeks 1–4, so generation runs in weekly batches with a one-glance acceptance rule against the style bible. Terms: you own the outputs and commercial use is allowed on paid plans; Higgsfield may train on non-Enterprise content ([Higgsfield help centre](https://higgsfield.ai/creator-hub/help-center/account-and-privacy/who-owns-my-generations-and-can-i-use-them-commercially)). AutoSprite (2 credits) gets one test on the walk cycle; the puppet is the plan.

**Sprite specs.** Masters are delivered as PNG with alpha in `assets/` (see docs/ASSETS.md and `assets/manifest.json`); the build downsamples them into @2x/@3x atlases per room and per cat. The cat is about half the sofa's height in-room; rooms render large. Naming follows `assets/manifest.json` (`cat_<set>_<view>_<part>.png`, `furn_<room>_<item>_<R|L>.png`, `ext_<home>.png`, `terr_<biome>_<season>.png`, `widget_<frame>[_wide].png`); widget renders at 2× the small widget size.

**Consistency rules.** One Reference Element for the cat, one per home; identical prompt skeletons with only the variable swapped; same seed where the model allows; a "no" list in every prompt (bow, collar, crescent, hat); accept nothing that fails the style bible on the first glance; keep a `docs/art-log.md` of accepted generations with their IDs.

## Tech stack and architecture

One Xcode workspace, three targets, one pure-Swift package that holds every rule, so the game logic is testable without a simulator and the widget and the app can never disagree.

| Layer | Choice | Why |
| --- | --- | --- |
| Language, UI | Swift 6, SwiftUI shell (navigation, shop, onboarding, settings) | Native, fast to iterate with Claude Code |
| Scenes | SpriteKit via `SpriteView`: `ExteriorScene`, `RoomScene`; `CatNode` puppet with `SKAction`-driven bones; `FurnitureNode` with affordances; particle emitters for rain and snow | 2D scene graph, 60 fps, no engine import |
| Game logic | `HouseCatCore` Swift package: models, tuning, cat brain, economy, levels, day seed, widget state; no UIKit, 100% unit-tested | Deterministic from timestamps; shared by app and widget |
| Persistence | SwiftData, CloudKit private database mirroring, App Group container `group.<bundle>.soot` | Backup without accounts; widget reads the same store |
| Widgets | WidgetKit, App Intents (Feed, Pet), ActivityKit (Nap timer), StandBy | iOS 26 minimum |
| Weather | WeatherKit by the home's coordinate (capability on the App ID); MapKit \`MKLocalSearch\` for place search and time zone; no CoreLocation; SpriteKit colour grading (per-layer tint and a lookup curve) for time of day | 500K calls/month free with the developer account |
| Health | HealthKit read: steps, sleep analysis, workouts | Opt-in day 3 |
| Purchases | StoreKit 2 through RevenueCat; entitlements `club`, `lifetime`; non-consumables for packs and cats | Free to $2.5K MTR; refund-control webhooks |
| Notifications | `UNUserNotificationCenter` local only | No server |
| Analytics, crashes | PostHog iOS SDK, Sentry | Free tiers |
| Project | xcodegen `project.yml`, SwiftLint, swift-format | Claude Code edits YAML, not pbxproj |
| Build loop | XcodeBuildMCP (`claude mcp add XcodeBuildMCP -- npx -y xcodebuildmcp@latest mcp`) for build, run, screenshot on simulator and device | Closes the fix loop without you in Xcode |
| CI | GitHub Actions: build + `HouseCatCore` tests on every push; TestFlight upload by `xcodebuild -exportArchive` on tag | Keeps a green build for TestFlight week |

**Repo layout.**

```
soot/
  CLAUDE.md                 rules for the Claude Code session
  docs/SPEC.md              this document, exported as Markdown
  docs/STYLE.md             the art bible
  docs/ARCHITECTURE.md      kept current by Claude Code
  project.yml               xcodegen
  Packages/HouseCatCore/        Sources, Tests (tuning, brain, economy, levels, day seed, widget state)
  App/                      SwiftUI shell, scenes, shop, onboarding
  Widgets/                  WidgetKit extension, intents, Live Activity
  Assets/                   atlases by room and cat; exteriors; widgets
  Content/                  lines.json, catalogue.json, gifts.json, personalities.json
```

**Rules that keep it fast.** All state derives from timestamps plus a daily seed, never from timers. The widget never touches the network. No account, no login screen. Placeholder art (coloured shapes with the right footprints) from day one, so the engine never waits for a painting. Every tunable in `Tuning.swift`. Every rule has a test in `HouseCatCore` before it has a screen. Two Claude Code sessions in parallel when useful: one in the main checkout on the app, one in a git worktree on the widget target ([worktrees](https://code.claude.com/docs/en/worktrees.md)).

**App Review defences.** 4.2: a real game with scenes, mini-games, an interactive widget and a Live Activity. 3.1.1: Restore button, no currency expiry. 3.1.2: full paywall disclosures. 4.5.4: local notifications, opt-in, pre-permission. 5.1.1: privacy policy URL, honest privacy labels (no data collected beyond analytics with no identifiers), in-app refund sheet. 2.3.8: no "for kids" wording. HealthKit and WeatherKit usage strings written in plain English.

## Build phases

Full scope, no staging, no dates. The work is ten build steps, then a public beta, then submission and launch; each step has a defined deliverable and an exit test, and the next step starts when the test passes. The art lane runs alongside every step. From step 5 onward, a build goes to a friends-and-family TestFlight at the end of each step, so the loop is being used long before the public beta. It ships when it is finished.

| Step | Build (Claude Code) | Art (Higgsfield) | Exit test |
| --- | --- | --- | --- |
| 0 Setup | Apple Developer enrolment (D-U-N-S first), repo + xcodegen skeleton, XcodeBuildMCP, first build on your iPhone | Style, master plate, turnaround and expression sheet (done) | App icon on your phone; name shortlist searched at the registers |
| 1 Arrival | `HouseCatCore` models, tuning and tests; `ExteriorScene` → door → `RoomScene`; cat puppet with idle, walk, sit, sleep; colour-grading stub; placeholder furniture grid | Puppet parts × 3 views (short fur); living room layers; terrace at noon | The arrival runs on device with the real cat walking to the door; tests green |
| 2 Cat builder and care | The full builder (every field, presets, live preview), the coat-recipe shader, personalities and the lines engine, feed, pet, trust, XP and levels, gifts, book, Beans, the cat's profile with time together, age and lifetime stats | The cat-builder art (`assets/cat/custom`), catbuilder.json, the coat-recipe shader checked against tint.py | Build any cat (every preset matches presetsheet.py) and it walks; a full day loop is playable; on a test clock the together count rises through a missed day and a lost streak |
| 3 Rooms and furniture | Decorate mode (grid, inventory, rotate), six rooms and room swipe, affordances, catalogue, room unlocks by level and Beans | Bedroom, kitchen, garden, study, attic layers; furniture batch 1 (30) | The cat uses furniture in all six rooms |
| 4 Map, seasons, windows | World map with MapKit search and the biome mask; season logic (Auto or fixed, seasonal weather tables); the layered exterior with grading; the window view in every room | World map painting and mask; terrain batch 1 (summer and winter, 16) | Pin anywhere and every window shows it; grading reads right at four times of day |
| 5 Weather, houses, widgets | WeatherKit and the seasonal simulation, weather and season particles; eight houses with night and snow overlays; widgets in every size with the streak, App Intents, notifications | Houses 1–8 with overlays; terrain batch 2 (spring and autumn, 16) | Widget correct over 48 h on device; weather matches the real place; first friends build |
| 6 Depth | Nap Live Activity, CloudKit private mirroring, three mini-games, sound and haptics | Furniture batch 2 (30), outfits 16 | Games pay Beans; data survives delete-and-reinstall |
| 7 Money and onboarding | RevenueCat SKUs and entitlements, shop, Cat Club paywall, starter and packs, restore, refund sheet; the four-step onboarding | Gifts 60; Housewarming pack; widget render script | Sandbox purchases work end to end; onboarding to first feed under four minutes |
| 8 Co-owning | CloudKit sharing of the household, invite link, merge rules, both owners' arrivals and widgets; friends' houses on the map | Share cards | Two phones co-own one cat for three days without a conflict |
| 9 Health and content | HealthKit steps, sleep and workouts; 600 lines loaded; furniture tagging QA; `events.json` with the Housewarming track | Furniture batch 3 (20); Christmas pack drafted | Every line and item in; lines read right in all four personalities |
| 10 Polish | Accessibility, privacy labels, analytics, performance, the integration matrix (builder × rooms × houses × seasons), App Store assets, review notes | Preview video; polish on the 20 most-seen assets | No crash in three days; 60 fps on an iPhone 12 |
| Public beta | 50 testers including 10 co-owning pairs; balance pass; fixes; Small Business Program application | — | D7 ≥ 35% among testers; trial start ≥ 6% |
| Submit and launch | Release candidate, one to three review cycles, UK-only availability first, then worldwide; day-one hotfix build ready | Launch posts | Live in every territory with the Housewarming track running |
| After launch | Regular content drops; the annual black-cat hooks | 20 furniture a month | — |

A step that fails its exit test is extended until it passes; nothing is cut and nothing is skipped. Steps 2–4 can run in parallel Claude Code sessions (app in the main checkout, map and widgets in worktrees) once step 1 is green.

**Steps added after the decisions of 17 October**, each run the same way (build, unit tests, exit test, then the next): **Empty house and allowance** (exit: a fresh install arrives in an empty living room with 150 Beans, the second room cannot be opened until level 2 and 200 Beans). **Season pass** (exit: a full four-week season runs on a test clock, both tracks claim correctly, a mid-season purchase unlocks the earned tiers, the end date shows on the pass). **Groups** (exit: two phones in a group see each other's cards and homes within a minute; a paw print lands). **Cat-sitting and gifting** (exit: a sitter keeps a streak through a three-day test; a gift link delivers a wrapped item at the next arrival). **The stray** (exit: it never appears before the gate, its look is deterministic, adoption works and restores). **Home widget, wallpaper, share cards, Sunday card** (exit: each exports a correct image or clip for the current home state on the connected iPhone). **Siri and Shortcuts** (exit: "Feed Pip" (the cat's own name) feeds and counts as the day's visit). **Watch and iPad** (exit: the complication shows the streak within 15 minutes of a visit; the dollhouse renders every room). **Mac menu-bar cat** (exit: feeding from the Mac counts on the iPhone within a minute). **Founders' pack** and **localisation** sit with the store and launch steps.

## Order of work

1. Setup → 2. Arrival → 3. Cat builder and care → 4. Rooms and furniture → 5. Map, seasons, windows → 6. Weather, houses, widgets → 7. Depth → 8. Money and onboarding → 9. Co-owning → 10. Health and content → 11. Polish → Public beta → Submit → UK soft launch → Worldwide launch.

Each arrow is an exit test from the table above. The art lane runs under every step; friends-and-family builds go out from step 6; the beta decides nothing about scope, only about tuning.

## Launch sequence and annual hooks

The launch is a sequence, not a date. Marketing starts once the app is in beta; the annual hooks below are real-world dates the content calendar will use whenever the app is live.

| Stage | What happens |
| --- | --- |
| Friends-and-family builds | From step 6, a build at the end of every step; the arrival, builder, rooms and widgets in real use |
| Public TestFlight | 50 testers including 10 co-owning pairs; tuning only |
| Submission | Housewarming track and pack included; Small Business Program approved beforehand |
| UK-only availability | Two weeks of real retention data before the world sees it |
| Worldwide launch | Housewarming pack on sale for 31 days with the real end date shown |

| Annual hook | What ships |
| --- | --- |
| Friday the 13th (next: 13 Aug 2027) | "Lucky" update: a 13-item set, a superstition line pack |
| Black Cat Appreciation Day, 17 Aug | Free gift drop; press and creator push |
| National Black Cat Day (UK, Cats Protection), 27 Oct | The charity tie-in, if agreed; adoption spotlight |
| Halloween, 31 Oct | Seasonal pack (pumpkins and fog on the house; no witch props on the cat) |
| Christmas, 1 Dec – 6 Jan | Advent gifts, snow past every window, the Christmas pack |

## Costs and hours

Cash to launch is under £200 because every asset is made in Higgsfield on the plan you already pay for.

| Item | Cost | Note |
| --- | --- | --- |
| Apple Developer Program | $99/year (shown in GBP at enrolment) | Needed for TestFlight, WeatherKit, CloudKit |
| Higgsfield | £0–£170 | 1,500–2,000 credits through launch; 2,713 in hand; a 4,000-credit top-up is $211 or Ultra $129/month if iteration runs long |
| Domain | \~£12/year | sootapp.com or the chosen name's .app |
| RevenueCat, PostHog, Sentry, CloudKit, WeatherKit | £0 | Free tiers cover launch volumes |
| XcodeBuildMCP, xcodegen, SwiftLint | £0 | Open source |
| GitHub Actions | £0 | Free minutes for a private repo at this size |
| Total to launch | **\~£100–150** | Excluding your Higgsfield subscription |

No time budget. The effort splits roughly 60% directing Claude Code and reviewing builds, 25% art generation and review (about 700 accepted assets), 15% content (lines, catalogue, store copy). Parallel Claude Code sessions (app in the main checkout, map and widgets in worktrees) shorten the calendar, not the work.

## Risks and mitigations

Ranked by how likely each is to cost the December date or the first month's reviews.

1. **Painterly consistency across 40 furniture items and 4 cat variants.** Mitigation: one Reference Element, one template, batches of ten reviewed against the style bible; the puppet means the cat is painted once; locked rooms ship as silhouettes so art never blocks a build.
2. **The arrival becomes friction.** Mitigation: 60-minute rule, 2.5 s auto-advance, tap to skip everywhere, widget actions bypass it; measure arrival-skip rate in PostHog from the first beta build.
3. **SpriteKit puppet animation looks stiff.** Mitigation: week-1 exit test on device; secondary motion (tail, ears, blink) is where the life is; the Kling hero-clip test is the fallback for the greeting only.
4. **Scope creep in decoration.** Mitigation: 40 items and two rooms are the v1 cap; every new idea goes to the v1.1 list in the doc, not the build.
5. **App Review.** 4.2 is covered by the game depth; 3.1.1/3.1.2 by the shop rules; the ten-day buffer between TestFlight and 1 December absorbs two rejections.
6. **WidgetKit staleness.** Mitigation: deterministic state from timestamps and the day seed; 30-minute entries; intents for instant updates; a three-day device test in phase 3.
7. **CloudKit sync surprises.** Mitigation: private-database mirroring only in v1; delete-and-reinstall test; co-owning waits for v1.1.
8. **Adults bounce off anything that feels like a kids' game.** Mitigation: the deadpan line packs, painterly art, adult pricing, no energy systems, no timers, no weekly plans; the Mistplay survey's regrets (limited impact, value mismatch) are designed out by keeping the free catalogue growing.
9. **Christmas timing.** Mitigation: the event is data-driven (dates in `Content/events.json`) so it ships inside the launch build with a real end date; if review slips past 7 December the event still runs to 6 January.
10. **Name.** Mitigation: trade-mark search this weekend; the bundle ID and repo stay "soot" whatever the public name becomes.
11. **Your attention across ventures.** Mitigation: the phase exit tests are weekly and binary; a missed exit test moves stretch items, never the date.

12) **A long solo build.** The risk is drift and fatigue, not any single feature. Mitigation: a build on a real phone at the end of every step, friends using it from step 6, the concept frozen at this spec, and every new idea logged for the post-launch content drops rather than the build.

## Start here: step 0, in order

- [x] Style locked, master plate, turnaround and expression sheet generated (done 16 Oct; IDs in `docs/art-log.md`).
- [ ] Name is HouseCat: manual search at [UK IPO](https://www.gov.uk/search-for-trademark), EUIPO and [USPTO](https://tmsearch.uspto.gov/) in classes 9, 41 and 42; register housecatgame.com, housecatgame.app and housecat.homes; brief a figurative mark (logo + word).
- [ ] Apple Developer Program enrolment as Lost Lambs Ltd (submitted 17 Oct; waiting for approval, App Store Connect opens after it). Turn on WeatherKit and CloudKit on the App ID once the account is live.
- [ ] On the Mac: Xcode 26 (installed 17 Oct), Claude Code per [the setup page](https://code.claude.com/docs/en/setup.md), Homebrew `xcodegen`, `swiftlint` and `git-lfs`; make `Cat App/housecat` the private repo `housecat` (GitHub account ready) with Git LFS tracking `*.png`, `*.jpg`, `*.wav` and `*.npy` before the first commit (2.2 GB of masters, inside the free 10 GiB LFS storage; JSON and docs stay plain git); CLAUDE.md and docs/ are already in the folder.
- [ ] Add XcodeBuildMCP in the repo (`claude mcp add XcodeBuildMCP -- npx -y xcodebuildmcp@latest mcp`); plug in the iPhone, trust the Mac, enable Developer Mode on the phone.
- [ ] Open Claude Code in the repo and paste the kickoff prompt below. Milestone 0 is the foundations that need no art (project, rules engine with tests, content files, store layer); Milestone 1 waits for the confirmed assets.
- [x] Higgsfield: puppet parts in four views, every room, furniture item, surface, exterior, terrain, outfit, gift, icon and widget frame; delivered to `assets/` (17 Oct, see docs/ASSETS.md).
- [ ] RevenueCat project and the App Store Connect app record (codename for now); create the SKUs from the Monetisation table.
- [ ] Step 1 starts: the arrival on device.

## The Claude Code kickoff

Two files go in the repo before the first session: `CLAUDE.md` (sent to you as a file; it loads at the start of every session) and `docs/SPEC.md` (this document). The first message to Claude Code is the prompt below. It asks for milestone 1 only; each later milestone is a new prompt that names the phase from the Build phases table and its exit test.

```markdown
You are building HouseCat, a cat virtual pet for iPhone (a black-cat mascot, any cat in the builder), with iPad, Apple Watch and Mac menu-bar companions. Read CLAUDE.md, docs/SPEC.md, docs/ASSETS.md, docs/CONTENT.md and docs/STYLE.md in full before doing anything. SPEC.md is the product spec and every number in it is a locked decision; CLAUDE.md holds the architecture and store rules that override anything older in SPEC.md. Ask me only when the spec is silent or contradictory.

MILESTONE 0: the foundations that need no art.

Deliver, in this order, committing after each step:
1. project.yml for xcodegen with these targets: App (SwiftUI + SpriteKit, bundle id com.lostlambs.housecat), Widgets (WidgetKit extension, App Group group.com.lostlambs.housecat), Watch (embedded watchOS app), Mac (native macOS menu-bar app using MenuBarExtra, App Sandbox on), and the local Swift packages Packages/HouseCatCore (pure Swift, no Apple frameworks), HouseCatModels (SwiftData), HouseCatUI (shared SwiftUI views), HouseCatGame (SpriteKit). Minimum OS per CLAUDE.md. Generate the project, build it with XcodeBuildMCP, install the App on my connected iPhone. Tell me exactly what to click if signing needs me.
2. HouseCatCore: the append-only event-log save (events, snapshot, compaction, derived state); Tuning.swift holding every constant from SPEC.md; DaySeed; the trusted-time rules; the level curve; trust tiers; streak rules (grace miss, pause mode, milestones); the Bean economy; room gating (housewarming allowance, level AND Beans); gift rarity weights by trust tier; season-pass points and tiers on both tracks; daily, weekly and achievement objectives; the behaviour table (mood x weather x personality -> affordance and pose); the widget state. Swift Testing for every rule, including the day-reset at wake time, a backwards clock jump, a mid-season pass purchase, and a cat with no furniture to sit on. Tests must pass before you move on.
3. Content as data: generate Content/lines.json, catalogue.json, gifts.json, outfits.json, objectives.json, seasons.json and minigames.json from docs/CONTENT.md, plus a test that validates every id referenced exists, every line is 70 characters or fewer and British English, and every catalogue item has a footprint, layer, affordances, capacity, motion and pool. Hand me the generated files to read before you build anything on them.
4. The store layer behind an EntitlementService protocol: RevenueCat on StoreKit 2, a .storekit configuration with every launch product in SPEC.md (no rare looks; correct types: non-consumables, the Cat Club subscription group with the yearly introductory offer, non-renewing season passes, consumable gifts), verified-only transactions, entitlements held in memory and mirrored to the Keychain, never in the synced store. Tests with SKTestSession.
5. docs/ARCHITECTURE.md describing the targets, the event log, how state flows from HouseCatCore to scenes and widgets, and the CloudKit sharing design (raw CloudKit zone, one-time URL participants) for the later social milestone.

Acceptance: the app installs and launches on my iPhone showing a placeholder room; `swift test` in every package is green; the content files exist and validate; the StoreKit configuration loads in the simulator and a sandbox purchase of an outfit unlocks it after a relaunch.

Then MILESTONE 1, only once I confirm the art is in Assets/: the arrival on device with the real cat puppet and the real living room from docs/ASSETS.md.

Working rules: HouseCatCore owns all rules and never imports UIKit or SpriteKit; scenes and widgets read state and never compute it; every constant lives in Tuning.swift; no network except RevenueCat, CloudKit, WeatherKit, PostHog and Sentry; no third-party dependency beyond those three without asking; edit project.yml and run xcodegen, never the .pbxproj; SwiftFormat on every edit; keep CLAUDE.md and ARCHITECTURE.md current as you go. When you finish, list what is placeholder, what is real, the test count, and the three riskiest things about milestone 1.
```

## The 20 ideas: decisions and specs

Numbered as in the chat of 17 October. The decisions are Josh's; the spec column is what gets built, and everything accepted is in the full build as its own step with an exit test (see Build phases). None of it changes the core loop.

| # | Idea | Moves | Decision | Spec |
| --- | --- | --- | --- | --- |
| 1 | **Custom Lock Screen wallpaper of your home** | Traffic | In, customisable | One tap exports a wallpaper of your house, terrain, weather and cat. The player picks the view (exterior or any room), the time of day (now, dawn, noon, dusk, night), the season, the cat's pose, and whether the streak, a caption and the small app mark appear (mark on by default). Free, unlimited |
| 2 | **The home-model widget** | Traffic, retention | In, as a model of your own home | The medium and large widgets are a miniature of your actual main room: your furniture, your cat in its current pose (asleep at night), and the window showing the real weather and time at your home's pin, with the temperature and the cat's one-line take. Lock Screen and StandBy use the same render. Because it is your room, every widget is different |
| 3 | **Web cat builder** | Traffic | In as a small website feature, low priority | After the app ships, the marketing site gets the builder in the browser: make a cat, download a sticker, open the app with it by link |
| 4 | **Referral that pays in looks** | Traffic | In. A marketplace is not in v1 (note below the table) | Invite a friend; when they reach day 3 you both unlock an outfit that is never sold |
| 5 | **24-hour time-lapse export** | — | Dropped | Not built (Josh, 17 October). The wallpaper (1) and the share cards (6, 15) cover the shareable-content role |
| 6 | **Streak milestone share cards** | Traffic | In; the streak is the retention spine | Cards at 7, 30, 100 and 365 days (cat, home, number, that day's weather). The other half is the cat's reaction to a missed day: sulk pose and grumpy lines in the app and on every widget until you visit, warming back over the next three visits |
| 7 | **Groups** | Retention | Replaces the public map | A group of up to 12 by invite link (a CloudKit share: no backend, no moderation queue). Each member has a profile card: cat, home, level, streak, personality. Members visit each other's homes read-only, leave one paw print a day and see progress. Cat-sitting (12) and gifting (18) live inside the group; a player can be in several groups |
| 8 | **Black Cat Day and Halloween tentpole** | Traffic, revenue | In; nothing to build until the event system exists | Every October: an events.json entry, the Cats Protection tie-in, an adoption spotlight, the October season pass themed to it, a featuring nomination |
| 9 | **App Store featuring** | Traffic | In | Submit Featuring nominations in App Store Connect ahead of launch and before every event, and publish an In-App Event for each season. Lead with the world map, the windows and the native tech (WidgetKit, StandBy, Live Activities, WeatherKit, Watch). Needs an app preview video and localised screenshots |
| 10 | **Localisation** | Traffic, revenue | In | Japanese, Korean, German, Spanish, Brazilian Portuguese: lines.json, store page, keywords, In-App Events. After launch, one language at a time |
| 11 | **Mac menu-bar cat** | Traffic | In | Your cat sits in the Mac menu bar beside the clock and walks along it once an hour. A click opens your real main room with Feed, Pet and Open house; feeding from the Mac counts as the day's visit; same iCloud save; free with the iPhone app (universal purchase) |
| 12 | **Cat-sitting** | Retention | In | A group member keeps your streak alive by feeding your cat for up to 14 days; they see your home and your cat thanks them |
| 13 | **Apple Watch and iPad** | Retention | In, both | Watch: the streak and the cat's state as a complication, Feed from the wrist; iPad: the whole house as a dollhouse view |
| 14 | **Siri and Shortcuts** | Retention | In | "Feed Pip" (the cat's own name); a Shortcut that checks in when the alarm goes off; the cat sleeps when the Sleep Focus turns on |
| 15 | **Weekly "your cat's week" card** | Retention | In | Sunday card: days visited, gifts found, what the weather did, one line from the cat; shareable |
| 16 | **A stray at the window** | Revenue | In, gated by the house | The stray appears once a month (weekly with three or more cats) and only once the house has grown: first after a second room is open and furnished, and adopting needs a spare bed in a room beyond the first. Always visibly different (odd-eyed, longhair, kitten); if not adopted it comes back another month. Adoption is `housecat.cat.slot<n>` |
| 17 | **Season pass** | Revenue | In; replaces the monthly limited set | Four-week seasons with the real end date shown; 20 tiers on a free track and a paid track, earned with pass points from daily actions. Free: Beans, common furniture, a basic outfit. Paid ($4.99 / £4.99 a season): an exclusive themed set of 6–8 items, an outfit, a wallpaper and floor, a cat look at tier 20. Buying mid-season unlocks the tiers already earned. Cat Club includes every pass. Rewards fixed and visible from day one; nothing random |
| 18 | **Gift Cat Club** | Revenue | In, expanded | Gift buttons on Cat Club yearly, adoptions and furniture sets: the giver buys a gift SKU and gets a gift link (a CloudKit record, no accounts); the recipient opens it and their cat delivers the wrapped item at the next arrival. Family Sharing on for the subscription. No gift prompts, just a Gift tab in the shop |
| 19 | **Founders' pack** | Revenue | In | On sale from the first public TestFlight until 30 days after worldwide launch, then retired for good with the end date shown: a numbered plaque on the house, one exclusive outfit, Cat Club forever at $29.99 / £29.99. TestFlight testers get the plaque free |
| 20 | **Print of your home** | — | Dropped | Not built |

**Marketplace (asked on idea 4): not in v1.** A player-to-player market needs a backend, fraud and moderation work, and Apple only allows real-money sales through its own in-app purchase, so items could only trade for Beans. A Bean market would let people pick up paid sets without paying, which undercuts the shop, and tradeable item values pull the app towards the loot-box and DMCC rules we have designed around. What keeps the good part: inside a group, duplicate earned gifts can be swapped one for one (earned items only, never paid ones), and duplicate gifts can be sold back to the game for Beans. If the app ever has a backend, a curated marketplace of player-made wallpapers is the version worth building.
