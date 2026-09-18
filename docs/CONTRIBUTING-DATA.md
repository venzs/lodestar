# Helping map WoW: Forever

Forever added roughly 640 quests that no existing database knows about, and the game does not tell
addons where anything is. Lodestar learns positions from people playing: every quest giver you talk to,
every objective you finish, every flight point you unlock is recorded on your own machine. Send that
file back and the next release knows it too — for everyone.

Nothing is uploaded, nothing runs in the background, and nothing leaves your computer unless you send
it. There is no account name, no password, no chat and no personal data in the file; it holds NPC ids,
quest ids, map coordinates and your character's name, realm, race, class and level (so contributions
can be credited and weighted).

## What to do

1. Install the addons and play normally. Talking to quest givers, turning quests in, opening a flight
   map and killing things all record something.
2. Before you log out, type `/reload`. WoW only writes the file on reload or logout, so a crash or an
   alt-F4 loses the session.
3. Run `tools\collect-harvest.cmd` (double-click it). It copies the file to your Desktop as
   `Lodestar-harvest-<yourname>-<date>.lua`. Send that.

No script? The file is here:

```
World of Warcraft\_classic_beta_\WTF\Account\<YOUR ACCOUNT>\SavedVariables\Lodestar_Guide.lua
```

`<YOUR ACCOUNT>` is a folder with a name like `123456#1` — there is usually only one. In game,
`/lode share` prints the path and a summary of what your file currently holds.

## What makes a contribution valuable

- **Talk to every quest giver you walk past**, even for quests you will not take. Opening the dialogue
  is what pins the NPC's exact position.
- **Play content nobody has mapped.** Anything in the 90000–99999 quest id range is new to Forever: the
  new starting zone, the Undead paladin chain, the Camping 101 profession quests, the level-22 Ruins of
  Lordaeron chain. A zone that already has a Lodestar route needs far less.
- **Open the flight map** at each flight master — it records the whole reachable network at once.
- **Run the census** once per character if you have a spare few minutes: `/lode scan quests 90000 100000`
  then `/lode scan retry`. It runs in the background while you play.
- Your **class and race matter**: a quest only visible to Tauren druids is only ever recorded by one.

## Useful commands

| Command | What it does |
|---|---|
| `/lode share` | Where your file is and what is in it |
| `/lode harvest` | Counts of what you have recorded |
| `/lode scan quests <from> <to>` | Walk a range of quest ids and record the ones that exist |
| `/lode scan retry` | Re-ask for ids the server did not answer |
| `/lode errors` | Anything Lodestar broke — worth sending with the file |
| `/lode harvest restore` | Undo an accidental wipe |

`/lode harvest wipe` deletes your recorded world data. It keeps one backup, but there is no reason to
run it; if something looks wrong, send the file instead.
