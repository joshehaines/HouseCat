# The cat's walk and run films

White-cat films the game tints into every look (Josh, 19 Oct 2026: of the rebuilt puppet and a generated film, "B is
the best by far"; then "all 32 films (walk and run, both views, every body)").

- `<body>_<view>_<gait>.mp4`: Higgsfield Kling 3.0, pro, 5 s, 16:9 (1920 x 1080), sound off, each started from
  `start/<body>/<view>_<gait>_white_<frame>.png` (the puppet's white frame: frame 4 of its walk, frame 5 of its run).
- `start/<body>/`: that frame drawn again from every coat mask, each part's shade (`ids`), the parts' coverage
  (`part-.`), the ears, tail and head (`part-_ear_`, `part-_tail`, `part-_head`) and the points the film follows
  (`points` .json), all from `renderThePuppetsMovement` (`tools/asset-pipeline/walk/films.sh start`).
- `frames/`: what `tools/asset-pipeline/walk/filmwalk.py` makes of them (`films.sh frames`); `build_cat_art.py` copies
  it into `App/Art/cat/custom`.

Prompts (the body's words: slim short-haired, stocky round short-haired, slim long-haired, fluffy long-haired, very
fluffy flat-faced Persian, slender oriental, large shaggy Maine Coon, hairless Sphynx with pale pure white hairless
skin):

- Walk, side: "The painted <body> cat with pure white fur walks steadily to the left in exact side profile, a relaxed,
  natural cat walk: shoulder blades rolling, hips swaying, head level, tail held up with a gentle sway. The camera
  tracks with the cat at its walking speed so it stays in the centre of the frame the whole time, the same size. Plain
  flat chroma green background, no floor, no shadow, no other objects. Keep the same painted style, soft warm rim
  light, pink inner ears and orange eyes as the first frame; the cat stays pure white."
- Walk, three-quarters: as the side, but "walks steadily towards the viewer and to the left at the same three-quarter
  angle as the first frame ... The camera moves back with the cat at its walking pace, so it stays in the centre of
  the frame at the same size and the same angle the whole time." The Maine Coon's adds "no stripes, bands or markings
  anywhere, on its legs or anywhere else" (Kling still painted faint leg stripes, twice).
- Run, side: "... runs in a fast, smooth cat gallop to the left in exact side profile, filmed in slow motion at half
  speed so every stride is smooth and clear: the back gathering and stretching, legs reaching far forward and back,
  paws close to the ground, tail streaming out behind. The camera tracks with the cat so it stays in the centre of the
  frame, the same size, the whole time. Its ears keep the same shape and size as in the first frame. Plain flat chroma
  green background, no floor, no shadow, no dust, no smoke, no particles, no motion blur, no other objects. ..." At full
  speed a gallop was only three or four of Kling's pictures a stride. The slim long-haired and Persian side runs were
  made again adding "It is already galloping from the very first frame and keeps exactly the same steady speed and the
  same gallop the whole time, never slowing down, speeding up or trotting" (the first sped up out of a trot, the second
  slowed into a crouch, so neither came round in one stride).
- Run, three-quarters: as the side run, "towards the viewer and to the left ... keeping exactly the same three-quarter
  angle as the first frame the whole time (it never turns side on)".
