# HouseCat — content brief — the words, names and rules the code generates from

Everything here is data, not code: Claude Code produces `Content/lines.json`, `catalogue.json`, `gifts.json`, `outfits.json`, `objectives.json`, `seasons.json` and `minigames.json` from this brief, Josh reviews them like art (one glance, accept or regenerate), and the app reads them. Nothing in this file is hard-coded anywhere.

## 1. Lines (`lines.json`)

Schema per entry: `{ "context": "...", "personality": "aloof|velcro|gremlin|loaf", "variants": ["...", "...", "..."], "meow": "short|long|chirp|trill|purr|grumble|silent" }`. Three variants per context per personality; four personalities; about 60 contexts → about 720 lines.

Wants (19 Oct 2026): `want.bed`, `want.seat`, `want.scratcher`, `want.hideaway`, `want.perch`, `want.window`, `want.toy` (the home has nothing of that kind; the cat says what it would love, a wish in its own voice, never a demand and never a mention of buying) and `want.met` (it has just got one).

Voice guides (the whole personality lives here):
- **Aloof**: dry, short, deadpan, judges you fondly. Rarely an exclamation mark. "Oh. You." / "I suppose you may sit."
- **Velcro**: warm, clingy, breathless, wants to be near you, asks you to stay. "You're back you're back you're back." / "Don't go. The sofa is big enough."
- **Gremlin**: chaotic, mischievous, plotting, threatens the furniture, loves 3 a.m. "The vase had it coming." / "I have plans for that shelf."
- **Loaf**: sleepy, cosy, slow, food-first, content, half-sentences. "Warm. Good. Later." / "Bowl. Then nap. Then bowl."

Rules: British English; 70 characters maximum (the text box holds two lines); no emoji; no baby talk; never meta ("I'm an app", "tap here"); never mention money, buying, the shop, the pass or the streak as a demand (UK DMCC: no exhortation, no guilt) — the cat can be sulky, never a salesman; adults-first humour, clean; no real brands, characters or people; weather, season and time words only in their contexts; placeholders `{cat}`, `{item}`, `{weather}`, `{temp}`, `{place}`, `{streak}`, `{sitter}`, `{together}` ("43 days", "a year").

Contexts (each with the condition the code checks):
- Arrival: first ever; first of the day; second visit same day; late night (after 23:00); early (before 06:00); from the Mac; from the Watch.
- After a missed day: 1 day; 2–6 days; 7 or more (the sulk lines; warming over the next three visits: sulky → thawing → fine).
- Feeding: fed; already fed today; unfed morning nag; unfed evening nag; fed by a sitter; fed by a co-owner.
- Petting: first of the day; repeated; too many (cat walks off).
- Play: start; win; lose; daily plays used up.
- Gift found: common; uncommon; rare; legendary; no gift today (missed yesterday).
- Weather (8): sun, cloud, rain, storm, snow, fog, wind, heat. Season (4). Time (4): dawn, day, dusk, night. One line each, plus the Sunday card's weather summary.
- Home: furniture placed with an affordance the cat likes; placed with none; item removed; room unlocked; wallpaper changed; empty room (nothing to sit on).
- Progress: level up; trust tier reached (six tiers); streak milestone (7, 30, 100, 365); streak at risk in the evening (one gentle line, no countdown); pause mode on; pause mode off.
- Time together (SPEC.md "Age and time together"): monthly gotcha day in the first year; yearly gotcha day; 100 days together; kitten grows up (day 21). Warm, never a demand; the share-card caption for the yearly one ("A year with {cat}").
- Social: sitter present; co-owner arrived; group visitor looking in; paw print received; gift received (wrapped delivery line); gift sent.
- The stray: appears; your cat's reaction (by personality); stray leaves; stray adopted (both cats).
- Objectives and seasons: daily objective done; weekly done; achievement unlocked; pass tier claimed; season ends in a week (factual, dated); new season starts.
- Outfits: put on (by item category: hat, scarf, glasses, jumper); taken off.
- Health rewards: steps reached; sleep reached; workout logged.
- Behaviour: nap start; nap end; window-watching; sunbeam; zoomies; scratching; hiding; ten generic idle lines.
- Events: Black Cat Day; Halloween (no witch jokes); Christmas; New Year; the Housewarming launch event.

## 2. Furniture (`catalogue.json`)

Fields: `id`, `name` (24 characters max), `set`, `room`, `footprint` (w×d cells), `layer` (floor|wall), `affordances[]` (sit, sleep, hide, perch, scratch, eat, watch, bat, none), `capacity` (cats at once), `motion` (see ASSETS.md §4), `pool` (free|beans|set|pass-free|pass-paid|housewarming|founders|club), `level`, `beans` or `sku`, `description` (90 characters, one dry line), `catPose` (how the cat rests on or by it), optional `catUse` (on|inside|front|floor|beside: where the cat goes to use it; left out, on what it sits, sleeps or perches on, on flat things at floor level, in front of wall things, else beside) and, for `inside`, `rim` (per facing, the front rim left to right as sprite fractions from the top left: the cat in it is drawn behind what lies below). Naming: plain British names ("Sagging sofa", "Radiator seat"); at most one pun in ten; no brand parodies.

Launch catalogue, 80 items (pool and level set by the tiers in ASSETS.md §5):
- **Living room (16)**: sagging sofa (sit, sleep; 2 cats), armchair (sit), wool rug (sleep), floor lamp (glow), bookshelf (perch), coffee table (perch), cardboard box (hide), scratching post (scratch), window-seat cushion (sit, watch), radiator (sleep, glow), record player (spin), houseplant (sway, bat), fireplace (frames; the rug in front becomes a sleep spot), cat tree (perch, sleep), wall clock (spin hand), picture frame (wall).
- **Bedroom (14)**: double bed (sleep; 2 cats), bedside table (perch), wardrobe (hide), laundry basket (hide), reading lamp (glow), curtains (sway), chest of drawers (perch), cat bed (sleep), slippers (bat), mirror (the cat judges itself), dressing-gown hook (wall), cat hammock (sleep), alarm clock (bat), bedroom rug (sleep).
- **Kitchen (14)**: food bowl (eat; the one item every home starts with), water fountain (eat, frames), kitchen table (perch), kitchen chair (sit), fridge (glow when open), kettle (frames, steam), herb shelf (sway), bread bin (hide), fruit bowl (bat), cooker (none), cat flap (none; the way to the garden), radio (none; music note particles), door mat (sleep), sink (perch).
- **Garden or balcony (12)**: bench (sit; 2 cats), sunbeam spot (sleep; sun only), bird feeder (watch, frames), flower pots (sway), watering can (none), deck chair (sit), shed (hide), fence (perch), pond (watch, frames), outdoor string lights (glow), hammock (sleep), washing line (sway).
- **Study (12)**: desk (perch, sits on the keyboard), office chair (sit, spin), laptop (perch, "helping"), tall bookshelf (perch), paper tray (sleep), desk lamp (glow), globe (spin), filing cabinet (hide), printer (perch, frames), noticeboard (wall), mug (bat), window blind (sway).
- **Attic (12)**: old trunk (hide), dusty armchair (sit), skylight beam (sleep; sun only), stacked boxes (perch, hide), rocking horse (sway), dressmaker's dummy (none), telescope (watch), rolled rug (sleep), antique lamp (glow), cobweb corner (bat; Gremlin's favourite), suitcase (hide), old radio (none).

No alcohol anywhere: the champagne bucket and the mulled-wine mugs were painted but are left out (Josh, 18 Oct; `excluded` in catalogue.json). Season-pass sets (8 items a season, Midwinter 7; 3 on the free track, the rest on the paid track): **Housewarming** (moving boxes, tea chest, paint tins, step ladder, fairy lights, picnic blanket, takeaway bag, scented candle); **Midwinter** (knitted blanket, log basket, wreath, snow globe, fir tree, sledge, hot-water bottle); **First Light** (seed trays, bird box, tulip pot, peg bag, picnic hamper, butterfly jar, wellies, daffodil jug).

Housewarming launch pack (5): deluxe fireplace, deluxe record player, string lights, welcome mat, framed house portrait. Founders: the numbered plaque (wall; brass, slate, oak finishes).

## 3. Gifts (`gifts.json`)

60 items the cat brings: toys (12), treats (12), oddities (12: a sock, a bottle cap, a leaf, a very dead toy mouse), keepsakes (12), seasonal (12, only in their months). Rarities by count: 30 common, 17 uncommon, 9 rare, 4 legendary (draw weights 60 / 28 / 10 / 2, shifting 3 points up per trust tier). Each: `id`, `name`, `rarity`, `description` (one line, the cat's angle), `months[]` for seasonal. Duplicates sell back for Beans (5 / 15 / 40 / 100) or swap one-for-one in a group.

## 4. Outfits (`outfits.json`)

35 at launch (12 added 18 Oct for the launch shop: beret, strawberry hat, frog hat, sun hat, nightcap, chef's hat, bowler hat, cowboy hat, bunny ears (March and April), heart sunglasses, pearl necklace, bell collar; all sold for 450 Beans). The first 23: head and neck (14): beanie, flat cap, bucket hat, party hat, blue bandana, mustard scarf, green bow tie (never red), round glasses, sunglasses, flower crown, pumpkin hat (October), Santa hat (December pass), antlers (December), small crown (the top of the Housewarming pass). Body (9): fisherman's jumper, raincoat, hoodie, Christmas jumper, pyjamas, cardigan, Hawaiian shirt, life vest, skeleton onesie (October). The body garments are painted for every body's resting poses and walking torso (19 Oct) and sold like the rest. Pools: 25 sold for 450 Beans (`Tuning.Beans.outfit`), 4 earned (streak 30, streak 100, referral, launch event), 6 on the season pass (3 on the free track, 3 on the paid); no founders' outfit (no founders' pack any more, Josh, 18 Oct). Fields: `id`, `name`, `slot` (head|neck|body), `views[]`, `pool`, `sku` or `earnedBy`.

## 5. Objectives (`objectives.json`)

The Clash of Clans achievement loop, paying Beans and pass points (the path also XP, outfits and pieces of furniture), never anything else.
- Daily (3 drawn by DaySeed from a pool of 20): e.g. pet twice, feed before 09:00, play one mini-game, move or place one item, visit from a widget, check the weather (tap the window), put the cat to bed (nap), say hello on the Mac. Reward: 10–20 Beans + 5 pass points each.
- Weekly (3 from a pool of 12): e.g. visit all seven days, find five gifts, win three mini-games, place five items, open one room, send a paw print. Reward: 50–100 Beans + 20 pass points.
- Achievements (60 one-offs, ladders of three where sensible): care (10), home (12), social (8), streak (6), collection (10), explore (6: change the season, move home, try every room), seasons (8). Reward 25–500 Beans by difficulty. Fields: `id`, `name`, `text`, `metric`, `target`, `beans`, `passPoints`, `ladder`.
- 21 more achievements (19 Oct 2026, Josh: more to complete), 81 in all: ladders for naps (5/20/100), the pieces the cat uses (5/15/40), furnished rooms (1/3/6, five pieces or more), games played (10/100/500), three-star games (5/25/100), visit days (30/100/365), other cats' homes on the map (3/7), ten outfits, and level 30.
- The path (`path`, 19 Oct 2026, Josh: "i have been playing for 5 mins and dont know what to do"): three chapters of goals in order, each step teaching one thing and paying Beans and XP (a little pass XP on top), each chapter paying its own reward and opening the next. Moving in, the first hour: feed, stroke, three pieces in the living room (the new home's bowl and box do not count; it gives the rug), a game, a nap, level 2, the bedroom (it comes with the nightcap), the nightcap on, the home on the map; 100 Beans and the scratching post. Getting to know you, the first week: a second day, a present, three days of meals, two pieces in the bedroom, three stars, three pieces the cat tries out (it gives the plant), the kitchen, four different presents; 150 Beans, the beret and the lamp. Making it home, the first month: a wallpaper and a floor, level 6, two outfits, 15 pieces, 14 days of meals, a star in 20 games, 20 visit days, and two optional ones (three other cats' homes once the map opens them at level 5, three pass rewards while a season is on); 300 Beans and the picture. The path's outfits are never a season's (a pass would be selling what players already have). Fields: chapter `id`, `name`, `when`, `done` (said when it is done), `beans`, `xp`, `outfit`, `item`, `steps`; step `id`, `name`, `text`, `metric`, `target`, `room` (room_pieces), `screen` (screen_seen), `beans`, `xp`, `passPoints`, `outfit`, `item`, `optional`. `{cat}` is the cat's name.

## 6. Mini-games (`minigames.json`)

Five plays a day across the four; each play 5 XP (25 a day cap), stars pay Beans 2 / 4 / 6, 5 pass points a play. Every game is 20 s on the clock (Josh, 19 Oct: "very basic right now and too long"), about half a minute from the tap to the result; one thumb, no fail state that upsets the cat. Each scores points: a hit scores 1, and 1 more for every two hits in a row before it, up to 5 a hit; a miss, or three seconds without a hit, starts the combo again. Every game has golden targets (three times the points) and one catnip (the zoomies: double points for 4 s), and gets a little quicker as it goes. The stars are set so steady play earns three and careless play one or two (`MiniGameTests.starsRewardPlayingWell`).
- **Laser Pointer**: drag the dot; the cat chases it, and close up it crouches and pounces. Hold the dot still and it lands on it: a catch (twice the points when it lands right on it); flick it away and it lands on nothing. The dot turns golden twice a game; catnip lies on the floor for a while. Stars at 30 / 80 / 150.
- **Knock It Off**: the cat walks the mantel; tap and it swipes off whatever is in front of its nose. Things keep arriving (faster as the game goes on, six at most); each hit quickens the cat a little; a swipe at nothing rests it a moment. Golden things now and then, and a catnip fish (a longer reach). Stars at 25 / 60 / 120.
- **String Chase**: draw a string with your finger; the cat runs along it. Three sparkles at a time appear a run away from the cat and fade after a few seconds (sooner as it goes); collect them quickly to keep the combo. Two golden sparkles and a catnip fish a game. Stars at 5 / 25 / 70.
- **Hide and Seek** (added 19 Oct, Josh's pick of three new ideas): five of the room's things along the floor (a box, the armchair, the laundry basket, the sofa, the plant, the cat tree); the cat hides behind one while your eyes are shut, then peeks out now and then (ears over the top, or its face round the side). Tap where it is: twice the points within 1.1 s; a wrong guess breaks the combo and the cat gives itself away. Its peeks get shorter and further apart and, from a third of the way in, other places rustle as decoys. A golden bell two rounds a game; a catnip fish lies by one place for a while, and with the zoomies the cat can't keep still. Left unfound for 4 s it comes out by itself. Stars at 5 / 40 / 100.
Personality changes the cat's chase speed and reaction lines only.

## 7. Seasons (`seasons.json`)

Four-week seasons back to back, always one running (`SeasonSchedule` runs an earlier season again in a slot with none of its own): `id`, `name`, `theme`, `startAt`, `endAt` (real, shown), `freeTrack[20]`, `paidTrack[30]`, `sku`; `launchAt` is the launch day the events count from. Written by `tools/content/build_seasons.py`. First four: Black Cat (5 Oct–1 Nov 2026, before the launch, pieces from the Bean shop), Housewarming (the launch season), Midwinter, First Light. December is always the Christmas season, Midwinter: it runs 1–28 December every year, the following seasons run four weeks each, and the one that meets 1 December runs a day longer (two in a leap year) (Josh, 18 Oct; `SeasonCalendar` in HouseCatCore). The Santa hat and antlers are Midwinter's outfits.

**2027, to paint** (dates from `SeasonCalendar`; each needs 8 pieces of furniture, a wallpaper and a floor, `pass_<id>_<item>`, then its tracks in `seasons.json` and a `housecat.pass.<id>` product; no alcohol, no witches):

| Dates | Season | Pieces |
|---|---|---|
| 26 Jan – 22 Feb | Snug | knitted pouffe, cocoa tray, book stack, sausage-dog draught excluder, patchwork quilt, tea cosy, slipper rack, paper lantern |
| 23 Feb – 22 Mar | Kite Weather | kite, pinwheel pot, wind chime, weather vane, umbrella stand, barometer, jigsaw table, paper boats |
| 23 Mar – 19 Apr | Blossom | blossom branch jug, painted-egg basket, nest box, seed packets, potted cherry tree, bunting, robin feeder, spring wreath |
| 20 Apr – 17 May | Allotment | raised bed, scarecrow, wheelbarrow, veg trug, compost bin, potting bench, sweet-pea wigwam, tomato planter |
| 18 May – 14 Jun | Seaside | striped deckchair, bucket and spade, windbreak, sandcastle, lighthouse lamp, shell jar, rock pool, ice-cream cart |
| 15 Jun – 12 Jul | Midsummer | paddling pool, desk fan, lolly freezer, sun lounger, parasol, lemonade jug, strawberry punnet, fairy-light jar |
| 13 Jul – 9 Aug | Camping | tent, campfire ring, camp lantern, rucksack, map table, sleeping bag, postcard rack, binoculars |
| 10 Aug – 6 Sep | Harvest | hay bale, sunflower pot, jam jars, apple crate, owl box, harvest basket, plum tree, cider-free apple press |
| 7 Sep – 4 Oct | Back to School | satchel, chalkboard, pencil pot, school bell, lunchbox, conker string, leaf basket, tidy desk caddy |
| 5 Oct – 1 Nov | Spooky | pumpkin lanterns, bat bunting, cauldron of sweets, toffee-apple stand, candle stack, cobweb hammock, ghost sheet, black-cat lantern |
| 2 Nov – 30 Nov | Firelight | sparkler bucket, toasting fork and marshmallows, conker bowl, lantern-walk lantern, fleece blanket, woolly hat stand, hot-chocolate flask, firework poster |
| 1 Dec – 28 Dec | Midwinter 2027 (the Christmas pack's 12: stockings, gingerbread house, nutcracker, present pile, pudding, sleigh bed, candy canes, crackers, garland, poinsettia, carol lantern, advent house) |

The Christmas event needs no new art: the Advent track in `events.json` (dated `12-01`, 37 days, a fresh one every year) gives Beans most days and a piece of furniture every fourth day, the fridge and 300 Beans on Christmas Day, and snow falls past every window while it runs. Special days greet the first arrival with their `event.*` lines (Black Cat Day, Halloween, the Christmas event, New Year's Day, the Housewarming).

## 8. Audio (25 files, `Audio/`)

Cat: meow short, meow long, chirp, trill, grumble, question meow, purr loop, sleep breathing, zoomies thumps. World: door open, door close, rain loop, wind loop, fire crackle, dawn birds, night crickets, snow hush. UI: tap, place item, Bean chime, gift open (one per rarity, 4), level up, streak milestone, pass tier, purchase confirm. Generated in Higgsfield (`generate_audio`) or CC0 libraries; stored in the Cat App folder under `audio/`; every file logged with its source.
