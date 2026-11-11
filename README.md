# Hulk vs Abomination: Lockdown

A scary hide-and-seek game for Roblox. A random player becomes the **Abomination** and hunts
everyone through a pitch-black research facility. Another random player is the **Hulk**, who
has to keep it away. Everyone else is a **civilian** with a weak flashlight and nowhere to go
but a locker. The more the giants fight, the more the building comes apart, and the fewer
places there are to hide.

## Play it

1. Download **`MonsterLockdown.rbxlx`** and open it in Roblox Studio (File → Open from File).
2. Press **Play**. You'll spawn in the lit lobby. After 20 seconds the lockdown starts.
3. With one player you're a civilian and AI bots play both giants. To try the other roles,
   use **Test → Clients and Servers** with 2–3 players.
4. To save coins and costumes: publish, then turn on
   *Game Settings → Security → Enable Studio Access to API Services*.

The map is built by scripts, so the editor shows an empty world until you press Play.

## How a round works

| Phase | Time | What happens |
|---|---|---|
| Lobby | 20 s | Buy and equip costumes at the shop booth. |
| Role draw | instant | Random roles: Abomination (2+ players), Hulk (3+ players), everyone else civilian. AI bots fill in missing giants. |
| Hide | 25 s | Civilians scatter and hide. The Abomination is locked in a glass containment cell. |
| Hunt | 4 min | The glass shatters. The Abomination wins if it catches every civilian. If anyone is still free when time runs out, the Hulk and the survivors win. |

**Civilians**: hide in lockers, wardrobes, under desks, in bathroom stalls, crates, walk-in
fridges, server racks or air vents (E). You peek out through the slats while hidden.
Sprinting (Shift or Ctrl) makes noise the Abomination can hear, and your flashlight (F) helps you see but
helps it see you too. If your hiding spot gets smashed, you're thrown out stunned, so run.

**Giants** stand about twice as tall as a civilian (`Config.GiantScale`), too big for doors, and
move fast. They don't need doors: running into a wall, door, locker or desk plows straight
through it (`Config.Rampage`).

**Abomination**: Click/F smash (breaks walls and grabs anyone in reach), Q roar (reveals every
civilian nearby, even hidden ones, as heartbeats), R leap, and hold E on a hiding spot to search it.
Footstep ripples show you where people are sprinting. If the Hulk knocks you out, you're down for
18 seconds, then you get back up.

**Hulk**: Click/F smash (launches the Abomination through walls), Q thunderclap (stuns it),
R leap. Every fight shakes the building, and hiding spots near the brawl crack and eventually
break, so fight it *away* from the civilians. The Hulk can die. If that happens, nobody is
coming.

## Chaos and destruction

Every interior wall is made of breakable panels. Doorways fit people, not giants, so the giants
smash their way into rooms. A launched giant crashes through every wall in its path. Each broken
panel and each giant-on-giant hit fills the **chaos meter**:

| Chaos | Event |
|---|---|
| 20 | Blackout: exit signs die and the emergency lights flicker wildly |
| 45 | The ceiling collapses in several places, crushing hiding spots |
| 70 | The Abomination is enraged: faster, and its roar recharges twice as fast |
| 100 | Structure failing: random collapses every few seconds, often right on top of hiding spots |

Atmosphere: no lights except dim green exit signs and flickering red emergency lights,
lightning through the windows, a heartbeat vignette and screen shake as the Abomination gets
close, whispers, and role-specific vision (the Abomination sees in yellow "predator vision").

## Coins and costumes

| Result | Coins |
|---|---|
| Abomination wins | 120, plus 15 per catch |
| Hulk wins | 100, plus 40 per knockout |
| Surviving civilian (Hulk side wins) | 60 |
| Caught | 10 |
| Everyone | +5 for playing |

Costumes: Hulk (Classic, Gray Brute, Red Rage, Gladiator), Abomination (Classic, Crimson, Bone
White, Toxic glow), Civilian (Office Worker, Scientist, Security Guard, Janitor, Black Hoodie).

## Sounds

The `sounds/` folder has eight original sound effects, synthesized from scratch by
`tools/make_sounds.py` (no samples, no movie audio), so you own them outright:

| File | Where it plays |
| --- | --- |
| `roar.ogg` | Giant roars, heard across the building |
| `smash.ogg` | Walls, panels and hiding spots breaking; punches; collapses |
| `stomp.ogg` | Giant footsteps (you hear them coming before you see them) and leap landings |
| `thunder.ogg` | After each lightning flash, and the Hulk's thunderclap |
| `heartbeat.ogg` | Loops louder and faster as the Abomination gets close |
| `ambience.ogg` | Looping drone, vents and groaning metal |
| `alarm.ogg` | Structure failing |
| `scream.ogg` | Jump-scare stinger when you're caught or your hiding spot is exposed |

Roblox only plays audio that's uploaded to your account:

1. Download the `.ogg` files from the `sounds/` folder on GitHub.
2. In the Creator Dashboard go to **Creations → Development Items → Audio** and upload each one.
3. Copy each asset id and paste it into `Config.Sounds` in `src/shared/Config.lua`
   (or the `Config` ModuleScript in Studio) as `"rbxassetid://1234567"`.

Empty slots are skipped, so the game runs fine before you upload them. To tweak a sound,
edit `tools/make_sounds.py` and run `python3 tools/make_sounds.py` (needs numpy and ffmpeg).

## A note on names

Hulk and Abomination are Marvel characters. A public game using their names or looks can be
removed by Roblox moderation or a copyright claim. Every name shown in the game comes from
`Config.Names` in `src/shared/Config.lua`, so renaming them (e.g. "The Brute" vs "The Horror")
is a one-line change.

## Project layout

```
src/shared/Config.lua            All names, timings, abilities, chaos events, rewards, costumes
src/server/Main.server.lua       Round loop, roles, catching, noise, flashlights, payouts
src/server/Services/
  Facility.lua                   Builds the dark facility (breakable walls, rooms, hiding spots) + lobby
  Destruction.lua                Blasts, flying debris, cracked/shattered hiding spots, chaos events
  Hiding.lua                     Hide / leave / search / expose
  Giants.lua                     Giant transformation, HP, knockouts, smash/roar/clap/leap, launches
  Bots.lua                       AI giants that smash through walls to reach their targets
  Data.lua                       Coins and costumes (DataStore)
  Net.lua                        Remotes
src/client/HUD.client.lua        Status, role reveal, HP bars, meters, results, shop, spectating
src/client/Controls.client.lua   Abilities, sprint, flashlight, mobile buttons, role-based prompts
src/client/Effects.client.lua    Vision, heartbeat, shake, lightning, flicker, hiding camera, senses
tools/build_place.py             Rebuilds MonsterLockdown.rbxlx from src/ (no Rojo needed)
```
