# HouseCat: App Store listing, review notes and launch checklist (updated 25 Oct 2026)

This file holds everything App Store Connect asks for, ready to paste. It is written against version 1.0 as built at commit aaa050f3 and after. Prices are UK tiers; StoreKit shows each player their own. The website's corrections are in `website_fixes.md`.

## Listing

- **Name** (30): HouseCat
- **Subtitle** (30): Cosy cat game & virtual pet
- **Promotional text** (170): Start in a run-down terrace with a cat who needs a home, and work your way up to a mansion flat in London. Feed, play and decorate every day.
- **Keywords** (100): kitten,cozy,kitty,decorate,home,house,interior,cute,widget,daily,care,collect,dress up,relaxing,sim (Josh, 25 Oct, the ASO playbook: no word repeated from the name or subtitle, no trademarks)
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

A cat who needs a home, and a home that grows with you.

HouseCat starts in a run-down terrace in the little town of Puddlebury, with a cat waiting at the door. Make the cat your own in the cat creator: start from one of 23 looks, then change the coat, pattern, eyes, ears and tail, and give it a name.

Every visit, your cat notices you, hops down and comes over to say hello, then gets on with its day: a nap in the sun, a loaf on the sofa, a scratch at the post, zoomies at dusk. Feed it, stroke it and play with it, and most days it brings you a present for its book.

Care for your cat, finish each home's tasks and save your Beans, and you move up the ladder: a houseboat on an Amsterdam canal, a cabin outside Vancouver, a cottage in Queenstown, a new-build in Tokyo, a rooftop in Santorini, a townhouse in New York and, at the top, a mansion flat in London. Every home is bigger than the last, comes with another room, and sits in its own painted street, with that town's sky, seasons and weather. Your furniture moves with you.

Make every room cosy: pick a piece up, drag it, turn it and put it down, with wallpapers and floors to change. Goals for today and this week, each home's tasks and milestones always give you something to look forward to, and a new season every four weeks fills a free track with furniture and an outfit.

Your cat lives on your Home Screen and your Apple Watch too, waiting in the window until you visit, with your streak. Miss a day and it sulks a little; it never leaves, and nothing is ever lost.

- Beans are earned every day in play and also sold in packs. Room looks are kept for good. The season's premium pass is an optional one-off purchase for that season.
- Cat Club is an optional subscription: +20% Beans, a daily treat of Beans and pass XP, and a streak shield that saves a missed day each month. Yearly with a 7-day free trial, or monthly. It renews automatically unless cancelled at least 24 hours before the end of the period, in your Apple Account settings.
- Nothing is random for money. No ads, no account.
- Optional: Apple Health. With your permission HouseCat reads your steps, sleep and workouts to give extra XP. It never writes to Health, and the data stays on your device.

Terms of Use: https://housecatgame.com/terms/
Privacy Policy: https://housecatgame.com/privacy/
Weather: Apple Weather.

## Screenshots

Ten a device, in story order (23 Oct, after Apple's "App Store asset best practices"): your cat at home, making the cat, the opening's run-down terrace, the house ladder, a home in its town, decorating, a game, the season pass, the profile, the goals. Each is a real screen from the current build with a short caption above it in the website's fonts (Young Serif, Figtree) on a brand background; no prices, URLs or awards (the pass is shown owned, so no price shows).

- **iPhone 6.9"** (landscape, 2868 × 1320): `iphone-6.9/`
- **iPhone 6.3"** (landscape, 2622 × 1206; the required size): `iphone-6.3/`
- **iPad 13"** (portrait, 2064 × 2752): `ipad-13/`
- **Apple Watch** (46 mm, 416 × 496): `watch/`. App Store Connect asks for these because the Watch app ships inside the iPhone app.
- **iPhone Duo, outer display** (landscape, 2034 × 1398): `iphone-duo-outer/` (25 Oct). In App Store Connect as `APP_IPHONE_DUO` for now (see below).
- **iPhone Duo, inner display** (landscape, 2853 × 2007): `iphone-duo-inner/`. Not made yet (see below).

### iPhone Duo

Apple requires iPhone Duo screenshots from April 2027 for any app built with the iOS 27.1 SDK or later, and an app that has them gets an "optimized for iPhone Duo" badge (App Store Connect's screenshot specifications, checked 25 Oct). App Store Connect has a single display type for it, `APP_IPHONE_DUO`: there is no separate inner and outer type. The API accepts it, though Apple's published OpenAPI spec (4.5.1) doesn't list it yet. One set holds at most ten, so the inner set is the one to keep there (agreed 25 Oct). Until it is made, the outer set stands in: uploaded through the API to version 1.0's en-GB localization on 25 Oct (set 09e49b7a-ffc1-45ae-9733-d54add3996b4), all ten processed.

- **The simulator**: the iPhone Duo device type needs the iOS 27.1 simulator runtime (downloaded 25 Oct with `xcodebuild -downloadPlatform iOS -buildVersion 27.1`, 7.9 GB). The device is `iPhone Duo` (DEF91508-C6BA-48B3-8DBF-4E805E7246AF). It boots folded, with the app on the outer display. `xcrun simctl io <udid> screenshot --display=<port uuid>` takes either display; `simctl io <udid> enumerate` lists the ports (1398 wide is the outer, 2007 the inner), and their UUIDs change on every boot.
- **Folding**: simctl can't fold the Duo. Powering the displays with `screenConfig power` doesn't move the app, and the inner display stays black. Fold and unfold from Device Hub (Xcode 27.1's replacement for Simulator.app).
- **The outer set**: the same shots, order and captions as `iphone-6.9/` (`tools/store/screenshots.json`), composed with `compose_screenshots.py … duoouter`. They come from the same seeded home: `HOUSECAT_SCREEN=shot HOUSECAT_RUNG=1 HOUSECAT_TIME=day` (home), `RUNG=2` (the houseboat), `SCREEN=decorate RUNG=3`, `SCREEN=game:string_chase HOUSECAT_AUTOPLAY=1`, `SCREEN=pass HOUSECAT_PASS_OWNED=1`, `profile`, `goals`, `homes` and `cutscene`. The builder is `SCREEN=editlook HOUSECAT_CREATOR=looks`: the profile's Edit look, with no tip to tap away, so the cat is Pip's own Midnight rather than the 6.9" set's Ginger Tabby. The compositor paints out the camera dot the simulator draws into a corner (`clean_camera`), as it does the Dynamic Island.
- **Layout**: the outer screen is 678 × 466 points with the camera in a corner. The app has been checked there screen by screen (25 Oct): the room, the builder, the tour, Homes, the shop, the pass, the profile, the goals, the menu, outside, decorate, the games menu and every game. Fixed for it, all needing a new binary (build 4 or 1.0.1): the room's controls and the builder's columns move in past the camera (`CameraClearance`, iOS 27.1's occlusion regions); the builder draws at down to 0.8 on a screen narrower than its 800-point design, with Surprise me as its dice alone under the narrow stage; the goal tracker's header and a quick game's title keep to one line. The inner display and a fold or unfold while the app runs are not checked yet.
- **To finish**: fold the Duo open in Device Hub, check the same screens on the inner display (951 × 669 points) and through a fold and an unfold, then capture the ten again with `duoinner` into `iphone-duo-inner/`. Delete the outer ten from the `APP_IPHONE_DUO` set and upload the inner ten in their place.

Made from a debug build on the iPhone 18 Pro Max and iPad Pro 13-inch simulators with the seeded home (`HOUSECAT_HOUSE=full HOUSECAT_CAT=midnight HOUSECAT_SKIP_STORE=1`, a `HOUSECAT_SCREEN` value so the day-3 cards stay away), `HOUSECAT_RUNG`, `HOUSECAT_ROOM=living`, `HOUSECAT_TIME` and `HOUSECAT_ZOOM` (the camera's starting zoom), and the pass with `HOUSECAT_PASS_OWNED=1`; the creator's tip tapped away. The simulator's Dynamic Island is painted out of the iPhone frames. The compositing script (captions, background, rounded screen) is `tools/store/compose_screenshots.py` with `tools/store/screenshots.json`.

The Watch set was taken on 20 Oct on the Apple Watch Series 12 (46mm) simulator paired with the iPhone 18 Pro, from a debug build: the iPhone app first, with the seeded home (`HOUSECAT_HOUSE=full HOUSECAT_CAT=midnight HOUSECAT_SKIP_STORE=1` on a fresh install), so the Watch has its snapshot; then the Watch app, freshly installed so no older snapshot is left on it, with `HOUSECAT_WATCH_TAPS=pet` and `=feed` for the cat's replies and `HOUSECAT_SCREEN=complications` for every complication family.

The shop is not in the marketing set: a simulator launch from the command line has no test products, so it shows the catalogue's UK prices in a debug build (`HOUSECAT_SKIP_STORE=1`) and "…" otherwise. For each in-app purchase's review screenshot, use `iphone-6.9/review_beans.png` (the five Bean packs), `review_offers.png` (the Starter Pack), `review_room_looks.png` (the room looks), `review_pass.png` (the four season passes: the pass screen with Get Premium · £2.99, taken 20 Oct with `HOUSECAT_SCREEN=pass`) and `review_cat_club.png` (both plans, with the billed price on the button), all taken 19 Oct from the redesigned shop with `HOUSECAT_SCREEN=shop HOUSECAT_SHOP=beans|offers|looks|club`; or run from Xcode (the scheme loads `Store/HouseCat.storekit`) for StoreKit's own prices.

## In-app purchases (21, matching `Store/HouseCat.storekit`)

| Product ID | Type | Price | Display name (30) | Description (45) |
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
| housecat.pass.blackcat | Non-consumable | £4.99 | Black Cat Premium Pass | The Black Cat season's 30 premium rewards. |
| housecat.pass.housewarming | Non-consumable | £4.99 | Housewarming Premium Pass | The Housewarming season's 30 premium rewards. |
| housecat.pass.midwinter | Non-consumable | £4.99 | Midwinter Premium Pass | The Midwinter season's 30 premium rewards. |
| housecat.pass.firstlight | Non-consumable | £4.99 | First Light Premium Pass | The First Light season's 30 premium rewards. |
| housecat.club.monthly | Auto-renewable (group "Cat Club", level 1) | £2.99 / month | Cat Club Monthly | +20% Beans, a daily treat and a streak shield. |
| housecat.club.yearly | Auto-renewable (group "Cat Club", level 1) | £19.99 / year, 1-week free trial | Cat Club Yearly | +20% Beans, a daily treat and a streak shield. |

- The Housewarming look's product ID keeps its earlier name, because IDs can never be renamed once live.
- Apple's limits are 30 characters for a display name and 45 for a description (App Store Connect's in-app purchase reference, checked 21 Oct); some descriptions above run longer, so check each saved one in App Store Connect ends on a whole word.
- Family Sharing is on for Cat Club only, as the StoreKit configuration has it. A room look's pieces go into one household's save. Turning Family Sharing on in App Store Connect cannot be undone.
- Each season sells its own premium pass (Josh, 19 Oct: the pass is the main thing sold): `housecat.pass.<season>`, non-consumable, paid once, brought back by Restore Purchases, the same price every season. Create one for each season in `Content/seasons.json` (four now) and add each new season's before it starts. A season that has no pass of its own runs an earlier one again (`SeasonSchedule`) and sells that one's pass, so no product is ever missing.
- Each product needs a review screenshot (see Screenshots) and, for the subscription group, a display name ("Cat Club").

## App Privacy (the App Store Connect questionnaire)

1.0 ships with RevenueCat (purchases) and PostHog (anonymous usage counts, opt-in), their keys set in `project.yml` before the upload (Josh, 21 Oct: "ok lets implement both"; the steps are in the checklist). Answer as if both keys are set, and the two privacy manifests (`App/Resources/PrivacyInfo.xcprivacy`, RevenueCat's own) already say the same.

- **Data collection**: "Yes, we collect data from this app."
- **Purchases → Purchase History**: collected. Used for: App Functionality. Linked to the user's identity: No (RevenueCat keeps an anonymous app user ID; no name, email or account). Used for tracking: No.
- **Usage Data → Product Interaction**: collected. Used for: Analytics. Linked to the user's identity: No (a fresh random ID each launch, no person profiles). Used for tracking: No. Sent only after the player says yes to "Help improve HouseCat?" (the card on the second day, or the switch in Settings); off by default.
- Nothing else is collected: the save, Health results and settings stay on the device. Weather requests send the pinned place's coordinates to Apple WeatherKit, place search goes to Apple Maps and purchases go through Apple; Apple, not us, is responsible for those.
- **Tracking**: No. There is no IDFA, no App Tracking Transparency prompt and nothing is shared with data brokers.
- If 1.0 goes out with a key still empty, that data is simply not collected; the answers above then say more than happens, which is allowed, so leave them.

## Other App Store Connect answers

- **Export compliance**: `ITSAppUsesNonExemptEncryption` is NO. The app uses only Apple's HTTPS.
- **Content rights**: the app contains no third-party content beyond the credited cat recordings (Wikimedia Commons, credited in Licences and credits).
- **Sign-in required**: No. There is no account and no demo login.
- **Version**: 1.0, build 1. `project.yml` sets these once for every target (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`; the Info.plists read them): raise `CURRENT_PROJECT_VERSION` for each upload and run `xcodegen generate`.

## Notes for App Review (in App Store Connect since 25 Oct, by the API)

```
No account or sign-in. The game opens with a short story (skippable), then the cat creator; after that you are in the cat's first home. The tour shows Feed, stroking and furnishing.

Where things are (landscape on iPhone, any way up on iPad):
- Shop: the gold Shop button, bottom right of the room. Tabs along the top: Offers (the Starter Pack, a room look, the way into Cat Club), Season pass, Beans (five packs), Room looks, Outfits and Cat Club. Every product can be bought there; bought Beans appear at once in the balance at the top right.
- Cat Club page (the last tab): its perks, both plans with their prices, Restore Purchases, Terms of Use and Privacy Policy. Restore Purchases, Request a refund, Manage subscription, Terms, Privacy and Help also run along the foot of every shop page, and are in Settings (tap the cat's portrait at the top left, then Settings).
- Menu (top left): Goals, Homes (the ladder of eight homes; the next one is bought with Beans once its level and tasks are done), Book, Pass, Outside (the house from outside).
- Season pass: a season is always running (Black Cat until 1 November, then Housewarming). The badge at the top right opens it. Get Premium shows every premium reward, what opens at once, the season's last day and the price before anything is bought. It is paid once for its season and is not part of Cat Club. Nothing on either track is random.

Cat Club (auto-renewable, monthly or yearly with a 7-day free trial): +20% on the Beans earned that day, a daily treat (30 Beans and pass XP on the first visit of the day) and a streak shield that holds one missed day a month beyond the free weekly one.

Beans are the one currency, earned every day by playing and sold in fixed packs. Nothing bought is random; the daily present is earned only and no purchase changes it.

Homes 2 to 8 download their outside paintings as Apple-hosted asset packs (Background Assets) when you move in; the game works fully while they arrive.

Optional Apple Health (steps, sleep, workouts; read only) is offered on the third day and in Settings. It only gives extra XP; nothing is written to Health or leaves the device. Notifications are local, at times the player chooses.

Weather comes from WeatherKit for the town of the home (no device location is used). The Apple Weather mark and link are shown wherever that weather is on screen.

Your data, in Settings: Export my data shares the save as a file; Delete all my data deletes the save, the widget's files, preferences and reminders and starts again. There is no account to delete.

The Apple Watch app and widgets show the cat, its mood and the streak; the Watch can feed and stroke. Nothing is hidden or dormant: co-owning a cat is built but switched off for 1.0 (no control reaches it). Debug switches are compiled out of this build.
```

## Launch checklist: what Josh does

### Apple Developer and App Store Connect

1. **Team**: done 20 Oct. Josh joined the Apple Developer Program; `DEVELOPMENT_TEAM` is 3UDHUPMKDF in `project.yml`.
2. **App IDs**: registered on 20 Oct by Xcode's automatic signing (Josh's go-ahead), along with a signed Release archive ("HouseCat 20-10-2026, 15.21" in Xcode's Organizer): `com.housecatgame.housecat` and its extensions (`.widgets`, `.downloader`, `.watchkitapp`, `.watchkitapp.widgets`; the portal refused `.watchkitapp.complication` as not available). Each needs the App Group `group.com.housecatgame.housecat`. Add these capabilities:
   - The app: HealthKit, WeatherKit, In-App Purchase, Background Assets, Push Notifications (not used yet; leave it off).
   - iCloud/CloudKit: only when co-owning ships.
3. **App record**: create it with the bundle ID above, primary language English (UK), SKU `housecat`.
4. **Agreements, tax and banking**: sign the Paid Apps agreement. In-app purchases can't be reviewed without it.
5. **In-app purchases**:
   - Create the 21 products in the table, with the same IDs, types, prices, names and descriptions.
   - Create the subscription group "Cat Club" with both plans at the same level (1), as the StoreKit configuration has them, and a 1-week free introductory offer on the yearly plan.
   - Add a review screenshot to each.
   - Submit them with the first build.
6. **Background Assets**: upload the seven exterior packs (`CLAUDE.md`, "Background Assets"), or every home but the London terrace has no cold open and no Outside view (the visit starts inside; nothing looks broken, the outside is simply missing).
   - *21 Oct 2026*: the packs were rebuilt from main at `147d74ac` into `~/Library/Caches/HouseCat/packs` and checked (ids `home-mansion-flat`, `home-cottage`, `home-georgian-townhouse`, `home-newbuild-balcony`, `home-houseboat`, `home-mediterranean-rooftop`, `home-woodland-cabin`; the first upload attempt failed because App Store Connect allows only letters, digits and hyphens in a pack id, so the dots and underscores went that day; `home_<style>.aar`, 45–53 MB each, 192 pictures and an `art.json` under `homes/<style>/`, iOS, on demand). **Uploaded 21 Oct, 20:13–20:26** with Josh's API key: all seven are version 1, *Ready for Internal Testing* (altool `READY_FOR_TESTING`), nothing submitted for review yet. The pictures are byte for byte what the 18 Oct build made; the 19–20 Oct scene changes (doors, house boxes, windows in `scenes.json`) ship inside the app, not in the packs.
   - **Upload** (Josh, or any session once the key is at `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8`), one command a pack; `--wait` returns when Apple has processed it:
     ```bash
     cd ~/Library/Caches/HouseCat/packs && for p in home_*.aar; do xcrun altool --upload-asset-pack "$p" --apple-id 6825008474 --api-key <KEYID> --api-issuer <ISSUERID> --wait; done
     ```
     Then `xcrun altool --list-asset-packs --apple-id 6825008474 --api-key <KEYID> --api-issuer <ISSUERID>` lists them. Each upload becomes a new version of its pack id automatically (there is no version in the manifest; never try to re-upload "the same" version). Transporter (Mac App Store) accepts the `.aar` files by drag and drop too; it is not installed here.
   - **Where they show**: App Store Connect → the app → TestFlight → Builds & Assets → Asset Packs (the section appears after the first upload). Processing ends with an email; the version then reads *Ready for Internal Testing* and internal TestFlight testers get it with no further step. External TestFlight needs each pack sent to TestFlight App Review (Asset Packs → the pack → Set Up External Testing → the version → Submit for Review). Testers must be signed in with the Apple Account that has the beta; sandbox accounts don't get packs. A development build from Xcode never gets them: test those with `HOUSECAT_PACKS` in the simulator or `xcrun ba-serve`.
   - **With the 1.0 submission**: the packs must be in the same App Review submission as the first app version (Apple's rule for an app not yet approved). In the app's Distribution tab → General → Asset Packs, for each of the seven: Select Asset Pack Version → the version → Add for Review → the 1.0 submission. A submission holds at most ten packs. Once approved they are live for every App Store version of the app; later pack versions can be submitted on their own.
   - **After an art change** to `assets/world/scenes/<style>_*`: `python3 -I tools/app-assets/build_home_packs.py <style>` (all seven with no argument), upload the changed `.aar` as above, and submit the new version (internal TestFlight takes it as soon as it is processed). A change to `scenes.json` alone needs an app build, not a pack; a change to both must ship together. Never click Archive on a pack: it deletes every version and the id can never be used again.
7. **App Privacy, age rating and export compliance**: as above.
8. **Pricing and availability**: free. Turn off Mac and Vision Pro availability.
9. **TestFlight**: archive the HouseCat scheme (Release) and upload. Test on a real iPhone and iPad: buy each kind of product in the sandbox, and check Restore on a second device.
10. **Screenshots**: upload `iphone-6.9/01-08`, `ipad-13/01-08` and `watch/01-04` (not the `review_*` files, which are for the in-app purchases). iPhone Duo (`APP_IPHONE_DUO`): `iphone-duo-outer/01-10` are up as a stand-in, to be replaced by `iphone-duo-inner/01-10` once made (see "iPhone Duo" under Screenshots). Required from April 2027 for a build made with the iOS 27.1 SDK.
11. **Legal name**: the account's legal name reads "JOSHUA EDWARD HAINCS" (seen 20 Oct). Ask Apple Developer Support to correct it before the Paid Apps Agreement goes Active, so tax forms and payouts match the bank account.
12. **EU trader status (Digital Services Act)**: in App Store Connect → Business → Compliance, declare trader status and give a verified address, phone and email (the support address is fine). Selling in-app purchases makes you a trader; Apple asks at first submission and won't distribute in the EU without it.
13. **Age rating**: answer the current questionnaire (the 2025 one with the 13+/16+/18+ tiers and the social-media questions added in September 2026); the answers in "Listing" above still apply. Expect 4+.
14. **WeatherKit**: on developer.apple.com, open the App ID `com.housecatgame.housecat` and check WeatherKit is ticked under both Capabilities and App Services. Without the App Services tick, weather requests fail on a real device with a 401 and the app falls back to no weather.
15. **App Store Connect API key** (for uploading the home packs and builds from the command line): Users and Access → Integrations → App Store Connect API → Team Keys → Generate, role App Manager; download the `.p8` once, and keep the Key ID and Issuer ID with it. Put the file at `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8` on the Mac (make the folder; `altool` looks there) and tell the session that uploads the Key ID and Issuer ID (they are not secrets; the `.p8` is, so never paste it into a chat or commit it).

### Decisions before submitting

- **RevenueCat and PostHog**: both in 1.0 (Josh, 21 Oct: "ok lets implement both"). Each comes alive the moment its key is set in `project.yml` (`RevenueCatAPIKey`, `PostHogAPIKey`) and the project is regenerated; empty, the app uses StoreKit 2 directly and shows no analytics card or switch. The App Privacy answers above assume both keys are set. The steps are under "RevenueCat and PostHog" in the checklist.
- **Season dates**: seasons run back to back on `SeasonCalendar` and the pass is always on: Black Cat 5 Oct to 1 Nov 2026 (so TestFlight and App Review see the pass), Housewarming 2 Nov to 30 Nov (the launch season; the launch events still count from 2 Nov, `launchAt` in `Content/seasons.json`), Midwinter every December, First Light to 25 Jan 2027. After that, seasons run again until the 2027 seasons (CONTENT.md §7) are painted.
- **Premium pass price**: £4.99 a season (Josh, 23 Oct; was £2.99), set the four pass IAPs to that tier in App Store Connect. Cat Club does not include it (Josh, 23 Oct).
- **Mac menu-bar cat**: leave it out of 1.0. It has no App Sandbox and can't reach the iPhone's cat, so review would reject it under minimum functionality. To ship it later, it needs the sandbox, the App Group and a privacy manifest.
- **Co-owning**: left out of 1.0 and planned for 1.1. Leave, Stop sharing, Hide and Report are built (19 Oct). Co-owner names go through the name filter. To ship it, it needs the iCloud container on the App ID, `HouseCatCloudKit` set to true and two-phone testing (CLAUDE.md, "To switch sharing on"). The website and App Store Connect lines it needs are in `sharing-1.1.md`.

### RevenueCat and PostHog (Josh, 21 Oct: both in 1.0)

RevenueCat, click by click:

1. revenuecat.com → Sign up (the free plan covers the launch; it charges only past $2,500 a month of tracked revenue) → "Create new project" → name it HouseCat.
2. App Store Connect → Users and Access → Integrations → In-App Purchase → "Generate In-App Purchase Key" → name it RevenueCat → Generate → Download the `.p8` once (it can't be downloaded again) and note the Key ID beside it and the Issuer ID shown above the list. This is the key RevenueCat needs; the App Store Connect API key in step 15 above is a different one.
3. RevenueCat → Project settings → Apps → "+ New" → App Store → App name HouseCat, Bundle ID `com.housecatgame.housecat` → under "In-app purchase key configuration" upload the `.p8`, paste the Key ID and the Issuer ID → Save.
4. On the same app page RevenueCat shows "Apple Server to Server notification URL" → Copy. App Store Connect → Apps → HouseCat → App Information → "App Store Server Notifications" → paste it into Production Server URL and Sandbox Server URL, Version 2 Notifications → Save. (So RevenueCat hears renewals, refunds and Ask to Buy; the app derives entitlements itself either way.)
5. RevenueCat → Product catalog → Products → "+ New" (or "Import" once App Store Connect has the 21 products and the key is set): every ID from the table above. Entitlements → "+ New" → identifier `club` → attach `housecat.club.monthly` and `housecat.club.yearly`. The app works out room looks and passes from the product IDs, so no other entitlement is needed; `club` keeps the dashboard honest.
6. RevenueCat → Project settings → API keys → "Public app-specific API keys" → copy the App Store one (`appl_…`) → paste into `project.yml` as `RevenueCatAPIKey` → `xcodegen generate` → rebuild. Never the secret key, and never commit anything but the public one.
7. Check: a sandbox purchase on a TestFlight build shows under RevenueCat → Customers within a minute.

PostHog, click by click:

1. posthog.com → Get started → choose **EU Cloud** (the app posts to `eu.i.posthog.com`, `Tuning.Analytics.endpoint`; US Cloud would silently receive nothing) → Create project → name it HouseCat → skip the SDK wizard (the app sends its events itself, with no PostHog SDK).
2. Project settings → "Project API key" (`phc_…`) → paste into `project.yml` as `PostHogAPIKey` → `xcodegen generate` → rebuild.
3. Project settings → Persons & groups: leave person profiles off for anonymous events (the app already sends every event with `$process_person_profile: false`). Nothing else to set.
4. Check: on a build with the key, say yes on the "Help improve HouseCat?" card (`HOUSECAT_SCREEN=analytics` shows it at once in a debug build), play, and the events (`intro_finished`, `first_feed`, `shop_opened`…) appear under Activity.

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
