# Character list

Prose before `.tres`, as CLAUDE.md requires - and before the select screen is
written, because the screen has to draw whatever a character turns out to be.

**Setting**: the players are box-shaped robots, the enemies are Factorio-style
bugs. A character is a CHASSIS: same box, different build.

---

## What a character already is

`CharacterData` exists and needs no new fields for anything below:

| field | what it says |
|---|---|
| `base_stats` | the chassis - MAX_HP, MOVEMENT_SPEED and whatever else it is born with |
| `starting_weapons` | granted through the same path a purchase takes, so it can be sold |
| `starting_items` | the same, and listing one twice grants two copies |
| `weapon_slots` | applied as a BASE modifier to WEAPON_SLOTS |
| `shop_slots` | the same, to SHOP_SLOTS; 0 means ShopData decides |
| `innate_effects` | abilities, the SAME type as item effects |

`innate_effects` is **declared and used by no authored character**, which is why
this list deliberately spends some of its roster on it. In this repo a path that
is built and unexercised has three times turned out to be quietly wrong.

### The authoring convention

Authoring eight characters must not mean eight independent decisions about how a
number is written down.

- **MAX_HP and MOVEMENT_SPEED are authored as BASE**, absolutely. They are what
  the chassis IS, so a character says `160`, not `+60`.
- **Everything else is a FLAT or PERCENT modifier**, so it lands in the same
  pool an item would land in and composes with items rather than replacing them.
- **A PERCENT on the holder reaches their weapons.** `-15%` RANGED_DAMAGE on a
  character whose own ranged damage is 0 still takes a sixth off the gun they
  are holding - that is what `WeaponModel.combined_stat` does now, and it is the
  only reason a damage penalty on a character means anything at all.

### The baseline

**Standard Unit is 100 HP and 220 speed**, which is exactly what
`test_character` already carries. Every character below is a delta from it, and
the deltas are written in the table so they can be compared at a glance rather
than reconstructed from eight files.

### Rules the roster follows

**A character is a TRADE, not a bonus.** Every entry gives something up. A
roster of upside-only characters collapses into one correct pick, and the pick
is whichever number the current build happens to reward.

**No character is a tutorial for another.** Standard Unit exists as a control -
the thing every balance judgement is measured against - not as "the weak one you
graduate from".

**Two players may pick the same character.** Forbidding it invents rules nobody
asked for: what happens when the catalogue is smaller than the player count,
what happens when a player leaves and frees a pick, and what four players do
with two authored characters. "We both want the tank" is not a problem worth
code on a shared couch.

**A character starts with at most ONE weapon.** Six slots and a shop full of
weapons is where a build comes from; a character handing over three of them
spends the interesting decision before the run starts.

---

## The eight

Deltas from 100 HP / 220 speed. Percentages are PERCENT modifiers, bare numbers
are FLAT.

| # | character | chassis | modifiers | starts with | costs |
|---|---|---|---|---|---|
| 1 | **Standard Unit** | 100 / 220 | - | Bolt Driver I | nothing |
| 2 | **Riveter** | 90 / 220 | ATTACK_SPEED +25%, RANGED_DAMAGE -15% | Rivet Repeater I | nothing |
| 3 | **Bulwark** | 165 / 165 | ARMOR +6, weapon_slots 5 | Servo Fists I | nothing |
| 4 | **Skirmisher** | 70 / 300 | DODGE +0.20, MELEE_DAMAGE +4 | Circular Saw I | nothing |
| 5 | **Bloodletter** | 75 / 230 | LIFESTEAL +0.06, BLEED_CHANCE +0.15 | Serrated Drill I | nothing |
| 6 | **Furnace** | 115 / 195 | BURN_CHANCE +0.20, ATTACK_SPEED -10% | Scatter Vent I | one existing effect |
| 7 | **Prospector** | 95 / 220 | CURRENCY_GAIN +30%, SHOP_SLOTS +2, RANGED_DAMAGE -20% | Bolt Driver I | one stat read |
| 8 | **Blood Bank** | 220 / 205 | HP_REGEN +0.5, CRIT_CHANCE -0.05 | Hydraulic Shears I | one new effect class |

**1. Standard Unit** is `test_character` with its eight bleed items stripped -
those were debug scaffolding for the status system and are called out as
temporary in CLAUDE.md. It keeps the Bolt Driver, which the weapon list already
names as the starting weapon.

**2. Riveter** is the rapid build with the drawback the rapid weapons already
have written into them: a flat damage bonus is worth less per second when every
shot is small. Its `-15%` scales the gun, so it is a real cost rather than a
number in the sheet.

**3. Bulwark** is the armor formula made playable. At `armor / (armor + 15)`, 6
armor is 29% off every hit, and 165 HP behind it is another 65%. It gives up a
weapon slot, which is the only stat in the game that cannot be bought back
cheaply, and a quarter of its speed - the horde catches it, which is the whole
point of having armor at all.

**4. Skirmisher** starts at a third of the dodge cap and never gets hit by the
first bug through the door. 70 HP means two mistakes end it. It carries flat
MELEE_DAMAGE rather than a percent so its saw is worth swinging on wave one.

**5. Bloodletter** is the bleed character the four authored bleed items were
waiting for, and the reason `Serrated Drill` exists. Lifesteal only answers
HITS, so the drill (fast, melee, already bleeding everything) is the weapon that
makes the 6% mean anything.

**6. Furnace** is the first character with an ABILITY: *enemies that are burning
take 20% more damage from you*. That is `EffectDamageVersusStatus`, which
already exists and is already used by an item - so the ability costs a `.tres`
and nothing else. It is here specifically to walk `innate_effects` end to end.

**7. Prospector** buys its way through the run: a third more currency, two more
shop slots, and a fifth off its damage to pay for it. **CURRENCY_GAIN is not
read by anything today** - see below.

**8. Blood Bank** pays for everything in MAX HP instead of currency, at 0.35 HP
per unit of price, which is why it is a 220 HP chassis. It is the character the
shop's stat-payment path was built for and never given: `PriceEvent` carries
`uses_stat_payment` and `pay_with_stat`, `ShopManager` spends whichever is
named, and **no effect in `core/effects/library` sets either one**. Only a test
double does.

---

## What the list exposes as missing in the engine

Six of the eight need no code at all, which is the same ratio the item list
produced and the reason the prose comes first.

1. **CURRENCY_GAIN is a dead stat.** It has metadata, a row in the stat sheet
   and no reader anywhere - `add_currency()` credits the raw amount. CLAUDE.md
   already lists it as the one remaining cheap wire. Prospector is the content
   that makes it worth doing: one read, one regression test.

2. **Nothing drives `CALCULATE_PRICE` from content.** The pipeline exists, the
   shop honours both a changed price and a stat payment, and the only things
   that have ever used it are two test doubles inside `core_test.gd`. One effect
   class - price share plus an optional payment stat - covers Blood Bank, every
   "items cost 20% less" item, and every future character that pays in
   something other than money. That is a FAMILY, which is the bar this repo sets
   for writing an effect class at all.

3. **A character has no portrait.** `EntityData.icon` exists and nothing draws
   it; the select screen will show a name and derived stat lines, exactly as the
   shop's detail block does. Not a gap in the engine, but it is the first screen
   that will look empty without art.

4. **Nothing distinguishes a character from an enemy in the shop's eyes.** Both
   are `EntityData`, both carry an unused `tier` and `base_price`. That is the
   deliberate trade written into CLAUDE.md and it costs nothing here - but it
   does mean the validator cannot tell a character file from an enemy file by
   type alone, only by which folder it is in and which class it declares.

---

## Open questions

**1. May a character start with a weapon a shop would never offer at wave one?**
Every starting weapon above is tier I and in the shop pool, so nothing here
tests it. A "starts with a tier III weapon and no shop for three waves" design
is expressible today and nobody has decided whether it should be.

**2. Does the roster want an unlock system?** Every character below is available
from the first launch. Brotato gates most of its roster behind wins, which is a
save-system feature and there is no save system. Deferred, deliberately: the
gate is one boolean per character once saving exists.

**3. What does a character cost the select screen?** Eight fit in a cycled list
per player. Forty do not, and that is when the screen needs a grid, a scroll and
a filter. Nothing here is designed for forty - the screen is being built for
eight and will be rebuilt once the roster is a real one.

Settled while writing this:

**Duplicate picks are allowed**, for the reasons under *Rules the roster
follows*.

**The default pick prefers a character nobody else is on.** With eight
characters and four players, the common case is four different chassis and
nobody has to press anything to get there. It is a DEFAULT, not a rule: the
second player may still cycle back onto the first player's pick.

**Selections live in `PlayerRoster`, beside the devices.** They are decided
before a run and re-decided between runs, which is the same argument that put
the roster in the lobby - and it is what makes a restart keep both who was
playing AND what they were playing.
