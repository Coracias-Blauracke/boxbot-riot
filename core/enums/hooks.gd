class_name Hooks

## Two categories of hooks - this split is the centrepiece of the effect system.
##
## NOTIFICATION - "this happened". Read-only payload, order is irrelevant.
## PIPELINE     - "this is about to happen, change it". The payload is MUTABLE
##                and passes through every effect in `priority` order. Without
##                this, armor, resistances and a shop that charges a stat
##                instead of currency are simply not implementable.
enum Kind {
	NOTIFICATION,
	PIPELINE,
}

## Who an effect applies to. Matters in co-op: "+30% map size" must aggregate
## once per player at world scope, while "+10% damage" stays with its owner.
enum Scope {
	SELF,
	TEAM,
	WORLD,
}

## Same convention as the other enums: only APPEND new values.
enum Hook {
	# --- pipelines ---
	CALCULATE_DAMAGE,
	TAKE_DAMAGE,
	CALCULATE_HEAL,
	CALCULATE_PRICE,
	ROLL_SHOP_ITEMS,
	BEFORE_DEATH,
	# --- notifications ---
	ON_DAMAGE_DEALT,
	ON_DAMAGE_TAKEN,
	ON_HEAL,
	ON_KILL,
	ON_DEATH,
	ON_STEP,
	ON_WAVE_STARTED,
	ON_WAVE_ENDED,
	ON_ITEM_BOUGHT,
	ON_ITEM_SOLD,
	ON_REROLL,
	ON_STATUS_APPLIED,
	ON_STATUS_RECEIVED,
	ON_WEAPON_FIRED,
	ON_CRIT,
	## Pipeline evaluated when a status is about to be applied. Runs first on
	## the applier (offence: "+10% chance to apply", "statuses last longer"),
	## then on the target (defence: resistances, immunities).
	CALCULATE_STATUS,
	ON_STATUS_TICK,
	ON_STATUS_EXPIRED,
	## Pipeline run over every player before a wave begins. This is where
	## "10% chance per wave to spawn a boss" and wave-composition tweaks live.
	CALCULATE_WAVE,
	ON_SHOP_OPENED,
	ON_SHOP_CLOSED,
	## Fired on the projectile when it hits something. This is where explosions,
	## lingering puddles and chain effects hang.
	ON_IMPACT,
	ON_OVERHEAT,
}

const KINDS: Dictionary = {
	Hook.CALCULATE_DAMAGE: Kind.PIPELINE,
	Hook.TAKE_DAMAGE: Kind.PIPELINE,
	Hook.CALCULATE_HEAL: Kind.PIPELINE,
	Hook.CALCULATE_PRICE: Kind.PIPELINE,
	Hook.ROLL_SHOP_ITEMS: Kind.PIPELINE,
	Hook.BEFORE_DEATH: Kind.PIPELINE,
	Hook.ON_DAMAGE_DEALT: Kind.NOTIFICATION,
	Hook.ON_DAMAGE_TAKEN: Kind.NOTIFICATION,
	Hook.ON_HEAL: Kind.NOTIFICATION,
	Hook.ON_KILL: Kind.NOTIFICATION,
	Hook.ON_DEATH: Kind.NOTIFICATION,
	Hook.ON_STEP: Kind.NOTIFICATION,
	Hook.ON_WAVE_STARTED: Kind.NOTIFICATION,
	Hook.ON_WAVE_ENDED: Kind.NOTIFICATION,
	Hook.ON_ITEM_BOUGHT: Kind.NOTIFICATION,
	Hook.ON_ITEM_SOLD: Kind.NOTIFICATION,
	Hook.ON_REROLL: Kind.NOTIFICATION,
	Hook.ON_STATUS_APPLIED: Kind.NOTIFICATION,
	Hook.ON_STATUS_RECEIVED: Kind.NOTIFICATION,
	Hook.ON_WEAPON_FIRED: Kind.NOTIFICATION,
	Hook.ON_CRIT: Kind.NOTIFICATION,
	Hook.CALCULATE_STATUS: Kind.PIPELINE,
	Hook.ON_STATUS_TICK: Kind.NOTIFICATION,
	Hook.ON_STATUS_EXPIRED: Kind.NOTIFICATION,
	Hook.CALCULATE_WAVE: Kind.PIPELINE,
	Hook.ON_SHOP_OPENED: Kind.NOTIFICATION,
	Hook.ON_SHOP_CLOSED: Kind.NOTIFICATION,
	Hook.ON_IMPACT: Kind.NOTIFICATION,
	Hook.ON_OVERHEAT: Kind.NOTIFICATION,
}

static func kind_of(hook: Hook) -> Kind:
	return KINDS.get(hook, Kind.NOTIFICATION)

static func is_pipeline(hook: Hook) -> bool:
	return kind_of(hook) == Kind.PIPELINE
