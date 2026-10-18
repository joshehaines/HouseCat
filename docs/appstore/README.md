# HouseCat: App Store listing and review notes (draft, 18 Oct 2026)

Everything App Store Connect asks for, ready to paste once the developer team exists. Prices are UK tiers; StoreKit shows each player their own.

## Listing

- **Name** (30): HouseCat
- **Subtitle** (30): Your cat, your home, every day
- **Promotional text** (170): Pick a home anywhere on the globe, build your cat, and visit each day. Feed, stroke, play and decorate room by room while your cat waits for you in the widget.
- **Keywords** (100): cat,cosy,cozy,pet,kitten,decorate,room,home,widget,streak,virtual pet,isometric,calm,daily,care
- **Category**: Games / Simulation (secondary: Casual)
- **Age rating**: 4+. None for every content question; Loot boxes: No; Contests: No; Unrestricted web access: No; User-generated content: No (the only text another person sees is the cat's name, filtered); Health or wellness topics: None; not Made for Kids.

### Description

Your own cat, in your own home, somewhere in the world.

Pin your home anywhere on a turning painted globe and the sky, the seasons and the real weather follow: rain on the glass in Lisbon, snow on the sill in Chamonix. Build your cat in the cat builder (any coat, pattern, eyes and ears) and give it a name.

Every visit, your cat notices you, runs over and rubs along the screen, then gets on with its day: a nap in the sun, a loaf on the sofa, zoomies at dusk. Feed it, stroke it, play laser pointer, knock-it-off and string chase, and it brings you a gift for its book.

Make the house a home, room by room. Open the bedroom, the kitchen, the garden, the study and the attic as you level up, and place every piece where you like. Earn Beans every day, or top up with a pack.

Your cat lives on your Home Screen too: in your own window with your own weather, waiting by the door until you visit, with your streak. Miss a day and it sulks a little; it never leaves, and nothing is ever lost.

Share your cat with someone you live with or love, and keep the streak together.

- Beans are earned every day in play and also sold in packs. Room looks are kept for good. Cat Club is an optional subscription: +20% Beans, rooms for half the Beans, moving home for free and every season's paid track; yearly with a 7-day free trial, or monthly. It renews automatically until cancelled at least a day before renewal in Settings.
- Nothing is random for money, no ads, no account.
- Terms of Use: https://housecatgame.com/terms
- Privacy Policy: https://housecatgame.com/privacy
- Weather: Apple Weather. Place search: Apple Maps. The cat's voice: recordings from Wikimedia Commons.

## Screenshots (iPhone 6.9", landscape, 2868 × 1320, `iphone-6.9/`)

| File | Caption |
| --- | --- |
| 01_intro.png | A cat, a home, anywhere in the world |
| 02_home_tour.png | Visit homes from London to Marrakech |
| 03_room.png | Your cat runs to meet you every day |
| 04_decorate.png | Make every room your own |
| 05_winter_exterior.png | Real weather and seasons where you live |
| 06_game.png | Play laser pointer, knock-it-off and string chase |
| 07_cat_club.png | Cat Club: more Beans and every season's track |
| 08_globe.png | Pin your home anywhere on the globe |
| 09_beans.png | Earn Beans, or top up any time |
| 10_level_up.png | Level up and open new rooms |

Taken in the simulator with debug screens (`CLAUDE.md`, "Debug"). The simulator draws the Dynamic Island into its screenshots, which a phone's own screenshots never include, so it was painted out of 04, 07, 09 and 10 from the background beside it. Shots 01 to 06 and 08 are from before the economy pass; 03 to 06 show the status pill without its XP bar.

## In-app purchases (17, matching `Store/HouseCat.storekit`)

Review screenshot for every product: `09_beans.png` (packs), `07_cat_club.png` (Cat Club), the shop's Room looks section (`HOUSECAT_SCREEN=shop HOUSECAT_SHOP=looks`) for the looks.

| Product ID | Type | Price | Display name | Description (45) |
| --- | --- | --- | --- | --- |
| housecat.beans.handful | Consumable | £0.99 | A handful of Beans | 500 Beans for your cat's home |
| housecat.beans.pouch | Consumable | £1.99 | A pouch of Beans | 1,200 Beans for your cat's home |
| housecat.beans.jar | Consumable | £3.99 | A jar of Beans | 2,600 Beans for your cat's home |
| housecat.beans.sack | Consumable | £9.99 | A sack of Beans | 7,000 Beans for your cat's home |
| housecat.beans.barrel | Consumable | £19.99 | A barrel of Beans | 15,000 Beans for your cat's home |
| housecat.starter | Non-consumable | £1.99 | Starter Pack | 2,000 Beans, a knitted beanie and an armchair |
| housecat.season.housewarming | Non-consumable | £4.99 | Housewarming living room | A whole living room look (launch month only) |
| housecat.room.fireside_living | Non-consumable | £2.99 | Fireside living room | A whole living room look |
| housecat.room.midnight_bedroom | Non-consumable | £3.99 | Midnight bedroom | A whole bedroom look |
| housecat.room.rainy_bedroom | Non-consumable | £3.99 | Rainy day bedroom | A whole bedroom look |
| housecat.room.country_kitchen | Non-consumable | £4.99 | Country kitchen | A whole kitchen look |
| housecat.room.riviera_garden | Non-consumable | £4.99 | Riviera garden | A whole garden look |
| housecat.room.cosy_study | Non-consumable | £4.99 | Cosy study | A whole study look |
| housecat.room.cabin_attic | Non-consumable | £3.99 | Cabin attic | A whole attic look |
| housecat.room.starlit_attic | Non-consumable | £2.99 | Starlit attic | A whole attic look |
| housecat.club.monthly | Auto-renewable (Cat Club) | £2.99 / month | Cat Club Monthly | More Beans, half-price rooms, every pass |
| housecat.club.yearly | Auto-renewable (Cat Club) | £19.99 / year, 7-day free trial | Cat Club Yearly | More Beans, half-price rooms, every pass |

The Housewarming look's product ID keeps its earlier name; IDs can never be renamed once live. Family Sharing: on for Cat Club only, as the StoreKit configuration has it (a room look's pieces go into one household's save).

## Notes for App Review

- No account or sign-in. The game starts with a short intro (skippable) and the cat builder.
- The shop is the bag button, bottom right of the room. Every product can be bought from it; Restore Purchases, Request a refund, Manage subscription, Terms and Privacy are at its end. Beans bought in a pack appear at once in the balance at the top right of the shop and in the room.
- Beans are the game's one currency: earned every day by playing and sold in fixed packs. Nothing bought is random; the daily gift cannot be bought or affected by any purchase.
- A room look puts a whole room's furniture, wallpaper and floor in at once ("Add the whole room"), and can be tried in the room before buying.
- Cat Club's paid season track opens with the subscription; the first season starts on 2 November.
- Health (steps, sleep, workouts, read only) is offered on the third day of play and can be switched on in the cat's settings (the cat's face button, bottom right, then Reminders and widget). It only ever gives extra XP. Nothing is written to Health or leaves the phone.
- Notifications are local, at times the player chooses, offered after the first feed with a sample of what they look like.
- Sharing a cat (co-owning) uses iCloud: the cat's face button, Reminders and widget, Share. Invites are one-time links or a six-character code that lasts two days.
- Weather comes from WeatherKit for the home's pinned place (no device location); the Apple Weather mark and link are in the cat's settings.
- Analytics are off unless the player switches them on in the cat's settings; anonymous counts only.
- Your data, in the cat's settings: Export my data shares the whole save as JSON; Delete all my data (two confirmations) deletes the save, the widget's files, preferences, reminders and the shared household in iCloud, and starts again from the intro. There is no account to delete. Licences and credits are there too.
