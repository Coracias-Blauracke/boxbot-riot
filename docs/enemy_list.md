# Enemy list

Prose before `.tres`, as CLAUDE.md requires, and for the same reason it worked
twice already: the repeats in a written list are the classes worth writing, and
what CANNOT be written down is the engine's real gap list.

**Setting**: the players are box robots, the enemies are Factorio-style bugs.
Bleed, poison and burn land on the bugs, which is why the statuses are what they
are.

---

## Why this list exists

WRITTEN WHEN THE TWO HALVES LOOKED LIKE THIS, and kept because the argument is
what the list was for - not because the numbers are still true:

| player side, then | horde side, then |
|---|---|
| 8 characters, 48 weapons, 24 items, 5 classes, 4 statuses, a shop | 2 enemies, 1 arena, 1 wave table |

The argument was that every balance judgement about the deep half was being made
against ONE behaviour. `ChaseBehavior` was the only movement and contact damage
the only attack, so **every weapon in the game solved the same problem**:
something walking straight at you. Piercing wants a queue, bouncing wants a
cluster, range wants something that outranges you, and armour wants something
that hits hard and rarely - and none of those situations existed.

**MOST OF THAT IS PAID OFF NOW**, which is the point of writing it down rather
than deleting it:

| player side, today | horde side, today |
|---|---|
| 8 characters, 52 weapons, 26 items, 5 classes, 4 statuses, a shop, drops | 8 ordinary enemies + 1 boss, 3 movements, contact / ranged / area damage |

Swarmlings are the cluster, the spitter is the thing that outranges you, the
brute and the charger both hit hard and rarely, and the charger is the first
that has to be dodged rather than out-walked. What is left is Lurker, Warden and
Colossus - and the reason to finish them is no longer "the horde is one file",
it is that a roster is only worth balancing once it is complete.

---

## The axes

An enemy decomposes the way a weapon does, which is what keeps this content
rather than code:

| axis | what it decides | today |
|---|---|---|
| `MovementBehavior` | how it approaches | `ChaseBehavior`, and nothing else |
| attack | how it hurts you | contact only |
| `SpawnPattern` | where it arrives | ring, in-view, near-player, edge |
| stats | how much of it there is | the whole stat set, per `EntityData` |
| effects | what is special about it | any `DynamicEffect`, same as an item |

Two enemies differing only in `movement` are two enemies. That is the point of
the split, and it is why most of the list below costs a `.tres`.

---

## The roster

Damage and health are rough and get tuned against play. `group` is the
`WaveEntry.group_size` it usually arrives in.

### Early (waves 1-6)

| # | enemy | movement | attack | spawn | group |
|---|---|---|---|---|---|
| 1 | **Chaser** | chase | contact | ring | 3 |
| 2 | **Swarmling** | chase, fast | contact, weak | ring | 8 |
| 3 | **Brute** | chase, slow | contact, heavy | edge | 1 |

- **Chaser** and **Brute** exist. Swarmling is the first new one and needs
  nothing: it is a chaser with small numbers and a big group.
- **Swarmling** is what makes a shotgun feel different from a rail spike. Eight
  weak things in a cluster is the situation `SpreadCone` and `BOUNCING` were
  authored for and have never met.

### Middle (waves 5-14)

| # | enemy | movement | attack | spawn | group | |
|---|---|---|---|---|---|---|
| 4 | **Spitter** | orbit at ~220 | RANGED weapon | edge | 2 | **AUTHORED** |
| 5 | **Charger** | charge: pause, telegraph, dash | contact on the dash | ring | 2 | **AUTHORED** |
| 6 | **Popper** | chase | contact, and explodes on death | near-player | 4 | **AUTHORED** |
| 7 | **Lurker** | chase, fast | contact, high burst | near-player | 3 | |

- **Spitter** is the whole reason the engine has to change at all. It is the
  first enemy that attacks from outside contact range, which is what makes
  MOVEMENT_SPEED and RANGE mean something on the player's side.
- **Charger** is the first enemy that can be DODGED rather than out-walked, and
  the first that needs a telegraph. Without a wind-up it is a cheap shot.
- **Popper** punishes killing things at your feet, which is exactly the habit a
  melee build forms.
- **Lurker** is what `SpawnNearPlayer` was written for, and the clearance rule
  in `SpawnPattern._push_clear_of_players` is what keeps it fair.

### Late (waves 12+)

| # | enemy | movement | attack | spawn | group | |
|---|---|---|---|---|---|---|
| 8 | **Splitter** | chase | contact, splits in two on death | ring | 2 | **AUTHORED** |
| 9 | **Warden** | chase, slow | contact, armoured | edge | 1 | |
| 10 | **Hive** | stands still, ignores players | spawns swarmlings on a timer | in view | 1 | **AUTHORED** |

- **Splitter** turns one kill into two problems, which is the first enemy where
  killing the wrong thing first is a mistake.
- **Warden** is the enemy `ARMOR` on the player's side has an answer to and the
  enemy that answers `PIERCING`: a wall that a fast weak weapon cannot chew.
- **Hive** does not chase at all. It is a spawner that has to be prioritised,
  and it is the first enemy that makes a player leave a safe corner.

  Authored with NO movement resource rather than with a drift behaviour and a
  speed of zero. "It does not move" is then one statement instead of two that
  could disagree, and a wandering drift needs per-holder STATE - which is gap 5's
  problem and belongs with the Charger, not here.

### Bosses

| # | boss | movement | attack | why |
|---|---|---|---|---|
| 11 | **Queen** | orbit at ~300 | ranged spit AND spawns swarmlings | the horde fight |
| 12 | **Colossus** | charge, slow, long telegraph | contact, enormous | the duel |

Two, deliberately, and deliberately opposite. A boss that is just a bigger brute
teaches nothing; these two ask different questions of a build - one wants
clearing power, the other wants burst and a dodge.

---

## What this list exposes as missing in the engine

Six of the twelve need no code. The other six need these, worst first - and a
seventh gap turned up later, from asking what a real boss fight is made of:

1. **A weapon always shoots the `enemies` group.** `&"enemies"` is hardcoded in
   three places - `weapon.gd`'s targeting, `weapon.gd`'s melee sweep and
   `projectile.gd`'s collision - so an enemy holding a weapon would shoot the
   other bugs. Who a weapon is hostile TO has to become a property of the
   wielder. This blocks Spitter and half of Queen, and it is the single change
   that turns "enemies can have weapons" from a system into a field: the model
   layer already shares `EntityModel` and `WeaponModel` between both sides.

2. **`spawn_boss` is decided and then ignored.** An effect rolls it,
   `RunModel` stores it, `wave_started` carries it, `main.gd` PRINTS it - and no
   spawner reads it. A boss wave is announced and then plays out identically to
   any other. `WaveTable` needs a boss entry and `WaveDirector` needs to emit it.

3. ~~**Nothing can spawn anything on death or on a timer.**~~ **DONE**, and
   built in the shape this entry predicted, with one correction: the request is
   emitted as a SIGNAL on the entity rather than queued on the run, because an
   effect firing on a dying enemy has no reference to the run and must not be
   given one. `EffectSpawn` says when, `SpawnRequest` says what and how many,
   and `main.gd` is the only thing that turns either into a node.

   Splitter and Hive are authored. The channel carries `EntityData` rather than
   enemies, so `SUMMON` delivery, turrets and dropped pickups ride it unchanged.

4. ~~**No area damage.**~~ **DONE.** `BlastData` says how far, how hard and
   whose side; `EffectBlast` says on what occasion. Popper is authored and bursts
   when it dies. Colossus still needs its charge, but its landing is now one more
   `.tres` rather than a system.

   The half of the old known-gap entry that remains is the PUDDLE: something that
   keeps hurting whatever stands in it is a duration with its own state, not a
   bigger explosion.

5. ~~**Only one `MovementBehavior`.**~~ **MOSTLY DONE.** Orbit and charge are
   authored. The phase problem this entry predicted is solved by `MovementState`,
   owned by the enemy and handed to the behaviour per call - the same split
   `EffectInstance` exists for, and now available to every behaviour that needs
   to remember anything.

   Drift is the one left, and it is only wanted for a wandering Hive; the Hive
   that exists carries NO movement resource at all, which says "it does not move"
   once instead of twice.

6. ~~**No telegraph.**~~ **DONE**, and the entry was right that the wind-up
   belongs to the behaviour and can exist before the art. It turned out the
   wind-up alone is most of the signal: an enemy that was moving and suddenly is
   not is readable with no art whatsoever.

   `ActorTint` is the drawing half, and it is general - a driver sets `sustain`
   from any fact it has and the tint decides what that looks like, so the next
   enemy that wants to show something reuses it without either side learning
   about the other.

   One lesson worth keeping: the accent must contrast with the BODY, not the
   background. Red was invisible on an already-red enemy while every number said
   it was working.

7. **Nothing CHOOSES between an enemy's weapons.** `EnemyData.weapons` is an
   array and every entry fires on its own clock, always, at once. That covers "a
   boss with three attacks happening together" and cannot express "three attacks
   taken in turn" or "one picked at random", which is what a boss fight is made
   of.

   This is its own axis and belongs beside `movement` rather than inside
   `FiringPattern`: a pattern answers WHEN THIS WEAPON fires, and the question
   here is WHICH WEAPON MAY. Folding the second into the first would make every
   pattern in the game - the ones players use included - carry a concept only
   bosses need. An authored resource that gates the rack, in order or at random,
   with its own state kept off the `.tres`.

### What the boss questions turned out NOT to need

Written down because the answers were verified in the code rather than guessed,
and because the expensive mistake here is building machinery that already
exists:

- **Ten shots in a stream** is `FiringBurst(shots_per_burst = 10)`. Once a burst
  starts it finishes, which is what makes it read as one attack.
- **Ten shots in an even ring** is `SpreadFan(count = 10)` with the weapon's
  `SPREAD_ANGLE` at 162. The fan spreads evenly from -angle to +angle, so a full
  ring of N is exactly `180 - 180/N` degrees - 120 for three, 162 for ten - and
  the gap that closes the circle at the back comes out the same size as the
  rest.
- **Several attacks at once** is already what an array of weapons does.
- **Changing MOVEMENT with health** needs one new `MovementBehavior` and nothing
  else: `get_direction` is handed the enemy's own `EntityModel` as its host, so
  a phase behaviour can read `current_hp` against `get_max_hp()` and delegate to
  a sub-behaviour. **Changing WEAPONS with health** needs one effect on
  `TAKE_DAMAGE`, because the rack is a view of `EntityModel.weapons` and
  re-syncs live the moment that list changes.

  Both carry the trap gap 5 already names: the phase is STATE and a `.tres` is
  shared by every enemy holding it, so it cannot live on the resource - the same
  rule that keeps effect state in `EffectInstance`.

## Open questions

**1. Does a Popper hurt other bugs when it explodes?** ANSWERED, by making it
stop being a question: `BlastData.reach` is HOSTILE, ALLIED or EVERYTHING, so
friendly fire is one field in a `.tres` rather than a decision in code. Popper
ships on HOSTILE and hurts players only.

The reasoning stands unchanged - friendly fire is a real design lever, because it
makes crowding the horde together valuable, and it is also very hard to balance
blind. Turning it on is now cheap enough to try the moment somebody wants to
measure it, which is the right shape for a question nobody can answer yet.

**2. Is Warden's toughness ARMOR or just health?** Armour makes fast weak
weapons bad against it specifically, which is the interesting version; raw
health just takes longer. Armour on an enemy uses the same formula the player
has, so it costs nothing to try.

**3. How many enemy types should a single wave mix?** `WaveTable` can express
anything; nobody has decided whether wave 10 is one type or four. This is a
pacing question that only play answers.
