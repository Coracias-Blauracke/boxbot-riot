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

So Bolt Driver runs 12 / 19 / 29 / 45 damage at 12 / 26 / 58 / 128 currency.
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

## The thirteen families

Damage and price shown for tier I. Firing intervals are seconds.

### gun

| # | family | firing | delivery | spread | target | tags | scaling | dmg / price |
|---|---|---|---|---|---|---|---|---|
| 1 | **Bolt Driver** | INSTANT 0.45 | projectile | single | nearest | gun | default | 12 / 12 |
| 2 | **Scatter Vent** | INSTANT 0.90 | projectile | cone 6 | nearest | gun | default | 5 / 20 |
| 3 | **Rail Spike** | WINDUP 1.6 | projectile | single | by_health HIGHEST | gun | 150% RANGED | 40 / 40 |
| 13 | **Slag Mortar** | INSTANT 1.30 | projectile, EXPLODES | single | nearest | gun | default, + 60% RANGED as blast | 14 / 30 |

- **Bolt Driver** is the existing pistol renamed, and the starting weapon.
- **Scatter Vent** is the existing shotgun: six pellets, falloff 110 -> 280 at
  x0.4, so it is a room-clearer and useless at range. Damage is PER PELLET.
- **Rail Spike** spins up for 1.6s, carries PIERCING +3 and aims at the toughest
  thing on screen. Its 150% scaling is the counterweight to the rapid weapons: a
  slow weapon should reward flat damage items MORE, not less.
- **Slag Mortar** was added after this list was written, once area damage
  existed - it is the family the engine could not express when the other twelve
  were chosen, which is why the list has thirteen entries and its numbering runs
  to 13 out of order.

  The charge it fires carries the explosion, not the weapon: `slag_charge.tres`
  holds one `EffectBlast` on impact, and the blast is authored as 60% of the
  WEAPON's ranged damage rather than a number of its own. All four tiers
  therefore scale from the single damage figure in the tier table, and ONE
  projectile file serves the whole family.

  It is tagged `gun` rather than given a class of its own. A class needs
  thresholds up to six and there is exactly one explosive family, so a `blast`
  class would be one nobody could ever complete.

### rapid

| # | family | firing | delivery | spread | target | tags | scaling | dmg / price |
|---|---|---|---|---|---|---|---|---|
| 4 | **Rivet Repeater** | INSTANT 0.18 | projectile | single | nearest | gun, rapid | 50% RANGED | 5 / 14 |
| 5 | **Needle Array** | INSTANT 0.10 | projectile | single | by_health LOWEST | gun, rapid | 35% RANGED | 3 / 26 |
| 6 | **Servo Fists** | INSTANT 0.30 | melee ARC 70 | - | nearest | rapid, blade | 60% MELEE | 8 / 10 |

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
| 7 | **Circular Saw** | INSTANT 0.60 | melee ARC 150 | - | nearest | blade | default | 14 / 12 |
| 8 | **Hydraulic Shears** | INSTANT 0.80 | melee THRUST | - | nearest | blade | default | 20 / 24 |

- **Circular Saw** replaces the sword. Wide sweep, no frills, tier I is cheap.
- **Hydraulic Shears** carry +15% CRIT_CHANCE of their own and a long thrust:
  single target, picks its moment.
- **Guillotine Arm was cut** to reach twelve. It came out of `blade` because
  that was the best-covered class at five families, while `bouncy` sits at two -
  cutting from the thickest keeps the roster even. Rail Spike still covers the
  slow-heavy role on the ranged side, so nothing was lost that has no echo.

### bouncy

| # | family | firing | delivery | spread | target | tags | scaling | dmg / price |
|---|---|---|---|---|---|---|---|---|
| 9 | **Carom Pistol** | INSTANT 0.50 | projectile | single | nearest | bouncy | default | 10 / 16 |
| 10 | **Pinball Launcher** | INSTANT 1.10 | projectile | fan 4 | nearest | bouncy | default | 9 / 44 |

BOUNCING is carried by the weapon: +2 on Carom, +4 on Pinball, and both rise a
step per tier. Neither is tagged `gun` - otherwise `gun` would sit on two thirds
of the roster and its set bonus would cost nothing to complete, which is the
failure mode of a tag that means "ranged".

### bloody

| # | family | firing | delivery | spread | target | tags | scaling | dmg / price |
|---|---|---|---|---|---|---|---|---|
| 11 | **Serrated Drill** | INSTANT 0.40 | melee THRUST | - | nearest | blade, bloody | default | 9 / 14 |
| 12 | **Sanguine Sprayer** | INSTANT 0.70 | projectile | cone 5 | nearest | bloody | default | 4 / 46 |

- Both apply bleed through `EffectApplyStatusOnHit`, with their own
  `base_chance` rather than relying on the holder's stats - an item raising
  BLEED_CHANCE then adds to something rather than multiplying zero.
- **Sanguine Sprayer** also carries `EffectHealWhenHittingStatus`, so it heals
  its wielder for hitting something already bleeding. Both effect classes exist.

Twelve families. Tier I prices are set so the FIRST shop visit can buy a
weapon: wave one pays about 12, and Servo Fists at 10, Bolt Driver at 12 and
Circular Saw at 12 are all reachable. Enemy counts and currency per kill will be
tuned against play, not the other way round.

---

## Class membership

Counted in FAMILIES; carried duplicates raise the real count further, which is
what makes a set reachable at all.

| tag | families | reachable set |
|---|---|---|
| gun | 5 | easily, and with variety |
| blade | 4 | easily |
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

1. **BEAM and SUMMON deliveries do not exist.** `weapon.gd` implements only
   PROJECTILE and MELEE_SWEEP, which blocks anything laser-shaped and the whole
   turret and drone family. They are now GUARDED rather than merely missing:
   the validator refuses such a weapon outright and the runtime reports it once
   by name. An earlier draft of this list said they "fall through in silence",
   which was wrong - there was a push_warning, unnamed and repeated on every
   attempted shot, which is close enough to silence to mislead but not close
   enough to write down as fact.
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

All three are answered. Recorded here because the reasons matter more than the
answers:

**1. Guillotine Arm was cut**, from `blade` rather than from a thin class.

**2. A weapon IS affordable on the first visit.** Tier I prices come down to
10-46, with three weapons at or under 12. Enemy counts and currency per kill get
tuned against play afterwards.

**3. Thresholds are authored INDIVIDUALLY and need not be contiguous.** A class
may grant something at every count from one to six, or nothing at all until six
and then one large thing. `WeaponClassTier` carries `effects` as well as
`modifiers` for exactly that second case - a payoff that a stat line cannot
express. Both shapes cost the same: they are just which tiers exist in the
array.
