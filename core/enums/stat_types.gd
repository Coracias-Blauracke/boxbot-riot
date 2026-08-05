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
}
