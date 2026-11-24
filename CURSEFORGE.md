# CurseForge project page (draft)

Copy these into the Author Console when creating the project. Not part of the addon zip.

## Name

Biggus

## Summary (one sentence)

Guild fun for WoW Forever: bank leaderboards with titles, a savings goal, dungeon runs, deaths and loot envy, and a Most Wanted list of enemy players, shared between guildmates.

## Categories

- Main: Guild
- Additional: PvP, Bags & Inventory (guild bank), Chat & Communication

## License

MIT License (anyone may use, change or redistribute it, keeping the copyright notice). Same as the LICENSE file in the repository.

## Description

Biggus keeps score in your guild, with a sense of humour. Everything it shows comes from what your own game sees, and it is shared only with guildmates who also run Biggus.

**Guild bank.** Every time you open the guild bank, Biggus reads the bank log and keeps it, so the history never runs out (the game only keeps the last 25 entries per tab). The leaderboard shows each member's gold and items in and out, and a title: *Patron Saint of the Vault*, *Chief Goblin Officer*, *Trash Panda*, *Sponsored by Repair Bills* and more.

**Savings goal.** The bank's gold as a progress bar towards the next bank tab, or towards a goal your officers set.

**Dungeons.** Runs with guild members are logged with who was there, deaths and favourite dungeons. Titles include *Lives in Dungeons*, *Ride or Die* and *Floor Inspector*.

**Loot envy.** Rare and epic drops in guild runs, with *Luckiest Biggus* and *Cursed by RNG*.

**Most Wanted and Avengers.** When an enemy-faction player kills a guildie outside battlegrounds, the killer goes on the guild's Most Wanted list, read from the victim's own death recap. Hovering an enemy player shows if they're on it, and guildies who get them back land on the Avengers list. The list stays inside the guild, only counts the last 30 days on tooltips, and can be switched off in the settings. Biggus never messages or posts about the players on it.

**Sharing.** Guildmates with Biggus share their data by hidden addon whispers and catch each other up when they meet. Nobody without Biggus sees anything. Data is only accepted from guild members and is checked and limited.

**Commands.** `/biggus` opens the window (Bank, Dungeons, Loot, Most Wanted and Avengers). `/biggus report` posts the highlights to guild chat, only when you ask. `/biggus settings` turns each feature on or off. `/biggus help` lists the rest.

**Rules.** Biggus keeps to Blizzard's add-on policy and WoW Forever's restrictions: no combat log, no automation, at most one addon message a second, and it waits whenever the game locks addon messages down. Details are in SECURITY.md in the source repository.

Biggus was written with the help of an AI coding assistant, and its code is original. Source: https://github.com/Roaringman/Biggus
