# HouseCat — art style bible

Reference mood: the rooftop painting (black cat on terracotta tiles against a blue sky): textured brushwork, bold warm key light, cool fill, strong silhouette.

## The cat
The rules below describe the mascot, Midnight (the default cat and every marketing image). Players can build any cat (SPEC.md "Cat builder"); the builder art follows the same drawing rules, see the last two bullets.
- Solid black fur that is never pure black: dark navy-brown base (#1b1a22 to #2a2630 range) with a lit edge so the silhouette reads in dark mode and at 16 px.
- Amber/gold eyes with one white catchlight; eyes and ear angle carry all expression.
- Slim graceful body, long slim legs, long curling tail, a round head a touch large for the body, big round amber eyes, small simplified nose, subtle mouth line. Slightly stylised (painted-animation), real cat anatomy underneath. Both ears upright and pointed. Kitten = same parts at head 1.25x, body 0.8x.
- The master cat is the approved style-test image of 16 Oct 2026 (Higgsfield job 9e4615cc-5e47-4b77-b869-9fcded637dfd); every part set descends from it.
- Palette direction: the Mediterranean-pastel test (E): high-key, saturated, violet-blue simplified shadows; jewel tones at dusk.
- Painted variants of the mascot: void (all black), tuxedo (white chest and paws), smoke (grey undercoat on the edges), white-locket (single white chest spot). They stay as the mascot's masters; in the game every look, black included, comes from the cat builder.
- Puppet parts (as delivered): head, ear far, ear near, torso, four legs (front near/far, back near/far), three tails (up, curl, low); four views (side, three-quarter front, front, three-quarter back); four body sets (short slim, short chunky, long slim, long chunky). Expressions are whole replacement heads (calm, slow blink, content, surprised, sleepy, squint) for the front, three-quarter and side views. Markings (tuxedo, locket, socks) are full repainted part sets, not overlays.
- The cat reference chain: master plate 3553b9b6 → turnaround 80aec50a → one turnaround per body set → parts sheets. Every cat prompt carries the identity line from docs/art-log.md.
- Cat-builder art (`assets/cat/custom`) is painted WHITE on mid-grey: soft white fur, cool grey-violet shading, a warm rim light, pink inner ears and nose, amber eyes. Each white sheet is an edit of the black sheet it replaces (same layout and pose), so the coat recipe can tint it to any colour. Patterns are masks painted on the white sheets in dark charcoal, never separate colour paintings.
- Breed bodies (Persian, Siamese / Oriental, Maine Coon, Sphynx) are drawn in the same painterly style from the nearest body set: same views, same 11 parts, same poses and expressions. A breed keeps its own ears and tail; the four standard bodies take the swap ears (rounded, folded, tufted, oriental) and the bobtail.

## Never (IP and tone)
- No red bow or red collar. No white-sclera almond eyes. No crescent or any forehead mark. No witch hat, broom or cauldron on the cat. No bell collar.
- No Ghibli greens-and-cream palette or watercolour-wash backgrounds.
- No cutesy kids'-app UI: no bubble fonts, no rainbow gradients, no stickers.

## Homes and rooms
- Corner rooms in 2:1 isometric: left and right walls meeting at the back, 10 x 10 floor cells, walls 5 cells high, a door in one wall that shows the next room, windows that show the exterior scene.
- Doors are painted in 3D at the wall's 2:1 angle (architrave standing proud, the wall's depth in the jamb, a threshold), on magenta from a guide with the frame drawn at the slope, never a front-on door laid onto the wall (Josh, 19 Oct: "they look very strange").
- Walls and floors are flat seamless tiles (2048 px) projected in code; light and shadow come from a separate painted light map per time of day (morning, midday, evening, overcast, night), so any wallpaper or floor works in any room without repainting.
- Palettes: terrace = brick reds and slate; mansion-block flat = cream and teal; cottage = moss and honey.
- Light: warm key from the upper left, cool fill from the window; time of day shifts hue, not line.
- Weather lives on the exterior as particle and tint layers; interiors show it through the window only.

## Furniture
- One template: every item is painted inside the same neutral grey reference room (job d8ab3b05) at the same 2:1 isometric angle and key light, then cut out; two orientations per item, R (against the right wall) and L (against the left wall). The game draws furniture at 80% of its painted size (Josh, 19 Oct), so the standing cat is about two-thirds of the sofa's height.
- Each item: footprint (w x d cells), layer (floor or wall), affordances (sit, sleep, hide, perch, scratch, eat, none), and a cat-on-it pose if it has one.
- Sets of 6–8 items share a palette and a wallpaper + floor.

## Generation backgrounds (so cut-outs stay clean)
- Furniture: neutral grey reference room (saturation matte). Cat parts: flat pale cream (magenta spills purple into black fur); marked cats on mid-grey so the white reads. Houses, terrain, outfits, gifts, UI, windows and doors: flat magenta #FF00FF background, and flat cyan #00FFFF wherever glass or an opening must stay see-through. Widget frames are full paintings (wall and sill) with cyan glass.
- Never ask for pink or magenta inside a magenta-keyed item; say peach, coral or red instead.

## Export
- Masters are PNG with alpha in `assets/`, named as in `assets/manifest.json`; the build makes @2x/@3x atlases per room and per cat.
- Log every accepted generation (Higgsfield ID, prompt, date) in `docs/art-log.md`; the full per-file job record is `tools/asset-pipeline/pipeline_state.json`.
