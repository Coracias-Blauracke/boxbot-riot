class_name StatusSpreadOnDeath
extends StatusDamageOverTime

## Burn: when whatever is carrying it dies, it jumps to everything nearby.
##
## Hooks ON_DEATH rather than on_expired(): the status is meant to spread off a
## CORPSE, not off a fire that simply burned out. ActiveStatus registers with the
## dispatcher like any effect, so a status taking part in a hook needs no
## machinery beyond saying so - which is what the base class documents.

## World units. Scaled by the applier's stat when one is named on the SPREAD
## axis, so "+25% fire spread radius" is an ordinary item.
@export var spread_radius: float = 90.0

## How many neighbours catch it. 0 is unlimited, which with a big radius is how
## a wipe turns into a chain reaction.
@export var max_targets: int = 3

func get_hooks() -> Array:
	return [Hooks.Hook.ON_DEATH]

func execute(host: Variant, inst: EffectInstance, _event: EventPayload) -> void:
	var active := inst as ActiveStatus
	if active == null:
		return

	var carrier := host as EntityModel
	var census := carrier.get_census()
	if census == null:
		return

	# The ORIGINAL applier keeps the credit, so a chain of spreads still feeds
	# that player's "every 1000 fire damage" and not the corpse's.
	var applier := active.get_applier()
	var caught := 0

	# Resolved from the applier at the moment it spreads, not snapshotted: the
	# reach belongs to whoever lit the fire, and they are still around to ask.
	var reach := spread_radius * (1.0 + bonus_for(StatusScaling.Axis.SPREAD_RADIUS, applier))

	for neighbour in census.entities_within(carrier.world_position, reach, carrier):
		if max_targets > 0 and caught >= max_targets:
			break
		# Never re-light something already burning: that would let one death
		# refresh an entire screen and make the status effectively permanent.
		if neighbour.statuses.has(status_id):
			continue
		neighbour.apply_status(self, applier, 1)
		caught += 1

func describe(inst: EffectInstance) -> String:
	return "spreads to %d nearby on death (x%d)" % [max_targets, inst.stacks]
