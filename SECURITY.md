# Biggus safety notes

Biggus shares data between guild members' copies by hidden addon whispers. Anything that arrives that way could have been typed by a person: WoW lets any player send any addon message. This page lists what Biggus does about faked data and leaked information, and what it can't prevent.

## Faked data

| Risk | What Biggus does |
|---|---|
| Someone outside the guild sends data | Messages are only read from players on the current guild roster. Everything else is dropped (counted as "refused" in `/biggus sync`). |
| A member floods you with messages | At most 200 messages a minute are read from one player; Biggus warns you once and drops the rest. History is capped (bank log 6000 entries, 3000 runs, 400 days). |
| Bad values: huge amounts, nonsense numbers | Every number is checked against a range: gold up to the game's cap, item counts, bank tabs 1–8, a run at most 5 people and 8 hours long, at most 25 deaths per person per run, at most 5 of one item per person per run. Anything out of range is dropped. |
| A time in the future, to always count as "newest" (bank gold, goal) | Times more than 10 minutes in the future, or more than 400 days old, are dropped. |
| Text that fakes item links or icons, or breaks guild chat | The game's `\|` escape codes and control characters are stripped from every received name, dungeon name, goal name and version, and their length is limited. Reports posted to guild chat only contain cleaned text. |
| Making up runs of other people | A player can only report a run they were in themselves, and only deaths and loot of the people in that run. Runs are passed on only by people who were in them, never second-hand. A run can't be padded past 5 people. |
| Changing the savings goal | Other copies only take a goal from the guild master and the first officer rank. A goal set by anyone else stays on their own copy. |
| Faking bank entries | Every received entry remembers who reported it. When you open the guild bank yourself, entries others reported that the real log contradicts are dropped, you're told who reported them, and those entries are never accepted again. Only the stretch of time the game's log still shows can be checked. |
| Removing a faker's data | `/biggus block Name` ignores a player from then on. `/biggus forget Name` drops every bank entry, run, death, loot drop, bank gold and goal they reported. |

## Information leaks

| Risk | What Biggus does |
|---|---|
| Strangers reading guild data | Data only goes by whisper to guild members known to run Biggus. Nothing goes to public channels. |
| Low ranks seeing bank tabs they can't open | Item-tab history only goes to members of your rank or higher. The gold log, which everyone who can open the bank sees, goes to all. |
| Posting to guild chat by accident | Only the **Report** button and `/biggus report` post to guild chat. Every other Biggus message only shows in your own chat window. |
| Not wanting to share | Settings > "Share bank, runs, deaths and loot…" off: your copy sends nothing (it still says hello, so others know you have Biggus). |

## What Biggus can't prevent

- **A member lying about their own runs.** Someone who really was in a run can still invent deaths or loot for that run, within the limits above, or invent a run with up to 4 other names. Their claims are marked with their name, so `/biggus forget` removes them. There's no way to prove a run happened without game data from a second player.
- **Bank entries older than the game's log.** The game keeps only the last ~25 entries per tab, so older reported entries can't be checked against the real log.
- **A member at your rank or higher passing on item-tab history.** Biggus can't see bank tab permissions, so it goes by rank order.
- **Being recorded by others.** Turning sharing off stops your copy sending, but guildmates' copies still record runs you're in, and bank deposits you make, because they see those in the game.
- **Edited saved data.** Anyone can edit their own `SavedVariables\Biggus.lua`. What they then send is subject to all the checks above.
- **Signatures.** WoW addons have no safe way to sign messages, so a message proves only which character sent it (the game guarantees the sender's name), not that its content is true.
