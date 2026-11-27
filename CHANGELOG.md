# Biggus changelog

## 1.0.1
- The settings window wraps long setting names and grows to fit them, instead of letting the text run past its edge.
- Fixed: roll wins over guildies were not counted. Newer clients only print the winner in chat, so Biggus now reads who rolled Need and Greed from the game's loot roll history.
- New `/biggus rollcheck` shows what Biggus can see of loot rolls, to find out why one was not counted.

## 1.0.0
- First public release on CurseForge.
- Guild chat reports and the *Luckiest* loot title use your own guild's name, so Biggus fits any guild.

## 0.7.0
- **Roll wins**: the Loot tab counts each guildie's Need and Greed rolls won over other guildies (only rolls where at least one other guildie also rolled). New titles *Dice Lord* and *Needs Everything*, and a Dice Lord line in the loot report.
- **Blues**: blue drops get their own chat line too, and the Loot tab calls them Blues.
- Loot and roll lines are read correctly when the game shows player names in colour or as links.

## 0.6.1
- Biggus now keeps to Blizzard's add-on rules and WoW Forever's restrictions, checked in the game:
  - Sharing sends at most one message a second and waits whenever the game locks addon messages down (in instances and fights).
  - Guild chat reports have a 30-second cooldown.
  - The savings goal's name, the only text you type that Biggus sends, goes as a logged message so it can be reported like chat.
- Most Wanted only counts the last 30 days on tooltips and warnings, and a new setting turns Most Wanted and Avengers off.
- Fixed: sharing could stop sending entirely on Forever's live realms.

## 0.6.0
- New **Avengers** tab: guildies who killed or helped kill someone on the Most Wanted list, with titles like *Guild Avenger* and *Bounty Hunter*.
- Wanted players' tooltips show how often guildies paid them back.

## 0.5.0
- New **Most Wanted** tab: enemy players who killed a guild member, read from your death recap, with the zone of the kill.
- Hovering an enemy player shows whether they're on the list; targeting one prints a warning.
- `/biggus deathcheck` shows what your last death recap contained.

## 0.4.2
- Runs are shared second-hand, so they keep spreading after the people in them log off.

## 0.4.1
- Safety: data is only taken from guild members, every value is checked, shared bank entries are checked against the real bank log, and `/biggus block` and `/biggus forget` remove a player's data.

## 0.4.0
- Sharing now uses hidden whispers (WoW Forever refuses addon messages in the guild channel), and copies catch each other up on what they missed.
- The bank history, the bank's gold and the savings goal are shared too.
- Two-part names ("Muliens Bubbleskull") are handled properly.
- `/biggus sync` shows whether sharing works.

## 0.3.0
- First release: guild bank leaderboard with titles, the savings goal, dungeon runs with guild members, a death counter, loot envy, a minimap button, tooltips and settings.
