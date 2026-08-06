class_name EffectDamageVersusStatus
extends DynamicEffect

## GENERIC: "+10% damage to burning enemies", "+10% damage to anything carrying
## two or more statuses".
##
## Hooks ON_OUTGOING_DAMAGE rather than CALCULATE_DAMAGE, because it has to see
## WHO is being hit and CALCULATE_DAMAGE fires once per shot before any target
## exists. That distinction is what lets one shotgun blast roll crit once and
## still check each pellet's victim separately here.

## Empty means "match on the count instead", using minimum_status_count.
@export var status_id: StringName = &""

## Matches a target carrying at least this many statuses of any kind. Ignored
## when status_id is set.
@export var minimum_status_count: int = 0

@export_group("Reward")
## Fraction added to the damage. 0.1 is +10%.
@export var bonus: float = 0.1

func get_hooks() -> Array:
	return [Hooks.Hook.ON_OUTGOING_DAMAGE]

func execute(_host: Variant, inst: EffectInstance, event: EventPayload) -> void:
	var damage := event as DamageEvent
	if damage == null or damage.target == null:
		return

	var matches := (
		damage.target.statuses.get_all().size() >= minimum_status_count
		if status_id.is_empty()
		else damage.target.statuses.has(status_id)
	)
	if not matches:
		return

	damage.amount *= 1.0 + bonus * float(inst.stacks)

func describe(inst: EffectInstance) -> String:
	var subject := (
		"targets with %d+ statuses" % minimum_status_count
		if status_id.is_empty()
		else "%s targets" % status_id
	)
	return "+%d%% damage to %s (x%d)" % [roundi(bonus * 100.0), subject, inst.stacks]
