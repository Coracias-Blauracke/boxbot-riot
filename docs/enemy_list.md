# Enemy list

Prose before `.tres`, as CLAUDE.md requires, and for the same reason it worked
twice already: the repeats in a written list are the classes worth writing, and
what CANNOT be written down is the engine's real gap list.

**Setting**: the players are box robots, the enemies are Factorio-style bugs.
Bleed, poison and burn land on the bugs, which is why the statuses are what they
are.

---

## Why this list exists

The player's half of the game is deep and the horde's half is two files:

| player side | horde side |
|---|---|
| 8 characters, 48 weapons, 24 items, 5 classes, 4 statuses, a shop | 2 enemies, 1 arena, 1 wave table |

Every balance judgement about the deep half is currently made against one
behaviour. `ChaseBehavior` is the only movement in the game and contact damage
is the only attack, so **every weapon in the game solves the same problem**:
something is walking straight at you. Piercing wants a queue, bouncing wants a
cluster, range wants something that outranges you, and armour wants something
that hits hard and rarely. None of those situations exists yet.

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

| # | enemy | movement | attack | spawn | group |
|---|---|---|---|---|---|
| 4 | **Spitter** | orbit at ~220 | RANGED weapon | edge | 2 |
| 5 | **Charger** | charge: pause, telegraph, dash | contact on the dash | ring | 2 |
| 6 | **Popper** | chase | contact, and explodes on death | near-player | 4 |
| 7 | **Lurker** | chase, fast | contact, high burst | near-player | 3 |

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

| # | enemy | movement | attack | spawn | group |
|---|---|---|---|---|---|
| 8 | **Splitter** | chase | contact, splits in two on death | ring | 2 |
| 9 | **Warden** | chase, slow | contact, armoured | edge | 1 |
| 10 | **Hive** | drift, ignores players | spawns swarmlings on a timer | in view | 1 |

- **Splitter** turns one kill into two problems, which is the first enemy where
  killing the wrong thing first is a mistake.
- **Warden** is the enemy `ARMOR` on the player's side has an answer to and the
  enemy that answers `PIERCING`: a wall that a fast weak weapon cannot chew.
- **Hive** does not chase at all. It is a spawner that has to be prioritised,
  and it is the first enemy that makes a player leave a safe corner.

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

3. **Nothing can spawn anything on death or on a timer.** Splitter and Hive both
   need "put two of these here", which `core/` cannot do because it has no
   nodes. The shape that fits what already exists: an effect fills a REQUEST on
   the run, and the scene layer drains it the same frame - the mirror of
   `EntityModel.world_position`, which the view writes and core reads.

4. **No area damage.** Popper explodes, Colossus lands, and neither is
   expressible. Already on the known-gaps list as "no explosion/puddle effects
   on `ON_IMPACT`"; this is the content that pays for it.

5. **Only one `MovementBehavior`.** Orbit, charge and drift are one resource
   each, around twenty lines, with no new machinery - the axis was built for
   exactly this. Charge additionally needs a place to keep its own phase, which
   is the first behaviour with STATE. It cannot live on the resource, for the
   same reason effect state cannot: a `.tres` is shared by every holder of it.

6. **No telegraph.** A charger that dashes with no wind-up is a cheap shot, and
   there is no way to show one - no animation, no flash, no sound. The wind-up
   itself belongs to the behaviour and can exist before the art does, but until
   something DRAWS it the enemy is unfair rather than hard.

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

**1. Does a Popper hurt other bugs when it explodes?** Friendly fire between
enemies is a real design lever - it makes crowding them together valuable - but
it also makes a horde partly kill itself, which is very hard to balance blind.

**2. Is Warden's toughness ARMOR or just health?** Armour makes fast weak
weapons bad against it specifically, which is the interesting version; raw
health just takes longer. Armour on an enemy uses the same formula the player
has, so it costs nothing to try.

**3. How many enemy types should a single wave mix?** `WaveTable` can express
anything; nobody has decided whether wave 10 is one type or four. This is a
pacing question that only play answers.
