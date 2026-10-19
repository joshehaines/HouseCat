# Website: what to correct before upload (19 Oct 2026)

The site in `website/` was built outside this repo's sessions (a Cowork session was still editing `support/index.html` at 15:37), so nothing here has been changed in it. App Review reads the privacy policy and the support page, and they must describe the app that is submitted. Against version 1.0 as it stands (commit aaa050f3), these lines are wrong.

## What 1.0 does and does not have

- **No co-owning, groups or cat-sitting.** Sharing is built but switched off until the iCloud container is set up. The Settings card is hidden, and there are no groups, no cat-sitting, and no Report, Remove or Leave controls.
- **No iCloud sync.** The save is on the device only. It is also in the person's iCloud or computer backup, if they use one. Health results are not synced either.
- **No crash-reporting SDK.** There is no Sentry. The only crash reports are Apple's own, sent when the person shares analytics with app developers in iOS Settings.
- **No usage analytics in this build.** The PostHog key is empty, so the "Help improve HouseCat" switch does not appear. If a key is added later, the switch is called "Help improve HouseCat", not "Share anonymous usage".
- **RevenueCat is not used** unless its key is set before launch. Without it, purchases go straight through Apple's StoreKit.
- **No Mac app in 1.0.** The menu-bar companion can't reach the iPhone's cat, so don't submit it. Apple Watch and widgets are in.
- **No anonymous ID** is shown in the app's settings.
- **Purchases and help** are in the app's settings, as the site says: Restore Purchases, Manage subscription, Request a refund, Help and support, Terms, Privacy.

## Line by line

| File | Now says | Change to |
| --- | --- | --- |
| index.html | "For iPhone and iPad, with widgets, Apple Watch and a Mac menu-bar cat." | "For iPhone and iPad, with widgets and Apple Watch." |
| index.html | "...Keep the streak going, or share it with someone you live with." | "...Keep the streak going." |
| index.html | "Your save lives on your device and in your own iCloud." | "Your save lives on your device. We can't see it." |
| index.html | "Coming soon to the App Store" (two places) | Fine until launch day; then swap in the App Store badge and link (`https://apps.apple.com/app/id<APP_ID>`). |
| privacy | Short version: "Your game save stays on your device and in your own iCloud." | "Your game save stays on your device (and in your device backup, if you make one). We cannot see it." |
| privacy | "If iCloud is on, Apple syncs it to your own private iCloud database so your iPhone, iPad, Apple Watch and Mac stay in step..." | "It is included in your iCloud or computer backup if you back up your device. Your Apple Watch gets a small copy (your cat, its mood and your streak) from your iPhone." |
| privacy | The whole "Sharing a cat or joining a group" section | Remove for 1.0. Add it back, with a Report and Leave in the app, when co-owning ships. |
| privacy | Health: "Only simple yes/no results (for example "walk goal met") are saved, encrypted, to your own iCloud." | "Only simple yes/no results (for example "walk goal met") are kept in the save on your device." |
| privacy | Providers: "PostHog (EU servers): Only if you turn on "Share anonymous usage"..." | Remove for 1.0, or rename the switch "Help improve HouseCat" if a PostHog key goes in before launch. |
| privacy | Providers: "Sentry: If the app crashes..." | Remove. Optionally add: "Apple: crash reports, only if you choose to share analytics with app developers in your device's settings." |
| privacy | Providers: "RevenueCat: Receipts for your purchases..." | Keep only if the RevenueCat key is set before launch. |
| privacy | Legal basis: "...and our legitimate interest in keeping the app working (crash reports)." | Drop "(crash reports)", or drop the clause. |
| privacy | Retention: "Shared cards: until you leave the group or the share ends; friend codes expire after two days." | Remove. |
| privacy | Retention: "Usage counts and crash reports: up to 12 months" | "Usage counts (if switched on): up to 12 months", or remove. |
| privacy | Retention: "Your save: until you delete it in the app or remove it from iCloud." | "Your save: until you delete it in the app or delete the app." |
| privacy | "...include the anonymous ID shown in the app's settings." | "...tell us roughly when you started playing and your cat's name." |
| terms | "HouseCat for iPhone, iPad, Apple Watch and Mac" | "HouseCat for iPhone, iPad and Apple Watch" |
| terms | Beans "are shared by everyone in your household." | Remove the clause. |
| terms | "5. Groups, co-owning and cat-sitting" | Remove for 1.0 (renumber), or one line: "Sharing a cat with someone is not in this version." |
| terms | "Your save is kept on your device and in your own iCloud. We can't see or restore it for you, so if you delete it, or delete it in iCloud, it is gone." | "Your save is kept on your device. We can't see or restore it for you, so if you delete it, or delete the app without a backup, it is gone." |
| support | "...Room looks and Cat Club come back; your save comes back through iCloud." | "...Room looks and Cat Club come back. Your cat and home come back when you restore the device from an iCloud or computer backup." |
| support | "How do I co-own a cat with someone?" | Remove for 1.0. |
| support | "Someone in my group is being unkind" | Remove for 1.0. Keep safety@housecatgame.com as a general contact if wanted. |
| support | Delete my data: "...It deletes your save, reminders and your household in iCloud." | "...It deletes your save, the widget's copy, your reminders and your settings." |

## After any change

Re-make the upload bundle the site tool left in `website/_to_delete/` (or zip `website/` without `_to_delete`). The app links to `https://housecatgame.com/terms/`, `/privacy/` and `/support/` (`Tuning.Store`). The site's `.htaccess` already redirects to https and drops `www`.

## Status

Done 19 Oct 2026, 16:15: every change above is live on housecatgame.com (the site is built from `website/src/` by `website/build.py`; launch-day switch in `website/site.json`). The site uses this folder's 19 Oct screenshots.
