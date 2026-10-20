# HouseCat: App Store listing, review notes and launch checklist (19 Oct 2026)

This file holds everything App Store Connect asks for, ready to paste. It is written against version 1.0 as built at commit aaa050f3 and after. Prices are UK tiers; StoreKit shows each player their own. The website's corrections are in `website_fixes.md`.

## Listing

- **Name** (30): HouseCat
- **Subtitle** (30): Your cat, your home, every day
- **Promotional text** (170): Pick a home anywhere on the globe, build your cat, and visit each day. Feed, stroke, play and decorate room by room while your cat waits for you in the widget.
- **Keywords** (100): cat,cosy,cozy,pet,kitten,decorate,room,home,widget,streak,virtual pet,isometric,calm,daily,care
- **Category**: Games / Simulation (secondary: Casual)
- **Support URL**: https://housecatgame.com/support/
- **Marketing URL**: https://housecatgame.com/
- **Privacy Policy URL**: https://housecatgame.com/privacy/
- **Licence agreement**: Apple's standard EULA. Our Terms of Use are linked in the description, the app, and on the Cat Club page.
- **Copyright**: 2026 Josh Haines
- **Age rating**: 4+.
  - Every content question: None.
  - Gambling: No. Loot boxes: No. Contests: No.
  - Unrestricted web access: No.
  - User-generated content: No. In 1.0 no text one person types is shown to anyone else: co-owning is off, and the cat's name stays on the device.
  - Messaging or chat: No. Advertising: No.
  - Health or wellness topics: None. It only reads steps, sleep and workouts, optionally, for extra XP.
  - Parental controls: No. Age assurance: No. Not Made for Kids.
- **Devices**: iPhone, iPad and Apple Watch (the Watch app is inside the iPhone app). In App Store Connect, turn off "Make this app available" for Mac (Apple silicon) and Apple Vision Pro, and don't submit the HouseCatMac target for 1.0 (see the checklist).

### Description

Your own cat, in your own home, somewhere in the world.

Pin your home anywhere on a turning painted globe and the sky, the seasons and the real weather follow: rain on the glass in Lisbon, snow on the sill in Chamonix. Build your cat in the cat builder (any coat, pattern, eyes and ears) and give it a name.

Every visit, your cat notices you, hops off the sofa and comes over to say hello, then gets on with its day: a nap in the sun, a loaf on the sofa, a scratch at the post, zoomies at dusk. Feed it, stroke it, play laser pointer, knock-it-off and string chase, and it brings you a gift for its book.

Make the house a home, room by room. Open the bedroom, the kitchen, the garden, the study and the attic as you level up, and place every piece where you like. Outside, the garden or the street moves with the wind and the seasons. Daily and weekly goals and sixty milestones give you something to work towards. Earn Beans every day, or top up with a pack.

Your cat lives on your Home Screen and your Apple Watch too: in your own window with your own weather, waiting by the door until you visit, with your streak. Miss a day and it sulks a little; it never leaves, and nothing is ever lost.

- Beans are earned every day in play and also sold in packs. Room looks are kept for good. Cat Club is an optional subscription: +20% Beans, rooms for half the Beans and moving home for free (and each season's paid track while a season is on); yearly with a 7-day free trial, or monthly. It renews automatically unless cancelled at least 24 hours before the end of the period, in your Apple Account settings.
- Nothing is random for money, no ads, no account.
- Optional: Apple Health. With your permission HouseCat reads your steps, sleep and workouts to give extra XP. It never writes to Health, and the data stays on your device.
- Terms of Use: https://housecatgame.com/terms/
- Privacy Policy: https://housecatgame.com/privacy/
- Weather: Apple Weather. Place search: Apple Maps. The cat's voice: recordings from Wikimedia Commons.

## Screenshots

- **iPhone 6.9"** (landscape, 2868 × 1320): `iphone-6.9/`
- **iPad 13"** (landscape, 2752 × 2064): `ipad-13/`
- **Apple Watch** (46 mm, 416 × 496): `watch/`. App Store Connect asks for these because the Watch app ships inside the iPhone app.

Both sets were taken on 19 Oct from the current build, each screen from a fresh launch with the debug switches in `CLAUDE.md` ("Debug"): a seeded home (`HOUSECAT_HOUSE=full HOUSECAT_CAT=midnight` on a fresh install, `HOUSECAT_SKIP_STORE=1`), with any `HOUSECAT_SCREEN` value so the day-3 cards stay away. The simulator draws the Dynamic Island into iPhone screenshots, which a phone's own screenshots never include, so it is painted out from the picture round it (OpenCV inpainting). The order and captions are in the table below the checklist. On iPad the room's controls and cards are drawn 1.6× on the 13-inch (`Tuning.Stage.hudDesignWidth`), so the iPad set was retaken the same way after that change.

The Watch set was taken on 20 Oct on the Apple Watch Series 12 (46mm) simulator paired with the iPhone 18 Pro, from a debug build: the iPhone app first, with the seeded home (`HOUSECAT_HOUSE=full HOUSECAT_CAT=midnight HOUSECAT_SKIP_STORE=1` on a fresh install), so the Watch has its snapshot; then the Watch app, freshly installed so no older snapshot is left on it, with `HOUSECAT_WATCH_TAPS=pet` and `=feed` for the cat's replies and `HOUSECAT_SCREEN=complications` for every complication family.

The shop is not in the marketing set: a simulator launch from the command line has no test products, so it shows the catalogue's UK prices in a debug build (`HOUSECAT_SKIP_STORE=1`) and "…" otherwise. For each in-app purchase's review screenshot, use `iphone-6.9/review_beans.png` (the five Bean packs), `review_offers.png` (the Starter Pack), `review_room_looks.png` (the room looks) and `review_cat_club.png` (both plans, with the billed price on the button), all taken 19 Oct from the redesigned shop with `HOUSECAT_SCREEN=shop HOUSECAT_SHOP=beans|offers|looks|club`; or run from Xcode (the scheme loads `Store/HouseCat.storekit`) for StoreKit's own prices.

## In-app purchases (21, matching `Store/HouseCat.storekit`)

| Product ID | Type | Price | Display name (35) | Description (55) |
| --- | --- | --- | --- | --- |
| housecat.beans.handful | Consumable | £0.99 | A handful of Beans | 500 Beans for furniture, outfits, rooms and presents. |
| housecat.beans.pouch | Consumable | £1.99 | A pouch of Beans | 1,200 Beans for furniture, outfits, rooms and presents. |
| housecat.beans.jar | Consumable | £3.99 | A jar of Beans | 2,600 Beans for furniture, outfits, rooms and presents. |
| housecat.beans.sack | Consumable | £9.99 | A sack of Beans | 7,000 Beans for furniture, outfits, rooms and presents. |
| housecat.beans.barrel | Consumable | £19.99 | A barrel of Beans | 15,000 Beans for furniture, outfits, rooms and gifts. |
| housecat.starter | Non-consumable | £1.99 | Starter Pack | 2,000 Beans, a beanie and an armchair. Once only. |
| housecat.season.housewarming | Non-consumable | £4.99 | Housewarming living room | A grand fireplace, a hi-fi, bulbs and a welcome mat. |
| housecat.room.fireside_living | Non-consumable | £2.99 | Fireside living room | A fire, a record player and a radiator seat. |
| housecat.room.midnight_bedroom | Non-consumable | £3.99 | Midnight bedroom | Starry walls, a reading lamp and a cat hammock. |
| housecat.room.rainy_bedroom | Non-consumable | £3.99 | Rainy day bedroom | Toile walls, rose carpet and a basket of laundry. |
| housecat.room.country_kitchen | Non-consumable | £4.99 | Country kitchen | Lemon walls, slate floor, a kettle and a bread bin. |
| housecat.room.riviera_garden | Non-consumable | £4.99 | Riviera garden | A pond, a deck chair, festoon lights and a hammock. |
| housecat.room.cosy_study | Non-consumable | £4.99 | Cosy study | Map walls, a globe, a desk lamp and a mug of tea. |
| housecat.room.cabin_attic | Non-consumable | £3.99 | Cabin attic | Pine walls, a skylight, an oil lamp and a wireless. |
| housecat.room.starlit_attic | Non-consumable | £2.99 | Starlit attic | A telescope, a rocking horse and a dressmaker's dummy. |
| housecat.pass.blackcat | Non-consumable | £2.99 | Black Cat Premium Pass | The Black Cat season's 30 premium rewards. |
| housecat.pass.housewarming | Non-consumable | £2.99 | Housewarming Premium Pass | The Housewarming season's 30 premium rewards. |
| housecat.pass.midwinter | Non-consumable | £2.99 | Midwinter Premium Pass | The Midwinter season's 30 premium rewards. |
| housecat.pass.firstlight | Non-consumable | £2.99 | First Light Premium Pass | The First Light season's 30 premium rewards. |
| housecat.club.monthly | Auto-renewable (group "Cat Club", level 1) | £2.99 / month | Cat Club Monthly | +20% Beans, rooms for half the Beans and free moves. |
| housecat.club.yearly | Auto-renewable (group "Cat Club", level 1) | £19.99 / year, 1-week free trial | Cat Club Yearly | +20% Beans, rooms for half the Beans and free moves. |

- The Housewarming look's product ID keeps its earlier name, because IDs can never be renamed once live.
- Family Sharing is on for Cat Club only, as the StoreKit configuration has it. A room look's pieces go into one household's save.
- Each season sells its own premium pass (Josh, 19 Oct: the pass is the main thing sold): `housecat.pass.<season>`, non-consumable, paid once, brought back by Restore Purchases, the same price every season. Cat Club includes every season's premium track as well. Create one for each season in `Content/seasons.json` (four now) and add each new season's before it starts. A season that has no pass of its own runs an earlier one again (`SeasonSchedule`) and sells that one's pass, so no product is ever missing.
- Each product needs a review screenshot (see Screenshots) and, for the subscription group, a display name ("Cat Club").

## App Privacy (the App Store Connect questionnaire)

As built, with the PostHog and RevenueCat keys empty (`project.yml`):

- **Data collection**: "No, we do not collect data from this app."
  - The save, Health results and settings stay on the device.
  - Weather requests send the pinned place's coordinates to Apple WeatherKit. Place search goes to Apple Maps. Purchases go through Apple. Apple, not us, is responsible for those.

If keys are added before launch, answer "Yes" and declare:

- **PostHog** (if its key is set): Usage Data, then Product Interaction. Purpose: Analytics. Not linked to the user. Not used for tracking. The privacy manifest already declares this.
- **RevenueCat** (if its key is set): Purchases, then Purchase History. Purpose: App Functionality. Not linked to the user (RevenueCat's anonymous ID only). Not used for tracking. RevenueCat's own SDK manifest declares the same.

**Tracking**: No. There is no IDFA and no App Tracking Transparency prompt.

## Other App Store Connect answers

- **Export compliance**: `ITSAppUsesNonExemptEncryption` is NO. The app uses only Apple's HTTPS.
- **Content rights**: the app contains no third-party content beyond the credited cat recordings (Wikimedia Commons, credited in Licences and credits).
- **Sign-in required**: No. There is no account and no demo login.
- **Version**: 1.0, build 1. The Info.plists set these; raise the build number for each upload.

## Notes for App Review (paste into "Notes")

```
No account or sign-in. The game opens with a short intro (skippable) and the cat builder; after that you are in the cat's home.

Where things are (landscape):
- Shop: the gold Shop button, bottom right of the room. Its pages are tabs along the top: Offers (the Starter Pack, a room look, the way into Cat Club), Beans (the five packs), Room looks, Outfits and Cat Club; a Season pass tab joins them while a season is on. Every product can be bought there. Bought Beans appear at once in the balance at the top right.
- Cat Club page (the last tab): Restore Purchases, Terms of Use and Privacy Policy are at the foot of the page; the price that will be charged is on the button.
- Restore Purchases, Request a refund, Manage subscription, Terms of Use, Privacy Policy and Help also run along the foot of every shop page, and are in Settings (tap the cat's portrait at the top left, then Settings, then "Purchases and help").
- Menu (top left, under the portrait): Goals, Map, Book, the Pass, and the Gift track while one runs.
- Season pass: always on (a season is running now, Black Cat until 1 November). The badge at the top right of the room, under the Beans and the streak, opens it, as does the menu's Pass. Get Premium shows all 30 premium rewards, the ones that open at once, the season's last day and the price before anything is bought; Restore Purchases, Terms and Privacy are on that panel. The premium pass is paid once for its season; Cat Club also includes it. Nothing on either track is random.

Beans are the one currency: earned every day by playing and sold in fixed packs. Nothing bought is random. A room look puts a whole room's furniture, wallpaper and floor in at once, and can be tried in the room before buying.

Optional Apple Health (steps, sleep, workouts; read only) is offered on the third day of play and is in Settings. It only gives extra XP. Nothing is written to Health or leaves the device.

Notifications are local, at times the player chooses, offered after the first feed.

Weather comes from WeatherKit for the home's pinned place (no device location is used). The Apple Weather mark and link are in Settings.

Your data, in Settings: Export my data shares the whole save as a file; Delete all my data (two confirmations) deletes the save, the widget's files, preferences and reminders, and starts again from the intro. There is no account to delete.

The Apple Watch app and widgets show the cat, its mood and the streak; the Watch can feed and stroke.
```

## Launch checklist: what Josh does

### Apple Developer and App Store Connect

1. **Team**: join the Apple Developer Program, then put the Team ID in `project.yml` (`DEVELOPMENT_TEAM`) and run `xcodegen generate`.
2. **App IDs**: `com.housecatgame.housecat` and its extensions (`.widgets`, `.downloader`, `.watchkitapp`, `.watchkitapp.complication`). Each needs the App Group `group.com.housecatgame.housecat`. Add these capabilities:
   - The app: HealthKit, WeatherKit, In-App Purchase, Background Assets, Push Notifications (not used yet; leave it off).
   - iCloud/CloudKit: only when co-owning ships.
3. **App record**: create it with the bundle ID above, primary language English (UK), SKU `housecat`.
4. **Agreements, tax and banking**: sign the Paid Apps agreement. In-app purchases can't be reviewed without it.
5. **In-app purchases**:
   - Create the 21 products in the table, with the same IDs, types, prices, names and descriptions.
   - Create the subscription group "Cat Club" with both plans at the same level (1), as the StoreKit configuration has them, and a 1-week free introductory offer on the yearly plan.
   - Add a review screenshot to each.
   - Submit them with the first build.
6. **Background Assets**: upload the exterior packs (`CLAUDE.md`, "Background Assets"), or the other homes fall back to the city scenes.
7. **App Privacy, age rating and export compliance**: as above.
8. **Pricing and availability**: free. Turn off Mac and Vision Pro availability.
9. **TestFlight**: archive the HouseCat scheme (Release) and upload. Test on a real iPhone and iPad: buy each kind of product in the sandbox, and check Restore on a second device.
10. **Screenshots**: upload `iphone-6.9/01-08`, `ipad-13/01-08` and `watch/01-04` (not the `review_*` files, which are for the in-app purchases).

### Decisions before submitting

- **RevenueCat**: set `RevenueCatAPIKey` or leave it empty. The app uses StoreKit 2 directly without it. The privacy policy and the App Privacy answers must match the choice.
- **PostHog analytics**: same choice. Empty means no analytics and no switch in Settings.
- **Season dates**: seasons run back to back on `SeasonCalendar` and the pass is always on: Black Cat 5 Oct to 1 Nov 2026 (so TestFlight and App Review see the pass), Housewarming 2 Nov to 30 Nov (the launch season; the launch events still count from 2 Nov, `launchAt` in `Content/seasons.json`), Midwinter every December, First Light to 25 Jan 2027. After that, seasons run again until the 2027 seasons (CONTENT.md §7) are painted.
- **Premium pass price**: £2.99 a season (Josh approved it on 20 Oct), the same as a month of Cat Club, which includes it.
- **Mac menu-bar cat**: leave it out of 1.0. It has no App Sandbox and can't reach the iPhone's cat, so review would reject it under minimum functionality. To ship it later, it needs the sandbox, the App Group and a privacy manifest.
- **Co-owning**: left out of 1.0 and planned for 1.1. Leave, Stop sharing, Hide and Report are built (19 Oct). Co-owner names go through the name filter. To ship it, it needs the iCloud container on the App ID, `HouseCatCloudKit` set to true and two-phone testing (CLAUDE.md, "To switch sharing on"). The website and App Store Connect lines it needs are in `sharing-1.1.md`.

### Website (Hostinger)

1. The domain housecatgame.com is registered (Hostinger, 19 Oct). Point it at the hosting plan.
2. Apply `website_fixes.md`, then upload the contents of `website/` (not `_to_delete/`) to `public_html`.
3. Create the mailboxes `support@housecatgame.com` and `safety@housecatgame.com` in Hostinger's email.
4. Check that https://housecatgame.com/privacy/, /terms/ and /support/ load before submitting. App Review opens them.

## Screenshot order and captions

Captions are for overlay text if wanted. Apple shows the screenshots as they are.

| # | iPhone file | iPad file | Caption |
| --- | --- | --- | --- |
| 1 | 01_room.png | 01_room.png | Your cat runs to meet you every day |
| 2 | 02_decorate.png | 02_decorate.png | Make every room your own |
| 3 | 03_game.png | 03_game.png | Laser pointer, knock-it-off and string chase |
| 4 | 04_goals.png | 04_goals.png | Goals today, this week and for good |
| 5 | 05_evening.png | 05_evening.png | Real weather and seasons where you live |
| 6 | 06_profile.png | 06_profile.png | Your cat, its look, its book |
| 7 | 07_intro.png | 07_intro.png | A cat, a home, anywhere in the world |
| 8 | 08_level_up.png | 08_level_up.png | Level up and open new rooms |

| # | Watch file | Caption |
| --- | --- | --- |
| 1 | 01_cat.png | Your cat and your streak on your wrist |
| 2 | 02_stroke.png | A stroke from your wrist |
| 3 | 03_fed.png | Breakfast without opening your phone |
| 4 | 04_complications.png | The streak on your watch face |
