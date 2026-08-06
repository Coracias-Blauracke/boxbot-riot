# Weapon list - families

Prose before `.tres`, as CLAUDE.md requires. Nothing here is authored yet.

**Setting**: the players are box-shaped robots. The enemies on the release map
are Factorio-style bugs, which is why bleed stays bleed - the statuses land on
the bugs, not on the robots.

---

## How families work

**Every weapon is a FAMILY of four tiers.** Bolt Driver I -> II -> III -> IV is
one weapon at four power levels, not four weapons. There are no single-tier
weapons: one rule, no exceptions to mark in the UI.

**Duplicates are carried normally.** Two Bolt Driver I occupy two slots and
count as two toward the `gun` class. This is the decision the shop exists to
pose: four copies of one weapon complete a class set, one merged copy is
stronger, and six slots mean you cannot have both.

**Merging is a player action in the shop.** Two identical weapons of the same
tier combine into one of the next tier, freeing a slot.

**Auto-merge fires in exactly one case**: every slot is full AND the weapon just
bought duplicates one already carried at the same tier. Without it that purchase
would be impossible, so it merges itself. A weapon at tier IV has nothing to
merge into, so a full rack still refuses it.

### Tier convention

Authoring 48 files must not mean 48 independent design decisions. A tier keeps
every axis identical - same firing pattern, same spread, same targeting, same
tags, same scaling - and moves two numbers:

| step | damage | price |
|---|---|---|
| I -> II | x1.55 | x2.2 |
| II -> III | x1.55 | x2.2 |
| III -> IV | x1.55 | x2.2 |

So Bolt Driver runs 12 / 19 / 29 / 45 damage at 25 / 55 / 120 / 265 currency.
Anything that deviates from this is a deliberate note on the weapon below.

**Author tier I of everything first.** Twelve files makes the game playable with
twelve weapons; the other thirty-six are mechanical afterwards. A half-authored
roster of tier I is worth more than three complete families.

---

## Classes

Five, all buildable with what the engine has today. Thresholds run 1 to 6,
because six is the default `weapon_slots` and a full set of one class is a total
commitment that should pay for itself.

| tag | bonus stat | why that stat |
|---|---|---|
| `gun` | RANGED_DAMAGE, RANGE | |
| `rapid` | ATTACK_SPEED | |
| `blade` | MELEE_DAMAGE, CRIT_CHANCE | |
| `bouncy` | BOUNCING | |
| `bloody` | BLEED_CHANCE, BLEED_DAMAGE | |

**Each threshold authors an INCREMENT, not a total** - the tiers are cumulative,
so six steps of +2 give +12 at a full set.

**Prefer stats scoped to the class.** A class bonus goes into the HOLDER's stats
and from there reaches every weapon they carry, so `blade` granting ATTACK_SPEED
would speed up their pistols too. MELEE_DAMAGE, RANGED_DAMAGE, BOUNCING and the
BLEED stats are self-limiting; CRIT_CHANCE and ATTACK_SPEED are not, and want
using sparingly and knowingly.

---

## The twelve families

Damage and price shown for tier I. Firing intervals are seconds.

### gun

| # | family | firing | delivery | spread | target | tags | scaling | dmg / price |
|---|---|---|---|---|---|---|---|---|
| 1 | **Bolt Driver** | INSTANT 0.45 | projectile | single | nearest | gun | default | 12 / 25 |
| 2 | **Scatter Vent** | INSTANT 0.90 | projectile | cone 6 | nearest | gun | default | 5 / 45 |
| 3 | **Rail Spike** | WINDUP 1.6 | projectile | single | by_health HIGHEST | gun | 150% RANGED | 40 / 90 |

- **Bolt Driver** is the existing pistol renamed, and the starting weapon.
- **Scatter Vent** is the existing shotgun: six pellets, falloff 110 -> 280 at
  x0.4, so it is a room-clearer and useless at range. Damage is PER PELLET.
- **Rail Spike** spins up for 1.6s, carries PIERCING +3 and aims at the toughest
  thing on screen. Its 150% scaling is the counterweight to the rapid weapons: a
  slow weapon should reward flat damage items MORE, not less.

### rapid

| # | family | firing | delivery | spread | target | tags | scaling | dmg / price |
|---|---|---|---|---|---|---|---|---|
| 4 | **Rivet Repeater** | INSTANT 0.18 | projectile | single | nearest | gun, rapid | 50% RANGED | 5 / 30 |
| 5 | **Needle Array** | INSTANT 0.10 | projectile | single | by_health LOWEST | gun, rapid | 35% RANGED | 3 / 55 |
| 6 | **Servo Fists** | INSTANT 0.30 | melee ARC 70 | - | nearest | rapid, blade | 60% MELEE | 8 / 20 |

- **Rivet Repeater** fires five times a second. Its 50% scaling is the entire
  reason `damage_scaling` exists.
- **Needle Array** carries `heat_per_shot` 0.12, so it overheats after roughly
  three seconds of held fire and vents at 35%. It is deliberately the FIRST
  authored weapon to use heat: the whole heat layer has tests and no content,
  which makes it the least trustworthy part of the weapon code.
- **Servo Fists** are punches at reach 40 - cheapest weapon in the game, and the
  reason `rapid` crosses melee and ranged.

### blade

| # | family | firing | delivery | spread | target | tags | scaling | dmg / price |
|---|---|---|---|---|---|---|---|---|
| 7 | **Circular Saw** | INSTANT 0.60 | melee ARC 150 | - | nearest | blade | default | 14 / 30 |
| 8 | **Hydraulic Shears** | INSTANT 0.80 | melee THRUST | - | nearest | blade | default | 20 / 55 |
| 9 | **Guillotine Arm** | WINDUP 2.0 | melee ARC 180 | - | by_health HIGHEST | blade | 150% MELEE | 55 / 140 |

- **Circular Saw** replaces the sword. Wide sweep, no frills, tier I is cheap.
- **Hydraulic Shears** carry +15% CRIT_CHANCE of their own and a long thrust:
  single target, picks its moment.
- **Guillotine Arm** is the melee heavy - two seconds of windup, huge reach,
  aimed at the toughest thing on screen. The melee mirror of Rail Spike.

### bouncy

| # | family | firing | delivery | spread | target | tags | scaling | dmg / price |
|---|---|---|---|---|---|---|---|---|
| 10 | **Carom Pistol** | INSTANT 0.50 | projectile | single | nearest | bouncy | default | 10 / 35 |
| 11 | **Pinball Launcher** | INSTANT 1.10 | projectile | fan 4 | nearest | bouncy | default | 9 / 95 |

BOUNCING is carried by the weapon: +2 on Carom, +4 on Pinball, and both rise a
step per tier. Neither is tagged `gun` - otherwise `gun` would sit on two thirds
of the roster and its set bonus would cost nothing to complete, which is the
failure mode of a tag that means "ranged".

### bloody

| # | family | firing | delivery | spread | target | tags | scaling | dmg / price |
|---|---|---|---|---|---|---|---|---|
| 12 | **Serrated Drill** | INSTANT 0.40 | melee THRUST | - | nearest | blade, bloody | default | 9 / 30 |
| 13 | **Sanguine Sprayer** | INSTANT 0.70 | projectile | cone 5 | nearest | bloody | default | 4 / 100 |

- Both apply bleed through `EffectApplyStatusOnHit`, with their own
  `base_chance` rather than relying on the holder's stats - an item raising
  BLEED_CHANCE then adds to something rather than multiplying zero.
- **Sanguine Sprayer** also carries `EffectHealWhenHittingStatus`, so it heals
  its wielder for hitting something already bleeding. Both effect classes exist.

That is thirteen families, not twelve. Cut one before authoring - Pinball
Launcher and Guillotine Arm are the two least load-bearing.

---

## Class membership

Counted in FAMILIES; carried duplicates raise the real count further, which is
what makes a set reachable at all.

| tag | families | reachable set |
|---|---|---|
| gun | 5 | easily, and with variety |
| blade | 5 | easily |
| rapid | 3 | yes, duplicates fill the rest |
| bouncy | 2 | needs duplicates past 2 |
| bloody | 2 | needs duplicates past 2 |

`bouncy` and `bloody` being thin is deliberate for a first pass: they are the
classes where the "four copies or one merged" decision bites hardest, which is
exactly what wants play-testing before more content is poured in.

---

## What the list exposes as missing in the engine

Not one weapon here needs a new effect class. `EffectApplyStatusOnHit` and
`EffectHealWhenHittingStatus` cover the only two behaviours in the list, and
everything else is stat lines over axes that already exist.

What could not be written, and why:

1. **BEAM and SUMMON deliveries do not exist.** `weapon.gd` matches only
   PROJECTILE and MELEE_SWEEP; the other two enum values fall through in
   silence, which makes them look supported. Blocks anything laser-shaped and
   the whole turret and drone family.
2. **No projectile-count stat.** The number lives inside `SpreadPattern`, so a
   `multishot` class bonus would have nothing to raise.
3. **No knockback stat**, which is the real reason `crush` is not a class.
4. **Only two swing motions**, ARC and THRUST.
5. **Heat has no authored content.** Needle Array is the first, on purpose.

## Open questions

**1. Which family gets cut to reach twelve?** Pinball Launcher and Guillotine
Arm are the candidates.

**2. Is a weapon meant to be unaffordable on the first shop visit?** Wave one
pays about 12 currency (measured), the cheapest tier I weapon here is 20 and the
cheapest authored item is 8. So the first visit buys an item and cannot buy a
weapon. That may be right - it makes the second weapon a goal - but it is
currently an accident of two numbers nobody chose together.

**3. Do the six class thresholds all carry a bonus, or only some counts?**
Six steps per class over five classes is thirty increments to tune. Bonuses at
1/2/3/4/5/6 make a class felt from the first weapon; bonuses at 2/4/6 make each
one an event. Both are authorable today with no code difference.
