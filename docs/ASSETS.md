# HouseCat — asset manifest (as built, 17 Oct 2026)

Decision (Josh, 17 Oct): every asset class is generated in Higgsfield and finished before the code build starts, so the code builds against real art. The masters are in `housecat/assets/` (10,523 files, 2.26 GB after the cat-builder delivery of 17 Oct, checksums verified on the Mac); `assets/manifest.json` lists every file with its class, orientation, source job and placement data, plus a `conventions` block that says how each class is used. `tools/asset-pipeline/` holds the Python that made them and `pipeline_state.json` (every Higgsfield job ID and result URL), so any item can be re-cut or regenerated. STYLE.md is the look; this file is the inventory.

## 1. Specs that changed during production (all decided by Josh on 17 Oct)

- **Rooms are corner rooms in 2:1 isometric**, not side-on: left and right walls, a 10 × 10 floor grid, walls 5 cells high, a door in one wall showing the next room. Rooms are built in code: flat seamless tiles (walls, floors) projected onto the three planes, multiplied by a painted light map for the time of day, plus window and door frames with masks.
- **Furniture comes in two orientations**, `R` (against the right wall) and `L` (against the left wall), so items can be rotated. Each was painted inside the same neutral grey reference room (job d8ab3b05) and cut out; `pos_in_ref`/`size_in_ref` in the manifest give where it stood in that room, from which the floor anchor follows.
- **Cat scale**: the cat is about half the sofa's height; rooms render large.
- **Widget**: the cat sits on a window sill with the live weather behind the glass (16 frames: 8 square, 8 wide).
- **World map**: blue sea and green land from real coastlines, city names drawn by code when zoomed; biome index mask for the pin.

## 2. What was delivered (`assets/`)

| Folder | Contents | Files |
|---|---|---|
| `furniture/<room>/` | Living 16 items, bedroom 14, kitchen 14, garden 12, study 12, attic 12 (the sunbeam and skylight spots are glow sprites, with the painted versions kept as `_painted`), season passes Housewarming 8, Midwinter 8, First Light 8, Housewarming pack 6, founders' plaque 3 finishes (blank, number drawn in code); each R and L | 230 |
| `rooms/walls`, `rooms/floors` | 33 wallpapers and 33 floors (5+ per room, plus pass and pack finishes; the living room's fourth and fifth wallpapers and fifth floor added 17 Oct), 2048 px seamless tiles | 66 |
| `rooms/windows`, `rooms/doors` | 8 window and 8 door frames, each with an `_opening` mask | 32 |
| `rooms/garden_strips` | 5 garden boundaries (picket fence, brick, drystone, hedge, trellis), horizontally tiling | 5 |
| `rooms/lightmaps` | light maps for morning, midday, evening, overcast, night × left wall, right wall, floor (.npy float + .png preview), and the grey reference room | 31 |
| `world/houses` | 8 exteriors with glass masks, plus door-open and snow variants (repaints: cross-fade, not pixel-aligned) | 48 |
| `world/terrain` | 8 biomes × 4 seasons, transparent sky | 32 |
| `world/weather` | raindrop, snowflake, leaf, petal, cloud, fog | 6 |
| `world/map` | painted map 4096 × 2048, land mask, biome index mask + legend | 4 |
| `cat/base/<set>/` | 4 body sets (short slim, short chunky, long slim, long chunky) × 4 views (side, three-quarter front, front, three-quarter back) × 11 parts (head, 2 ears, torso, 4 legs, 3 tails) + a whole standing cat per view | 192 |
| `cat/expressions` | replacement heads: calm, slow blink, content, surprised, sleepy, squint × front, three-quarter, side | 18 |
| `cat/marked/<marking>/` | tuxedo, locket, socks: the full part set repainted per body set and view (swap the set) | 528 |
| `cat/ears_rounded`, `cat/whiskers`, `cat/marking_refs` | rounded ears (4 views × 2), whiskers (short, long, curly × L/R, white on alpha), the three marking references | 17 |
| `cat/custom/base/` | **The cat builder, painted white** (added 17 Oct, see §3b): 8 bodies (short slim, short chunky, long slim, long chunky, Persian, Siamese, Maine Coon, Sphynx) × 4 views × 11 parts (352); resting poses for every body, plus every ear and bobtail variant of the four standard bodies (352); expression heads (108: ear-less for the standard bodies, with ears for the breeds, and the old eared standard set kept as a fallback); swap ears rounded, folded, tufted, oriental × 4 views × far/near (32); bobtails × 4 views × up/curl/low (12); standing references for the breeds (16) | 872 |
| `cat/custom/masks/` | Per sprite, same size: 5 pattern masks (tabby_mackerel, tabby_classic, spotted, tortie, colourpoint), 4 white-marking masks (white_mitts, white_tuxedo, white_bicolour, white_van) and a features mask (iris left, iris right, nose) | 7,988 |
| `cat/custom/catbuilder.json` | Bodies, ears, tails, patterns, white markings, colour palettes, the 23 presets, file paths, the proposed free/paid flags; `cut_report.json` has the cut check per sheet | 2 |
| `outfits/` | 35 outfits × 4 views (26 head/neck/face, 9 body) | 140 |
| `gifts/` | 60 gifts: toys, treats, oddities, keepsakes, seasonal, 12 each | 60 |
| `ui/` | 30 icons (Beans, XP, trust, streak, pass, objectives, shop, actions, rooms…) | 30 |
| `widget/` | 8 window-sill frames, square and wide, each with a `_glass` mask | 32 |
| `cat/poses/<coat>/` | Whole-cat resting poses for every body set and coat (plain, tuxedo, locket, socks): sit side / three-quarter / front / back (the widget pose), loaf side / three-quarter, curled asleep, stretch | 128 |
| `brand/icon`, `brand/logo` | App icon: flattened 1024 + iOS 26 layers (background, cat) + three alternate concepts; logo horizontal and stacked, each for light and dark backgrounds | 10 |
| `fx/<effect>/` | Animated effects: fire, candle flame, steam, chimney smoke, fountain trickle, ripple, butterfly (8-frame loops with strips); robin (8 poses); reaction icons (heart, Zzz, notes, sparkle, ?, !, paw); `fx.json` and `anchors.json` (where flames and steam attach on the moving furniture) | 70 |
| `audio/` | 32 WAVs: cat (13: real recordings for every meow, chirp, trill, grumble, hiss and the purr; synthesised sleep breathing and zoomies), world loops (8), UI (11) | 32 |

How a room is assembled in code: pick a wall tile and a floor tile, project them onto the left wall, right wall and floor of the 10 × 10 corner, multiply each plane by the light map for the time of day (blend between maps), cut the window and door openings with their masks and draw the exterior scene / next room behind them, then place furniture sprites (R or L) by their floor anchors, back to front, with the cat puppet among them.

## 3. What the cat art must support (from the arrival design)

- Arrival in the room view: the camera is at the doorway. The cat notices you (ear flick, head turn), runs towards the camera in real time (front view, scaled up along the run, four-frame run cycle driven in code from the leg parts), reaches the bottom edge and rubs along it (side view crossing left-right with tail up, purr, haptic), then chooses what to do next from the behaviour table and walks off to do it.
- Behaviour table = mood × weather × personality → activity with an affordance: sunbeam loaf (sun), window watch (rain, snow), bowl nag (unfed), zoomies (evening, Gremlin), sofa, box, scratch, sleep. Everything the cat does is a furniture affordance plus a pose, so new furniture adds behaviour without new cat art.
- Therefore the puppet needs all four views with legs as separate parts, three tail poses, six eye states, and the greet, rub, loaf, sit, sleep and stretch poses as code poses on those parts, not paintings.

## 3b. The cat builder (`cat/custom`, added 17 Oct)

Josh decided on 17 Oct that players can build any cat ("full like character customisation"); Midnight, the black cat, stays the mascot and the default. SPEC.md "Cat builder" lists the fields and "Coat recipe" the shader; `cat/custom/catbuilder.json` is the data. How the art is used:

- **Everything is white.** Each white sheet is an edit of the black sheet it replaces (same layout, shift ≤ 2 px), so the standard bodies match `cat/base` part for part in shape and proportion (sprite boxes differ by a few pixels: align parts on their centres, and use `cat/base/<set>/…_whole.png` as the standing reference for the standard bodies, `whole/` for the breeds). The look is applied in code: coat, pattern colour, white markings, eye colours, nose. Never ship a tinted copy; tint at runtime (or pre-render for the widget).
- **Masks** sit at `masks/<mask>/` under the same path as their sprite and are the same size. Pattern masks: 255 = pattern colour. White masks: 255 = the fur stays white. Features: red = iris of the eye on the image's left (a side view's one eye), green = the other iris, blue = nose leather. A missing file = 0 everywhere.
- **Bodies.** The four standard bodies use the weight slider (slim and chunky swap past the midpoint). Persian, Siamese, Maine Coon and Sphynx are fixed bodies with their own ears and tail and their own expression heads; draw the Maine Coon 1.15× larger. The Sphynx is hairless: its "coat" is its skin colour.
- **Ears and tail (standard bodies only).** On the puppet, swap `ear_far`/`ear_near` for `ears/ear_<shape>_<view>_<far|near>.png` and the tail for `tails/bobtail_<view>_<pose>.png`; they carry the pattern masks but never white markings. For the standard bodies the expression heads are ear-less (`expr/head_stdnoear_*`), so the chosen ears go on top of every expression too. The resting poses are whole paintings, so every combination is painted: `poses/cat_<body>_<pose>__<rounded|folded|tufted|oriental>.png`, `__bobtail.png` and `__<ears>_bobtail.png` (16 of these sheets are composites of the ear sheet and the bobtail sheet, checked by eye).
- **Pattern consistency.** The six expression heads of a view share the calm head's markings, so a blink never moves a stripe. Variant poses reuse their parent pose's masks; new fur (bigger ears, fur where a long tail was) is plain coat.
- **Outfits** are layered over any look, never painted per cat. Each body needs a one-off fit per view and slot (`catbuilder.json` → `outfits.fit`: dx, dy, scale, all neutral to start, set by eye in a debug screen), and head items sit higher on tall ears (Siamese, Sphynx, Maine Coon, oriental, tufted) so a hat never cuts through them. Paint a special version only if one combination still looks wrong in testing.
- **The widget** cannot run the shader: render the player's look into the App Group whenever it changes (the sit_back and sit_side poses for each house's frame).
- **Kitten** is still a scale (head 1.25×, body 0.8×); age changes the scale, never the art.
- **Reference renderer.** `tools/asset-pipeline/tint.py` is the coat recipe in Python; `presetsheet.py` draws every preset, `prevgrid.py` any sprite with any look. Match the Swift shader to it on a few sprites before building the builder screen.
- How it was made: 88 white sheets and 520 pattern overlays in Higgsfield (gpt_image_2_5), cut by `custcut.py` (pieces, masks, iris and nose detection; `nose_hints.json` places the nose on sleeping and profile poses), variants by `variants.py` and `combos.py`. Job IDs: `pipeline_state.json` under `cust:`.

## 4. Moving settings

Every item in `catalogue.json` carries a motion entry: `{type: static | sway | bob | glow | spin | frames, pivot: (x, y), period: s, frames: n}`. Sway for plants, curtains, hanging lamps and mobiles; bob for balloons and fish; glow (additive overlay) for lamps, fire, TV, candles and string lights; spin for fans and the record player; frames for the few that need painted loops. Rooms also run idle life in code: dust motes in the sunbeam, rain on the window glass, steam, the clock hand, the lamp coming on at dusk.

## 5. Where every asset sits (the gentle walls)

| Pool | Count | How you get it |
|---|---|---|
| Free from day one | starter catalogue 8 items, 3 wallpapers + 3 floors per room, common cat traits, 4 earned outfits | housewarming allowance (150 Beans) and play |
| Bean catalogue by level | 30 items in tiers: L1 8, L3 8, L6 8, L9 6; rooms by level + Beans | Beans from feeding, play, objectives, streak milestones, health rewards |
| Objectives (new, the Clash achievement loop) | 3 daily, 3 weekly, ~60 one-off achievements | Beans and pass points; nothing else |
| Season pass, free track | 3 items + a basic outfit + Beans per season | pass points from daily actions |
| Season pass, paid track | 5 items, 1 outfit, wallpaper + floor, a cat look per season | $4.99 / £4.99 a season or Cat Club |
| Paid sets | 6 sets × 6–8 items + outfit | $2.99 / £2.99 each, $4.99 bundle |
| Outfits | 12 at $0.99 / £0.99, 4 earned (streak 30 and 100, referral, launch event), 3 pass, 1 founders | |
| Cat looks | every cat-builder option, free at launch (decided 17 Oct); more cats are the paid item | free |
| Cat Club | monthly outfit, extra cat slot, +20% Beans, widget styles, rooms at half Beans, every season pass | $2.99 / £2.99 a month, $19.99 / £19.99 a year |
| Founders | plaque, exclusive outfit, Club forever | $29.99 / £29.99 in the launch window only |

Beans play the role gems play in Clash of Clans, earned through objectives and streak bonuses; they are not sold in v1. Selling them later is a switch in the store, not a rebuild, and keeping them earn-only is what keeps the app clear of the loot-box and UK DMCC rules.

## 6. How it was made (for re-dos)

- Model gpt_image_2_5, quality high, 2k, about 2.75 credits an image. At most 16 jobs in flight (more returns 429).
- Furniture: painted into the grey reference room, cut with a saturation matte plus rembg (`extract.py`). Surfaces: painted flat, made seamless by cross-fade or mirror tiling (`tiles.py`). Windows, doors, houses, terrain, outfits, gifts, UI: magenta background with cyan glass, keyed by `post.py`, `openings.py`, `outfitcut.py`, `widgetcut.py`. Cat: cream-background part sheets cut and auto-named by layout (`catcut.py`, `markcut.py`, `extrascut.py`).
- Re-cut anything from its raw: the raw result URL for every job is in `pipeline_state.json`.

## 6b. Added in milestone 1 (17 Oct 2026)
- `assets/world/scenes/`: each home painted into each biome and season as one picture (raised three-quarter view, 16:9 at 2688 × 1520 since the landscape decision; the first square set was superseded; all 8 homes × 8 biomes × 4 seasons = 256 scenes, each with its door-open edit, 1.3 GB; listed in the manifest as class `world/scenes`). Roughly one painting in sixty came back mirrored and was redone; `woodland_cabin_tropical_winter` has its door and window swapped (kept: the door point is measured per scene). Water sometimes reflects the magenta key as pink; the key only treats sky that reaches the top of the picture as sky, keyed into `<name>.jpg` (the painting; the sky filled with nearby land colour), `<name>_land.png` (1 = painting, 0 = sky) and `<name>_glass.png` (window glass), with a `_dooropen` edit of each that lines up with it. `scenes.json` gives each door point (fractions of the painting) measured from the door-open edit. Made by `tools/asset-pipeline/scenes.py`; the raw Higgsfield results are recorded in `pipeline_state.json` and the scratch ledger, not kept in the repo.
- `furniture/living/*`: all 31 living-room sprites repainted in the grey reference room (the cream-room originals were not true 2:1); their manifest entries carry the new job ids, `pos_in_ref` and a `repainted` note. The fireplace's fire anchor in `fx/anchors.json` was re-measured.
- `rooms/houses.json`: each home's room plan for the house view (storey and back corner of every room, which is outdoors, the staircase), and the ground tile per biome. `furniture/living/furn_living_stairs_R.png` (and its mirror, `_L`): the staircase, class `fixture` in the manifest.
- `cat/rig.json`: the puppet rig (pivots, joints, draw order, walk swing) for `short_slim` in the side, three-quarter-front and front views. `rooms/layout_living_demo.json`: the demo living room (surfaces, window, door, items, scales, the cat's start and activity spots).

## 6c. Added in step 2 (18 Oct 2026)
- `assets/cat/rig.json` holds a rig for every body (`tools/asset-pipeline/rigfit.py`; breeds without the separate ear parts, siamese and sphynx tail roots moved onto their cut faces).
- The app's copy of the cat builder art (`App/Art/cat/custom`, `tools/app-assets/build_cat_art.py`): parts at 0.35 and poses at 0.4 of the masters, colour as JPEG with a PNG alpha, masks as listed in the script, `index.json` (sizes and masks per sprite) and `builder.json` (the builder's options in order). The tail's cut face is erased and the rump's furred over there (`tools/asset-pipeline/caps.py`); the masters keep theirs.
- `App/Art/gifts` (all 60 at 0.3) for the room and the book; `App/Audio` adds the hungry and soft meows, the Bean chime, the level-up, the four gift-opening sounds and the streak milestone.
- `Content/names.json`: the word filter for cat names (for Josh to review).

## 6d. Added in step 4 (18 Oct 2026)
- `world/map/map_biome.png` regenerated by `tools/asset-pipeline/biomes.py` (rules by latitude plus hand-drawn regions for deserts, mountain ranges and forests; Britain and lowland Europe countryside, not forest); the legend says so. `world/map/cities.json`: 245 cities with coordinates, for the city biome and the map's labels.
- `Content/weather.json`: the seasonal weather tables per biome (weights for sun, cloud, rain, storm, snow, fog, wind, heat), for Josh to tune.
- App art now carries the London terrace's 32 exterior scenes, all 32 terrains (quarter size) and the world map with its biome mask.

## 6e. Added in the follow-ups (18 Oct 2026)
- `world/ground/ground_<biome>.png` (city, coast, countryside, mountain, forest, desert, tropical, snow, autumn): seamless 2048 px tiles for the ground around the house, bundled at quarter size as HEIC.
- `ui/shop/shop_<offer>.png` (club, starter, housewarming, forever, adopt, gifts): the shop's offer illustrations, painted on magenta with the floor reference and the mascot plate, keyed by `tools/asset-pipeline/shopkey.py` (pockets of key colour inside the painting go too, and saturated magenta spill is greyed). Bundled at 0.4.
- App-only derived art (not masters): `world/previews/<style>_<biome>.jpg` with `_land.png`, the house step's summer previews at 720 px; the seven non-London homes' exteriors as download packs (`tools/app-assets/build_home_packs.py`).
- `audio`: `ui_purchase_confirm` joins the app's sounds (after a purchase).

## 6f. Added in step 5 (18 Oct 2026)
- The widget frames go into the app at 0.32 (square 655 px, wide 860 px; the glass masks stay out, the frames' own transparency is the glass). The app measures each frame's glass from its alpha when it makes the widget kit; the sill line (where the cat's feet go) is set by eye per frame, square and wide, in `Tuning.Widget.sill`.
- One frame per home: London terrace sash, Georgian townhouse arched, mansion flat bay, cottage casement, woodland cabin cabin, houseboat porthole, Mediterranean rooftop shuttered, new-build picture window.

## 6g. Added in step 6 (18 Oct 2026)
- `audio/ui_knock_off.wav` (a ceramic clack and a soft bump) and `audio/ui_sparkle.wav` (two rising chimes): synthesised in code like the other UI sounds, for the mini-games. The recorded `cat_zoomies_thumps` and `cat_sleep_breathing` are now in the app too (Laser Pointer and the nap).
- The games use existing art: the living room's floor, wallpaper and rug, five gift keepsakes on the shelf, the paw and sparkle reactions.

## 6h. Added in the economy pass (18 Oct 2026)
- `ui/shop/shop_beans_<size>.png` (handful, pouch, jar, sack, barrel): the five Bean packs, golden paw-print Beans in a growing pile, pouch, glass jar, hessian sack and barrel, painted with gpt_image_2_5 on flat magenta in the shop pictures' style and keyed by `shopkey.py`. Bundled at 0.4 like the other shop pictures.
- `shop_starter.png` now stands for the starter's real contents (Beans, the knitted beanie, an armchair); `shop_adopt`, `shop_forever` and `shop_gifts` are no longer shown (their products went) but stay as masters.
- The widget's peeking head is a crop of the kit's sitting-front pose, not new art.

## 6i. Added in the outdoors pass (18 Oct 2026)
- `world/props/<biome>_<piece>[_autumn|_winter].png` (42): the scenery round the house, three pieces per biome (countryside oak, hawthorn, field stone; city plane tree, Victorian lamp, planter; coast umbrella pine, dune grass, sea rocks; forest Douglas fir, silver birch, mossy stump; mountain Swiss stone pine, granite boulder, woodpile; desert date palm, agave, terracotta pots; tropical coconut palm, banana plant, frangipani; snow spruce, snowman, snowy rocks), with autumn pictures for the oak, the plane and the birch and winter pictures for every piece outside the desert, the tropics and the snow biome. Painted with gpt_image_2_5 on magenta at a high isometric three-quarter view, keyed with `shopkey.py`, bundled at 0.3 (about 17 MB).

## 6j. The outfits worn (18 Oct 2026)
- All four views of every outfit are bundled now (they were three-quarter front only, for the shop), at 0.5. No new art: hats, glasses and neckwear are fitted in code to each pose. The body garments need painting for the sitting and loafing poses before they can be sold.

## 7. Known gaps and things for Josh's eye

- **Small items were painted at furniture size.** The model draws whatever it is asked for large, so tabletop and small floor items (mug, kettle, alarm clock, slippers, snow globe, candle, cat bed, laundry basket…) come out as big as a chest of drawers. The sprites are high-resolution, so scaling down in code loses nothing: `assets/manifest.json` carries a `suggested_scale` for 78 such files (from `tools/asset-pipeline/scales.py`); carry it into `catalogue.json` and check each by eye in the room view.
- **Composite check** (docs/previews): a bedroom built only from delivered files with `tools/asset-pipeline/demo_room.py` (tiles + light map + window with the coast terrain behind it + door + furniture by its reference position + the cat), at midday and evening; plus the widget and exterior composites. Rugs and mats are floor decals and must draw before everything else; everything else sorts by its floor anchor.
- **Audio**: the cat voices and purr are real recordings from Wikimedia Commons, all public domain or CC0 (no attribution required; credited anyway in `audio/CREDITS_cat_sounds.json` for the licences screen). UI and ambience are synthesised in code. If you record your own cat later, drop the files in under the same names.
- **Three-quarter back heads** show part of the face (the model draws a face on every head). Use the side head turned slightly, or regenerate if it reads wrong in the puppet.
- **R/L pairs are painted separately**, so a few pairs differ in detail (e.g. First Light bird box roof colour, hamper lining). Mirroring the R sprite for L is the fallback if a pair jars when rotated.
- **Door-open and snow houses** are repaints, not pixel-aligned: cross-fade rather than swap.
- **Tuxedo**: on some views only one front paw is white.
- **Widget frames**: the sill lines are set (step 5, `Tuning.Widget.sill`); worth a look on a device in each home.
- **Paid looks**: none at launch. Every builder option is free (decided 17 Oct); the `rare` flags in `cat/custom/catbuilder.json` are all off and stay as the switch if paid looks come later. Kitten-forever is a scale; nothing is painted per look.
- **Cat builder, tortoiseshell**: the tortie mask came out as bold patches rather than fine brindle; it doubles as the calico patches.
- **Cat builder, mitts and tuxedo on the expression heads**: the model drew bodies under some heads when painting these masks; the masks are clipped to the head, so only the chin and muzzle marking remains, which is right.
- **Swap ears on the puppet** sit where the body's own ears sit; folded and tufted ears may want a small per-view offset, set once by eye in data.
- The puppet (cut-out parts posed in code) is for movement: walking, running, rubbing, head turns. Resting poses (sit, loaf, sleep, stretch, the widget's window watch) are whole paintings in `cat/poses`, so the cat never has to hold a pose the puppet cannot make. Milestone 1 should still prove the puppet walk and the cross-fade between puppet and pose first.
- **Motion**: flames, steam, water, smoke, the garden robin and butterflies, and the reaction icons are animated frames in `fx/`; everything else in ASSETS.md §4 (sway, bob, glow, spin) is done in code. Kettle and mulled-wine steam anchors are the top of the sprite: nudge them to the spout by eye. House chimney smoke needs a chimney point per house set in data.
