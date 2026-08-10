class_name StatTypes

## CRITICAL CONVENTION: only ever APPEND new values to the end of an enum.
## These values are serialized into .tres files as plain numbers
## (stat = 14, modifier_type = 1). Inserting anything in the middle silently
## reinterprets every existing content file. Appending is always safe.

enum Stat {
	# --- survivability ---
	MAX_HP,
	HP_REGEN,
	LIFESTEAL,
	ARMOR,
	DODGE,
	# --- damage ---
	MELEE_DAMAGE,
	RANGED_DAMAGE,
	ELEMENTAL_DAMAGE,
	ATTACK_SPEED,
	CRIT_CHANCE,
	CRIT_MULTIPLIER,
	# --- projectiles / reach ---
	RANGE,
	PIERCING,
	BOUNCING,
	# --- movement / pickup ---
	MOVEMENT_SPEED,
	PICKUP_RANGE,
	# --- economy and utility ---
	WEAPON_SLOTS,
	LUCK,
	CURRENCY_GAIN,
	HARVESTING,
	ENGINEERING,
	# --- status effects ---
	STATUS_CHANCE,
	BLEED_DAMAGE,
	POISON_DAMAGE,
	BURN_DAMAGE,
	# --- world (stats of the map model, not of a character) ---
	MAP_SIZE,
	# --- weapons ---
	## Half-angle of the inaccuracy cone, in degrees. 0 is perfectly accurate.
	SPREAD_ANGLE,
	PROJECTILE_SPEED,
	## Heat is available to every weapon; heat_per_shot = 0 simply disables it.
	HEAT_CAPACITY,
	HEAT_DISSIPATION,
	## Push applied to the wielder when firing. Almost always 0.
	RECOIL,
	## How many things this buyer is offered in the shop.
	##
	## A STAT for the same reason WEAPON_SLOTS is one: "you see 6 items instead
	## of 4" is then an ordinary modifier that any item or character effect can
	## apply, and the shop never learns that such a thing exists. 0 means the
	## buyer has no opinion and ShopData.offer_count decides.
	SHOP_SLOTS,
	# --- status axes ---
	#
	# Per status rather than generic, because the whole point of having four
	# statuses is that they behave differently. A status names which of these it
	# reads via StatusScaling, and generic composes with specific: bleed can list
	# both STATUS_CHANCE and BLEED_CHANCE, and an item raising either one works.
	BLEED_CHANCE,
	BLEED_RATE,
	BLEED_MAX_STACKS,
	BURN_CHANCE,
	BURN_RATE,
	BURN_MAX_STACKS,
	POISON_CHANCE,
	POISON_RATE,
	POISON_MAX_STACKS,
	SLOW_CHANCE,
	SLOW_POWER,
	BURN_SPREAD_RADIUS,
	SLOW_DURATION,
}

## get_stat() computes: (base + flat) * (1.0 + percent) * mult
##
## PERCENT is a single additive pool - "increased" in PoE terms. Two +50%
## modifiers give x2.0, not x2.25. This is the default and covers almost
## everything.
##
## MULT is multiplicative - "more" in PoE terms. Each modifier composes as a
## separate factor, so two 1.5x modifiers give x2.25. Reserved for effects that
## must feel exceptional (a legendary "doubles your damage"). Ignore it and
## nothing changes: an empty MULT pool evaluates to 1.0.
enum Modifier {
	BASE,
	FLAT,
	PERCENT,
	MULT,
}

enum DamageType {
	MELEE,
	RANGED,
	ELEMENTAL,
	BLEED,
	POISON,
	BURN,
	TRUE_DAMAGE,
}

## Lower bounds applied in get_stat(). Without them a single -100% modifier
## yields negative movement speed or zero max HP, which then divides by zero
## further down the chain. Stats absent from this map are left unclamped
## (zero damage is a legitimate value).
## The value at which a stat contributes NOTHING.
##
## 0.0 for a quantity - no damage, no range, no piercing - and 1.0 for a
## multiplier, where "no effect" means leaving the number alone.
##
## This doubles as the COMBINATION RULE for a weapon inheriting its wielder's
## stat, which is why it is one table rather than two. An additive identity of 0
## means the two are ADDED; a multiplicative identity of 1 means they are
## MULTIPLIED. Storing those as separate facts would let them disagree, and the
## disagreement would be silent: adding a wielder's 1.0 attack speed to a
## weapon's 1.0 doubles every weapon's rate of fire out of nowhere.
##
## Distinct from FLOORS below. A floor is how low a stat may be pushed;
## a neutral is where it stops mattering. MAX_HP floors at 1.0 and is neutral
## at 0.0.
const NEUTRALS: Dictionary = {
	Stat.ATTACK_SPEED: 1.0,
	Stat.PROJECTILE_SPEED: 1.0,
	Stat.CRIT_MULTIPLIER: 1.0,
}

static func neutral_of(stat: Stat) -> float:
	return NEUTRALS.get(stat, 0.0)

## True when the stat composes by multiplication rather than addition. Read off
## the neutral rather than answered separately, so the two can never disagree.
static func is_multiplicative(stat: Stat) -> bool:
	return not is_zero_approx(neutral_of(stat))

## How high a stat may go. The twin of FLOORS below, applied in the same place,
## so a capped stat reads its capped value EVERYWHERE - including the player's
## stat sheet, which is what stops somebody buying dodge they cannot use.
##
## DODGE is capped because it is a chance to take NOTHING. At 1.0 the entity is
## untouchable and every "when you take damage" effect in the game stops firing
## silently. 0.6 leaves four hits in ten landing, which is about x2.5 effective
## health - strong, and still a game.
const CAPS: Dictionary = {
	Stat.DODGE: 0.6,
}

## Armor at which incoming damage is halved, and the whole armor curve:
##
##   reduction = armor / (armor + ARMOR_HALF_POINT)
##
## Diminishing in REDUCTION and linear in survival, which is the point and the
## reason nearly every game uses this shape. Each point of armor always adds
## 1/15 of the holder's health as effective health, so armor never stops being
## worth buying, while the reduction itself approaches 1.0 without reaching it -
## something always gets through, and effects that hang on taking damage cannot
## be switched off by stacking.
const ARMOR_HALF_POINT := 15.0

static func armor_reduction(armor: float) -> float:
	if armor <= 0.0:
		return 0.0
	return armor / (armor + ARMOR_HALF_POINT)

const FLOORS: Dictionary = {
	Stat.MAX_HP: 1.0,
	Stat.MOVEMENT_SPEED: 0.0,
	Stat.ATTACK_SPEED: 0.05,
	Stat.RANGE: 0.0,
	Stat.WEAPON_SLOTS: 0.0,
	Stat.MAP_SIZE: 0.1,
	Stat.CRIT_MULTIPLIER: 1.0,
	Stat.SPREAD_ANGLE: 0.0,
	## A multiplier, so it must be allowed below 1.0 for "slow projectiles"
	## effects - only prevented from reaching zero or going negative.
	Stat.PROJECTILE_SPEED: 0.1,
	Stat.HEAT_CAPACITY: 1.0,
	Stat.HEAT_DISSIPATION: 0.0,
	Stat.RECOIL: 0.0,
	## A share ADDED to 1.0, so -1.0 is "you earn nothing" and anything below it
	## would mean a kill TAKES money off the killer. The floor lives here rather
	## than as a clamp inside add_currency for the usual reason: it is a property
	## of the stat, so the stat sheet shows the same number the arithmetic uses.
	Stat.CURRENCY_GAIN: -1.0,
}
