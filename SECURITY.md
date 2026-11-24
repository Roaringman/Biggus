# Biggus safety notes

Biggus shares data between guild members' copies by hidden addon whispers. Anything that arrives that way could have been typed by a person: WoW lets any player send any addon message. This page lists how Biggus keeps to Blizzard's add-on rules, what it does about faked data and leaked information, and what it can't prevent.

## Blizzard's add-on rules

Blizzard's [UI Add-On Development Policy](https://us.forums.blizzard.com/en/wow/t/ui-add-on-development-policy/24534) has eight rules, and WoW Forever adds the Midnight-era API restrictions.

| Rule | How Biggus keeps it |
|---|---|
| 1. Free of charge | Free, with no paid features or services. |
| 2. Code completely visible | Plain, readable Lua; nothing is hidden or obfuscated. |
| 3. No harm to realms or other players: the realms | The game allows each message prefix a burst of 10 and then one message a second, and warns that sending a lot on several prefixes at once can disconnect you ([SendAddonMessage](https://warcraft.wiki.gg/wiki/API_C_ChatInfo.SendAddonMessage)). Biggus sends on one prefix, at most one message a second. It doesn't send while `C_ChatInfo.InChatMessagingLockdown()` says addon messages are locked down, and when the game answers "throttled" or "locked down" it waits and sends the same message later instead of retrying; "target offline" drops that player's messages until the next catch-up. Trial accounts, which Blizzard doesn't let send addon messages on Forever, don't send. A first catch-up with someone covers only the last 30 days; hellos to members without Biggus go at most once a day each. Guild chat is only posted to when you press Report, at most every 30 seconds and at most 6 lines. Stats are cached and timers run once a second at most. |
| 3. No harm to realms or other players: other players | Most Wanted and Avengers only hold what the victim's own game showed (an enemy player's name, race, class, level, and the zone of the kill), keep it inside the guild, and never message or post about the players on the list outside guild chat. Tooltips and target warnings only count the last 30 days, so the list ages out instead of becoming a permanent grudge. Settings > "Track Most Wanted and Avengers" turns the whole thing off (nothing recorded, shared, shown or announced). Kill-on-sight lists are a long-standing, ordinary kind of add-on, openly published for Forever and Midnight on CurseForge - [Forever Simple Spy](https://www.curseforge.com/wow/addons/forever-simple-spy), [Spy Forever](https://www.curseforge.com/wow/addons/spy-forever), [KillOnSight](https://www.curseforge.com/wow/addons/kill-on-sight) (Midnight 12.0.1) and [Spy Guild KoS Sync](https://www.curseforge.com/wow/addons/spy-guild-kos-sync), which shares a list across a guild like Biggus does. Those go further than Biggus (alarms when a listed enemy is near); Biggus only notes who killed a guildie, on hover or target. |
| User-written text | The savings goal's name is the only text a player types that Biggus sends. It goes with `C_ChatInfo.SendAddonMessageLogged` when the client has it, as Blizzard asks for user-generated content, so it can be reported like chat. |
| 4. No advertisements | None. |
| 5. No donation requests in game | None (and none in the `.toc`). |
| 6. Nothing objectionable (ESRB Teen) | Titles and quips are light teasing (*Trash Panda*, *Floor Inspector*, *Cursed by RNG*). |
| 7. Terms of Use | No automation: Biggus never casts, targets, moves, buys, trades or invites. It only reads what the game shows and posts to guild chat when you ask. Most Wanted lists stay inside the guild (guild chat and hidden whispers to guild members), never public channels or whispers to the players on them. |
| 8. Blizzard may disable features | Accepted. |
| Forever: no combat log | Biggus never registers for `COMBAT_LOG_EVENT_*` (Forever closes it to add-ons; ForeverDungeonJournal notes that registering for it gets an add-on blocked). Kills come from the death recap, `PARTY_KILL`, `UNIT_DIED` and kill chat lines, the same sources Forever's own add-ons use. |
| Forever: secret values | Values the game hides from add-ons (in instances, in fights, and chat text during a chat lockdown, even in the open world) are checked with `issecretvalue` and skipped, never compared or stored. |

| Midnight/Forever: no combat decision-making | Blizzard's Midnight restrictions target in-combat advantage; as one write-up puts it, "displaying information is allowed. Telling the player what to do with it is not" (no automatic marking, no movement instructions, no tracking other players' debuffs). Biggus makes no combat decisions: it shows history (bank, runs, kills, revenge) and a note on who killed a guildie, never anything about a fight in progress. |

How this was checked: the policy text from Blizzard's forum post; the message limits and result codes from the [SendAddonMessage](https://warcraft.wiki.gg/wiki/API_C_ChatInfo.SendAddonMessage) and [InChatMessagingLockdown](https://warcraft.wiki.gg/wiki/API_C_ChatInfo.InChatMessagingLockdown) API pages; which APIs Forever's client has, from the add-ons that run on it (EllesmereUI, ForeverDungeonJournal, ForeverTrading); Forever applying Midnight's rules, from [Kami Labs](https://kami-labs.fr/en/wow-classic/wow-forever-addons-restreints-comme-sur-midnight/) and the [Warcraft Tavern interview](https://www.warcrafttavern.com/forever/news/ion-holly-interview-blizzcon-2026/) (Ion: "we're not removing add-ons from the game"; the changes target competitive advantage in combat). In the game (from the client's own files, 24 November 2026): Biggus 0.4.x ran (its windows, its saved-data upgrades, bank reading and hellos); 0.6.1 loaded and ran with no Lua errors (script errors on); and a hidden-whisper hello to a guild member running Biggus 0.5.0 was answered 10 seconds later, with the catch-up to them completed - so addon whispers between guild members get through on Forever, both ways. With the final sending rules (only `InChatMessagingLockdown` holds sending back), a session showed sent 2, received 9, failed 0, refused 0, with the game reporting "chat lockdown false · outgoing addon chat restricted true": that second flag is on all the time on Forever's live realms and whispers get through regardless, which is why Biggus doesn't wait on it. The death recap was checked with a real death: `C_DeathRecap.GetRecapEvents()` works without an ID, the killing event comes first, `sourceName`, `sourceGUID` and `sourceFlags` are readable and `hideCaster` is secret (handled), and a mob killer was correctly not recorded. Not yet checked in the game: sending while inside an instance (Biggus waits on the lockdown flag and on the game's "locked down" answers there).

Not a rule today, but worth knowing: NetEase banned player-*rating* add-ons (gear and log scores) on Chinese Classic realms in July 2026. Biggus doesn't rate players' performance; its titles are guild jokes.

## Faked data

| Risk | What Biggus does |
|---|---|
| Someone outside the guild sends data | Messages are only read from players on the current guild roster. Everything else is dropped (counted as "refused" in `/biggus sync`). |
| A member floods you with messages | At most 200 messages a minute are read from one player; Biggus warns you once and drops the rest. History is capped (bank log 6000 entries, 3000 runs, 400 days). |
| Bad values: huge amounts, nonsense numbers | Every number is checked against a range: gold up to the game's cap, item counts, bank tabs 1–8, a run at most 5 people and 8 hours long, at most 25 deaths per person per run, at most 5 of one item per person per run. Anything out of range is dropped. |
| A time in the future, to always count as "newest" (bank gold, goal) | Times more than 10 minutes in the future, or more than 400 days old, are dropped. |
| Text that fakes item links or icons, or breaks guild chat | The game's `\|` escape codes and control characters are stripped from every received name, dungeon name, goal name and version, and their length is limited. Reports posted to guild chat only contain cleaned text. |
| Making up runs of other people | Not blocked: the guild trusts each other, so runs are passed on second-hand and any guild member may report any run, so that runs keep spreading after the people in them log off. What still holds: deaths and loot only count for people in that run, within the limits above, and a run can't be padded past 5 people. |
| Blaming a kill on someone | Kills are read from the victim's own death recap and only recorded when the killer is confirmed as an enemy-faction player (by their race from the recap, or by having been seen nearby in the last 10 minutes). Shared kills are passed on second-hand like runs, so any guild member could make one up; each remembers who reported it, for `/biggus forget`. |
| Claiming revenge | A revenge kill only counts for a guild member and only against someone on the Most Wanted list. It's seen from the game's own kill event, your own "You have slain" line, or a targeted wanted player dying while you fight. Shared ones can be made up by any guild member, like runs; each remembers who reported it, for `/biggus forget`. |
| Changing the savings goal | Other copies only take a goal from the guild master and the first officer rank. A goal set by anyone else stays on their own copy. |
| Faking bank entries | Every received entry remembers who reported it. When you open the guild bank yourself, entries others reported that the real log contradicts are dropped, you're told who reported them, and those entries are never accepted again. Only the stretch of time the game's log still shows can be checked. |
| Removing a faker's data | `/biggus block Name` ignores a player from then on. `/biggus forget Name` drops every bank entry, run, death, loot drop, bank gold and goal your copy got from them first. |

## Information leaks

| Risk | What Biggus does |
|---|---|
| Strangers reading guild data | Data only goes by whisper to guild members known to run Biggus. Nothing goes to public channels. |
| Low ranks seeing bank tabs they can't open | Item-tab history only goes to members of your rank or higher. The gold log, which everyone who can open the bank sees, goes to all. |
| Posting to guild chat by accident | Only the **Report** button and `/biggus report` post to guild chat. Every other Biggus message only shows in your own chat window. |
| Not wanting to share | Settings > "Share bank, runs, deaths and loot…" off: your copy sends nothing (it still says hello, so others know you have Biggus). |

## What Biggus can't prevent

- **A member making up runs.** Any guild member can invent a run with up to 5 names, including people who weren't online, and deaths and loot for it within the limits above. There's no way to prove a run happened without game data from a second player.
- **Made-up runs spreading.** Because runs are passed on second-hand, a made-up run reaches copies through honest players too. Each copy remembers only who it first heard a claim from, so `/biggus forget Name` removes what came straight from that player, but not what reached you through someone else. If a faker is found, everyone should run `/biggus block` and `/biggus forget` for them; claims that reached a copy second-hand stay on it.
- **Bank entries older than the game's log.** The game keeps only the last ~25 entries per tab, so older reported entries can't be checked against the real log.
- **A member at your rank or higher passing on item-tab history.** Biggus can't see bank tab permissions, so it goes by rank order.
- **Being recorded by others.** Turning sharing off stops your copy sending, but guildmates' copies still record runs you're in, and bank deposits you make, because they see those in the game.
- **Edited saved data.** Anyone can edit their own `SavedVariables\Biggus.lua`. What they then send is subject to all the checks above.
- **Signatures.** WoW addons have no safe way to sign messages, so a message proves only which character sent it (the game guarantees the sender's name), not that its content is true.
