class_name EffectStatPerWorldCount
extends DynamicEffect

## GENERIC: "gain X to a stat for every enemy that currently has <status>".
##
## The count is LIVE - it rises as things catch fire and falls as they die or
## the fire goes out - so unlike EffectStatPerCounter this cannot key off a
## monotonic tally. It recomputes on ON_TICK.
##
## Recomputing every frame is affordable only because WorldCensus caches per
## generation: ten items asking the same question in one frame pay for one walk.
## Without that this would be O(items x entities) every frame.

## Empty counts every living entity instead of filtering by status.
@export var status_id: StringName = &""

## When set, counts entities carrying at least this many statuses of any kind,
## and status_id is ignored.
@export var minimum_status_count: int = 0

@export_group("Reward")
@export var stat: StatTypes.Stat = StatTypes.Stat.ATTACK_SPEED
@export var modifier_type: StatTypes.Modifier = StatTypes.Modifier.PERCENT
@export var value_per_target: float = 0.01

func get_hooks() -> Array:
	return [Hooks.Hook.ON_TICK]

func execute(host: Variant, inst: EffectInstance, event: EventPayload) -> void:
	var tick := event as TickEvent
	if tick == null or tick.census == null:
		return

	var count := (
		tick.census.count_with_at_least(minimum_status_count)
		if minimum_status_count > 0
		else tick.census.count_with_status(status_id)
	)

	# Idempotent, exactly like EffectStatPerCounter: strip this effect's whole
	# contribution and reapply it. Nothing accumulates, and a missed frame or a
	# count that goes DOWN both self-correct on the next tick.
	if count == inst.get_state(&"applied", -1):
		return

	host.stats.remove_all_from_source(inst)
	if count > 0:
		host.stats.add_modifier(
			stat, modifier_type, value_per_target * float(count) * float(inst.stacks), inst
		)
	inst.set_state(&"applied", count)

func describe(inst: EffectInstance) -> String:
	var subject := (
		"enemy with %d+ statuses" % minimum_status_count
		if minimum_status_count > 0
		else "%s enemy" % status_id
	)
	return "+%s per %s (x%d)" % [str(value_per_target), subject, inst.stacks]
