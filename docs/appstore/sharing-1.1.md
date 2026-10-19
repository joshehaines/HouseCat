# Sharing a cat in 1.1: what the website and App Store Connect need

Co-owning is hidden in 1.0 and will lead 1.1. The app's side is ready but switched off (CLAUDE.md, "Co-owning for 1.1"). When it is switched on, the website and the App Store answers have to describe it. This file lists the lines to add. The site is built outside this repo from `website/src/`, so nothing here has been changed on the site.

Put these lines up on the day 1.1 is submitted, not before. Until then the site should keep saying that sharing isn't in the app, as `website_fixes.md` set it.

## What 1.1 does, in plain words

- **Sharing a cat**: the owner sends a one-time invite link, or a six-character friend code that lasts two days. The other person picks a name the owner will see. It isn't their Apple Account name. It goes through the same word filter as a cat's name, can be up to 20 characters, and can't be changed later.
- **What travels**: only what happens in the game: visits, feeding, furniture, Beans spent, presents and paw prints. It's stored in the owner's own iCloud and shared with the other person through Apple's CloudKit sharing. HouseCat has no server and can't see any of it. The friend code is stored for two days in the app's public CloudKit database, holding nothing but the invite link.
- **Stop sharing** (the owner) takes the other person out. The cat, home, streak and Beans stay with the owner, and the other person's past visits still count.
- **Leave** (the other person): the shared cat stays with its owner. The person who leaves gets back their own cat, if they had one before joining. Otherwise they can adopt a new one. Beans they earned or bought while sharing, and presents they gave, stay with the shared cat.
- **Hide**: shows the other person as "Pip's other owner" on this device, and stops their paw prints and presents being announced.
- **Report**: opens the person's mail app with a message to safety@housecatgame.com. It's filled in with what the report is about, the name, the cat's name and a household reference like `HC-36RJ-FAPA`. The reference is made from the household and says nothing about who anyone is.
- **Delete all my data**: for someone who joined another person's cat, this also takes them out of the share. Their visits stay in the shared cat's history, under the name they chose, because the owner's streak counts them.

## Privacy policy: lines to add

Add this as a section (it replaces the "Sharing a cat or joining a group" section that was taken out for 1.0):

> **Sharing a cat**
> If you share your cat, or join someone else's, what happens in the game (visits, feeding, furniture, Beans spent, presents and paw prints) is kept in the cat owner's iCloud and shared with the other person through Apple's iCloud sharing. The other person sees the name you chose when you joined, never your Apple Account name or email. We can't see any of it: HouseCat has no server.
> A friend code is kept in HouseCat's public iCloud space for two days, holding only the invite it stands for. Then it stops working.
> You can stop sharing or leave at any time in the app. If you leave, or stop sharing, the visits already made stay part of the cat's history, under the name that was chosen. Delete all my data takes you out of any cat you joined, and deletes your own cat and its home from this device and your iCloud.

In the "How long we keep things" list, add:

> - Shared cats: in the owner's iCloud, until the owner deletes them. The person who joined leaves it when they leave, stop sharing ends, or they delete their data.
> - Friend codes: two days.
> - Reports you send us: as long as we need to deal with them, then deleted. Up to 12 months.

In "What we don't do", keep "Sell, rent or share data with anyone." It stays true: sharing happens between the two people, through Apple.

If the policy names its data processors, add: **Apple (iCloud/CloudKit)**: stores the shared cat in the owner's iCloud and the friend codes, for the sharing to work.

## Support page: questions to add

> **How do I share my cat with someone?**
> Open Settings (tap your cat's portrait, then Settings) and choose Make an invite link. Send the link, or read out the code under it; the code works for two days. They open it on their iPhone or iPad, pick a name for you to see, and from then on you both look after the same cat. Either of your visits keeps the streak.
>
> **What happens to my own cat if I join someone else's?**
> It waits on your device. If you leave, it comes back, though its streak won't have kept going while you were away.
>
> **How do I stop sharing, or leave?**
> In the Together card (in the menu under your badge), or in Settings. The owner chooses Stop sharing; the other person chooses Leave. Nothing is taken from the cat: its home, streak and Beans stay.
>
> **Someone I share a cat with is being unkind.**
> Tap Report in the Together card, or under a present. Your mail app opens with a message to safety@housecatgame.com, already filled in. You can also Hide their name, or stop sharing or leave straight away. We read every report.
>
> **Can I change the name I joined with?**
> Not while you share. To use a different name, leave and ask for a new invite.

## Terms of Use: lines to add

Add back a short section in place of "Sharing a cat with someone is not in this version":

> **Sharing a cat**
> When two people share a cat, its Beans, home and presents belong to the shared cat. If you leave, or the owner stops sharing, they stay with the cat and its owner, including Beans you bought while sharing. Be kind: names that break these terms can be reported, and we may ask Apple to look at an account that is used to harass someone.

The last sentence is optional. HouseCat can't remove anyone itself; the people sharing the cat can.

## App Store Connect for 1.1

- **Age rating, "User-generated content"**: change it to **Yes**. A co-owner's chosen name, and the cat's name, are seen by the other person. Say that names go through a word filter, and that there are Report, Hide, Stop sharing and Leave. Check whether the answer moves the rating from 4+, and decide before submitting.
- **Messaging or chat**: still No. There is no free text other than names.
- **App Privacy**: check the answers again. CloudKit data in the person's own iCloud, which the developer can't read, is usually not "collected". The friend code record in the public database holds only an invite link. Decide whether that needs declaring.
- **Capabilities**: iCloud with CloudKit and Push Notifications on the App ID (see CLAUDE.md, "To switch sharing on").
- **Review notes**: add a paragraph. Sharing needs two devices with two Apple Accounts, so attach a short screen recording of both phones: invite, join, Stop sharing, Leave and Report. Say where the controls are: the Together card in the menu, and Settings → Share.
- **What's New in 1.1**: "Share your cat with someone you live with or love: you both see the same cat and home, and either of your visits keeps the streak."

## Before submitting 1.1

- Check the safety@housecatgame.com mailbox works and someone reads it. App Review 1.2 expects timely responses to reports. The app promises nothing more than "We read every report", so decide on a reply time and add it to the support page if you want to promise one.
