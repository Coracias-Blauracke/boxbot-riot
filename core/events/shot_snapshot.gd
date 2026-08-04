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
