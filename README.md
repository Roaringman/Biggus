# Biggus

A World of Warcraft addon for the **Biggus** guild on WoW Forever. It keeps score of who feeds the guild bank and who raids it, tracks the savings goal, and counts dungeon runs, deaths and loot among guild members, with (un)flattering titles for everyone.

## Install

1. Click **Code > Download ZIP** on this page (or download a release).
2. Unzip it into `World of Warcraft\_forever_\Interface\AddOns\`.
3. Rename the folder to exactly **`Biggus`** (GitHub names it `Biggus-main`), so you end up with `AddOns\Biggus\Biggus.toc`.
4. Restart the game.

## What it does

**Guild bank.** Every time you open the guild bank, Biggus reads the bank's log and keeps it, so the history never runs out (the game only keeps the last ~25 entries per tab). The leaderboard shows each member's gold in and out, items in and out, net, and a title: *Patron Saint of the Vault*, *Chief Goblin Officer*, *Trash Panda*, *Sponsored by Repair Bills*, *Selfless Little Bean* and more.

**Savings goal.** The bank's gold as a percentage of the next bank tab's price, or of a goal you set yourself, shown as a progress bar.

**Dungeons.** Entering a 5-player dungeon with at least one other guild member logs a run. The Dungeons view shows runs, deaths, best buddy and favorite dungeon per member, with titles like *Lives in Dungeons*, *Ride or Die*, *Floor Inspector* and *Unkillable*.

**Loot envy.** Rare and epic drops in runs with guild members. Titles: *Luckiest Biggus*, *Loot Goblin*, *Cursed by RNG*.

**Sharing.** Runs, deaths and loot are passed to other Biggus users in the guild through hidden addon messages, so everyone's copy counts the whole guild (for members who are online at the time).

Also: a minimap button, Biggus lines on guild members' tooltips, and a settings window.

## Commands

| Command | What it does |
|---|---|
| `/biggus` | Open the window (Bank, Dungeons and Loot tabs) |
| `/biggus dungeons`, `/biggus loot` | Open a specific tab |
| `/biggus report` | Post the bank highlights to guild chat |
| `/biggus report dungeons`, `/biggus report loot` | Post the dungeon or loot highlights |
| `/biggus goal 5000 New tabard` | Save for your own goal (5000g) instead of the next bank tab |
| `/biggus goal` | Back to saving for the next bank tab |
| `/biggus settings` | Turn chat comments, sharing, the minimap button and tooltips on or off |
| `/biggus reset` | Forget the bank history |
| `/biggus help` | List the commands |

`/snitch` works too.

## Good to know

- Chat comments only show in your own chat window. Only the **Report** button and `/biggus report` post to guild chat.
- The bank is only read while someone with Biggus has it open, and each copy keeps its own bank history.
- A goal set with `/biggus goal` only applies to your own copy.
- Net bank value counts items at vendor price, since addons can't see auction prices.
- Forever's live realms sometimes refuse addon messages; anything that couldn't be shared is retried every minute.
