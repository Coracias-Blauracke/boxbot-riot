# Weapon list - first pass

Prose before `.tres`, as CLAUDE.md requires. Nothing here is authored yet; this
is the document to argue with, cut and reorder before anything is built.

**Setting**: the players are box-shaped robots. The enemies on the release map
are Factorio-style bugs, which is why bleed stays bleed rather than being
re-themed as an oil leak - the statuses land on the bugs.

**Classes**, five, all buildable with what the engine has today:

| tag | bonus it should grant | identity |
|---|---|---|
| `gun` | RANGED_DAMAGE, RANGE | reach and precision |
| `rapid` | ATTACK_SPEED | many small hits; crosses melee and ranged |
| `blade` | MELEE_DAMAGE, CRIT_CHANCE | cutting, close |
| `bouncy` | BOUNCING | ricochet, rewards positioning |
| `bloody` | BLEED_CHANCE, BLEED_DAMAGE | damage over time |

The four axes are `FiringPattern` x delivery x `SpreadPattern` x
`TargetSelector`. Available today: firing INSTANT / BURST / WINDUP / CHANNEL,
delivery PROJECTILE / MELEE_SWEEP, spread SINGLE / CONE(n) / FAN(n), targeting
NEAREST / BY_HEALTH(LOWEST|HIGHEST). Melee motion is ARC or THRUST.

**Scaling** is `damage_scaling` (which stats feed damage, at what share) and
`stat_inheritance` (how much of the holder's attack speed, crit, range reaches
this weapon). Empty scaling means "all of my own damage type", which is the
right default for most weapons; a fast weapon needs a reduced share or it turns
every flat damage item into more DPS than a slow one.

---

## gun - reach and precision

| # | name | tier | price | firing | delivery | spread | target | tags | scaling |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Bolt Driver | 1 | 25 | INSTANT 0.45 | projectile | single | nearest | gun | default |
| 2 | Scatter Vent | 2 | 45 | INSTANT 0.90 | projectile | cone 6 | nearest | gun | default |
| 3 | Rail Spike | 3 | 90 | WINDUP 1.6 | projectile | single | by_health HIGHEST | gun | 150% RANGED |
| 4 | Rivet Repeater | 1 | 30 | INSTANT 0.18 | projectile | single | nearest | gun, rapid | 50% RANGED |
| 5 | Flak Pod | 3 | 75 | BURST 3 | projectile | cone 3 | nearest | gun | default |
| 6 | Bleeder Rounds | 2 | 50 | INSTANT 0.50 | projectile | single | nearest | gun, bloody | default |

- **Bolt Driver** is the existing pistol, renamed. Starting weapon.
- **Scatter Vent** is the existing shotgun: falloff 110 -> 280 at x0.4, so it is
  a room-clearer and useless at range. Existing content, renamed.
- **Rail Spike** takes 1.6s to spin up and picks the TOUGHEST target. PIERCING
  +3, so it lines up a row of bugs. 150% scaling is the counterweight to Rivet
  Repeater: a slow weapon should reward flat damage items more, not less.
- **Rivet Repeater** fires five times a second. Its 50% scaling is the whole
  reason `damage_scaling` exists.
- **Flak Pod** fires three-round bursts into a narrow cone - the burst pattern
  has tests and no authored content today.

## rapid - many small hits

| # | name | tier | price | firing | delivery | spread | target | tags | scaling |
|---|---|---|---|---|---|---|---|---|---|
| 7 | Needle Array | 2 | 55 | INSTANT 0.10 | projectile | single | by_health LOWEST | gun, rapid | 35% RANGED |
| 8 | Buzz Cutter | 2 | 45 | INSTANT 0.25 | melee ARC 90 | - | nearest | blade, rapid | 50% MELEE |
| 9 | Servo Fists | 1 | 20 | INSTANT 0.30 | melee ARC 70 | - | nearest | rapid | 60% MELEE |

- **Needle Array** is the first authored weapon to use HEAT: `heat_per_shot`
  0.12, so it overheats after roughly three seconds of continuous fire and vents
  at 35%. The whole heat layer has tests and zero content exercising it, which
  makes it the least trustworthy part of the weapon code.
- **Buzz Cutter** is a short fast arc - the saw that replaces the sword.
- **Servo Fists** are punches: reach 40, cheapest weapon in the game, and the
  argument for `rapid` crossing melee and ranged.

## blade - cutting, close

| # | name | tier | price | firing | delivery | spread | target | tags | scaling |
|---|---|---|---|---|---|---|---|---|---|
| 10 | Circular Saw | 1 | 30 | INSTANT 0.60 | melee ARC 150 | - | nearest | blade | default |
| 11 | Hydraulic Shears | 2 | 55 | INSTANT 0.80 | melee THRUST | - | nearest | blade | default |
| 12 | Reaper Discs | 3 | 85 | INSTANT 0.70 | melee ARC 220 | - | nearest | blade, bloody | default |
| 13 | Guillotine Arm | 4 | 140 | WINDUP 2.0 | melee ARC 180 | - | by_health HIGHEST | blade | 150% MELEE |

- **Hydraulic Shears** carry +15% CRIT_CHANCE of their own and a long thrust:
  single-target, picks its moment.
- **Reaper Discs** sweep 220 degrees and apply bleed on hit (MELEE only, through
  the `damage_types` filter that `EffectApplyStatusOnHit` already has).
- **Guillotine Arm** is the heavy: two seconds of windup, huge reach, aimed at
  the toughest thing on screen.

## bouncy - ricochet

| # | name | tier | price | firing | delivery | spread | target | tags | scaling |
|---|---|---|---|---|---|---|---|---|---|
| 14 | Carom Pistol | 1 | 35 | INSTANT 0.50 | projectile | single | nearest | bouncy | default |
| 15 | Ricochet Rig | 2 | 60 | BURST 2 | projectile | single | nearest | bouncy | default |
| 16 | Pinball Launcher | 3 | 95 | INSTANT 1.10 | projectile | fan 4 | nearest | bouncy | default |
| 17 | Wall Shredder | 2 | 65 | INSTANT 0.35 | projectile | single | nearest | bouncy, rapid | 50% RANGED |

BOUNCING is carried by the weapon itself: +2, +3, +4 and +2 in order. These are
deliberately NOT tagged `gun`, or `gun` would be on two thirds of the list and
its set bonus would cost nothing to complete.

- **Pinball Launcher** throws four bouncing projectiles in a fan every 1.1s.
- **Wall Shredder** also carries PIERCING +1, so it goes through a bug and then
  keeps bouncing.

## bloody - damage over time

| # | name | tier | price | firing | delivery | spread | target | tags | scaling |
|---|---|---|---|---|---|---|---|---|---|
| 18 | Serrated Drill | 1 | 30 | INSTANT 0.40 | melee THRUST | - | nearest | blade, bloody | default |
| 19 | Hemo Lance | 2 | 60 | INSTANT 0.90 | melee THRUST | - | by_health HIGHEST | blade, bloody | default |
| 20 | Sanguine Sprayer | 3 | 100 | INSTANT 0.70 | projectile | cone 5 | nearest | bloody | default |

- All three apply bleed through `EffectApplyStatusOnHit`, with their own
  `base_chance` rather than relying on the holder's stats.
- **Sanguine Sprayer** also carries `EffectHealWhenHittingStatus`, so it heals
  the wielder for hitting something already bleeding. Both effect classes exist.

## odd scaling - the weapons built for a build

| # | name | tier | price | firing | delivery | spread | target | tags | scaling |
|---|---|---|---|---|---|---|---|---|---|
| 21 | Ballast Cannon | 3 | 80 | WINDUP 1.2 | projectile | single | nearest | gun | 12% MAX_HP only |
| 22 | Kinetic Spike | 2 | 55 | INSTANT 0.30 | melee THRUST | - | nearest | blade, rapid | 6% MOVEMENT_SPEED |
| 23 | Governor Rig | 4 | 130 | INSTANT 0.55 | projectile | single | nearest | gun | 50% RANGED, 8% MAX_HP, -4% MOVEMENT_SPEED |

- **Ballast Cannon** ignores ranged damage entirely and fires off your health
  pool. A tank build's weapon, and useless in a glass-cannon one.
- **Kinetic Spike** hits harder the faster you move.
- **Governor Rig** is the joke weapon we agreed there would be at most one of:
  it wants health, tolerates damage items and actively punishes movement speed.

---

## Class membership after this pass

| tag | members | thresholds are reachable? |
|---|---|---|
| gun | 8 | yes, comfortably |
| blade | 8 | yes |
| rapid | 6 | yes |
| bloody | 5 | yes at 2, a stretch at 4 |
| bouncy | 4 | exactly one full set - aspirational, which is fine |

## What this list exposed as missing in the engine

Writing the four axes per weapon is what this exercise is for. Everything above
is authorable today EXCEPT where noted, and **not one weapon here needs a new
effect class** - `EffectApplyStatusOnHit` and `EffectHealWhenHittingStatus`
cover the only two behaviours in the list.

What could not be written, and why:

1. **BEAM and SUMMON deliveries do not exist.** `weapon.gd` matches only
   PROJECTILE and MELEE_SWEEP; the other two enum values fall through silently.
   This blocks anything laser-shaped and the whole `structure` class of turrets
   and drones. The enum values existing makes this look supported, which is
   worse than not having them.
2. **No projectile-count stat.** The number of projectiles is authored inside
   `SpreadPattern`, so a `multishot` class bonus has nothing to raise. Adding
   one means a stat plus a read in `SpreadCone`/`SpreadFan`.
3. **No knockback stat.** A `crush` class has no obvious bonus to grant, which
   is a real reason it is not in the first five rather than a taste one.
4. **Only two swing motions**, ARC and THRUST. A spin-in-place or a slam would
   be new `SwingPattern.Motion` values.
5. **HEAT has no authored content at all.** Needle Array is deliberately the
   first, because a subsystem with tests and no content is the one most likely
   to be quietly broken.

## Open questions before authoring

**1. Renamed in place, or replaced?** Pistol -> Bolt Driver, shotgun -> Scatter
Vent, sword -> Circular Saw. Renaming keeps every capture baseline recorded in
CLAUDE.md valid, because the numbers behind them do not move. Replacing
invalidates them and every A/B in this repo starts from a new baseline.

**2. Is a weapon meant to be unaffordable on the first shop visit?** This is a
question about the shop, not about the list, and the numbers already answer it
one way: wave one pays about 12 currency (measured), the cheapest weapon here is
20 and the cheapest authored ITEM is 8. So today the first visit buys an item
and cannot buy a weapon at all. That may be exactly right - it makes the second
weapon a goal rather than a formality - but it is currently an accident of two
numbers nobody chose together. Either weapon prices come down to 12-15, or this
is confirmed as the intent and written down.

**3. How many tier 4 weapons should a run be able to reach?** `tier_weight_per_wave`
for tier 4 is 0.9 from a base of 0, so tier 4 only becomes a common sight around
wave 10 of 20. Two tier-4 weapons in the list means a late run sees roughly the
same pair every time. Two is right if tier 4 is meant to be a rare prize; four
or five is right if it is meant to be the shape of a late build.
