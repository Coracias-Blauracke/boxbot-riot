class_name ShotSnapshot
extends EventPayload

## The payload of the CALCULATE_DAMAGE pipeline AND the frozen result carried by
## every projectile that shot produced.
##
## Sharing one snapshot across all projectiles is the design decision, not an
## optimisation: crit is rolled once per shot, so all eight pellets of a shotgun
## crit together, and a piercing projectile keeps critting on every enemy it
## passes through.
##
## Per-projectile state - pierce and bounce counters, distance travelled - does
## NOT live here. It belongs to the projectile, which has one each.

var source: EntityModel = null
var weapon: EntityModel = null

var amount: float = 0.0
var damage_type: StatTypes.DamageType = StatTypes.DamageType.RANGED

## Read and written by the pipeline BEFORE the roll, so an effect can grant
## "your next shot always crits" by setting the chance to 1.0.
var crit_chance: float = 0.0
var crit_multiplier: float = 2.0

## Set once the roll has happened; from then on it travels with every hit.
var is_crit: bool = false

@export_group("Falloff")
var falloff_start: float = 0.0
var falloff_end: float = 0.0
var falloff_multiplier: float = 1.0

## Statuses this shot tries to apply on hit, as {StatusEffect: stacks}.
var status_applications: Dictionary = {}

## Rolls the ONE crit this shot gets, applies the multiplier and credits it.
##
## Lives on the snapshot rather than in WeaponModel because a shot is not always
## fired by a weapon: a blast builds its own snapshot and has to roll in exactly
## the same way, down to which counters move. Two copies of these five lines is
## how a fix lands in one of them and not the other, which is the shape of every
## recurring bug in this repo so far.
##
## `weapon_model` may be null - an explosion that belongs to an entity rather
## than to a gun credits only its owner.
func roll_crit(shot_rng: RunRandom, weapon_model: EntityModel, holder: EntityModel) -> void:
	is_crit = shot_rng.chance(RunRandom.Stream.COMBAT, crit_chance)
	if not is_crit:
		return

	amount *= crit_multiplier
	if weapon_model != null:
		weapon_model.counters.add(CounterTypes.Counter.CRITS_LANDED)
	if holder != null:
		holder.counters.add(CounterTypes.Counter.CRITS_LANDED)
		holder.notify(Hooks.Hook.ON_CRIT, self)

## Takes another shot's crit outcome instead of rolling one.
##
## An explosion set off by a bullet is part of the SAME attack, and crit is
## rolled once per attack - the rule that makes all eight shotgun pellets crit
## together. Rolling again here would give one attack two independent chances,
## quietly making CRIT_CHANCE worth more on explosive weapons than on any other
## kind, for no reason a player could ever see.
##
## Nothing is credited: the counters and ON_CRIT already fired for the shot this
## is inheriting from, and a second helping would tally one crit as two.
func inherit_crit(other: ShotSnapshot) -> void:
	if other == null or not other.is_crit:
		return
	is_crit = true
	amount *= crit_multiplier

## Builds the per-hit event handed to the target's TAKE_DAMAGE pipeline.
## Fresh per impact, because absorption and cancellation are per target.
func to_damage_event(distance_travelled: float = 0.0, retained: float = 1.0) -> DamageEvent:
	var event := DamageEvent.new()
	event.source = source
	event.weapon = weapon
	event.amount = amount * falloff_at(distance_travelled) * retained
	event.damage_type = damage_type
	event.is_crit = is_crit
	return event

func falloff_at(distance: float) -> float:
	if falloff_end <= falloff_start or distance <= falloff_start:
		return 1.0
	if distance >= falloff_end:
		return falloff_multiplier
	return lerpf(1.0, falloff_multiplier, (distance - falloff_start) / (falloff_end - falloff_start))
