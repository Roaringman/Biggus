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

**Loot envy.** Blue and epic drops in runs with guild members, and each guildie's Need and Greed rolls won over other guildies. Titles: *Luckiest &lt;your guild&gt;*, *Dice Lord*, *Loot Goblin*, *Needs Everything*, *Cursed by RNG*.

**Most Wanted.** When a guildie with Biggus is killed by an enemy-faction player outside battlegrounds and arenas, their copy reads the death recap and records the killer, the zone and subzone. The Most Wanted tab ranks killers (*Public Enemy #1*, *Has a Vendetta*, *Serial Ganker*, *Picks On Lowbies*), with the Enemy's Favourite Snack and the Danger Zone. Hovering an enemy player shows on their tooltip if they're on the list, and targeting one prints a warning.

**Avengers.** Guildies who kill someone on the Most Wanted list: a killing blow by you or your group (the game's own kill event), or helping (a wanted player you targeted in the last 15 seconds dying while you fight). Titles: *Guild Avenger*, *Bounty Hunter* (got Public Enemy #1), *Settled the Score* (got the one who killed them), *Won't Let It Go*, *Wingman*. Wanted players' tooltips show how often guildies paid them back.

**Sharing.** The bank history, the bank's gold, the savings goal, runs, deaths, loot and kills are shared between the guild's Biggus users by hidden whispers (Forever refuses addon messages in the guild channel). When two copies meet, each sends the other everything it learned since they last met, so members who were offline catch up too. Nobody without Biggus sees any of it.

Also: a minimap button, Biggus lines on guild members' tooltips, and a settings window.

## Commands

| Command | What it does |
|---|---|
| `/biggus` | Open the window (Bank, Dungeons, Loot, Most Wanted and Avengers tabs) |
| `/biggus dungeons`, `/biggus loot`, `/biggus wanted`, `/biggus avengers` | Open a specific tab |
| `/biggus report` | Post the bank highlights to guild chat |
| `/biggus report dungeons` / `loot` / `wanted` / `avengers` | Post that tab's highlights |
| `/biggus deathcheck` | Show what the game's death recap gave for your last death (to check Most Wanted works) |
| `/biggus rollcheck` | Show what Biggus sees of loot rolls: the loot history, the last loot lines and the wins counted |
| `/biggus goal 5000 New tabard` | Save for your own goal (5000g) instead of the next bank tab |
| `/biggus goal` | Back to saving for the next bank tab |
| `/biggus settings` | Turn chat comments, sharing, the minimap button and tooltips on or off |
| `/biggus sync` | Check sharing: which guild members have Biggus, what's waiting to be sent, the last error |
| `/biggus sync now` | Say hello to every guild member online again (to find new Biggus users right away) |
| `/biggus block Name`, `/biggus unblock Name` | Ignore a player's Biggus messages, or stop ignoring them |
| `/biggus forget Name` | Drop everything a player reported (bank entries, runs, deaths, loot, gold, goal, kills, revenge) |
| `/biggus reset` | Forget the bank history |
| `/biggus help` | List the commands |

`/snitch` works too.

## Good to know

- Chat comments only show in your own chat window. Only the **Report** button and `/biggus report` post to guild chat.
- The bank is only read while someone with Biggus has it open; what they read reaches everyone else's copy.
- A goal set with `/biggus goal` is shared when the guild master or an officer sets it: the newest one wins.
- Shared data is checked, limited and traceable: only guild members are heard, every value is range-checked, and `/biggus block` and `/biggus forget` remove a player's data.
- Net bank value counts items at vendor price, since addons can't see auction prices.
- Everyone needs Biggus 0.4 or newer for sharing: 0.3 used the guild channel, which Forever refuses.

## License

[MIT License](LICENSE): use, change or share Biggus however you like, as long as the copyright notice comes along.
