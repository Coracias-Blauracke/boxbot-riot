class_name EffectBlast
extends DynamicEffect

## GENERIC: "something explodes when X happens".
##
## The WHEN is authored and the WHAT is a separate resource, so one class covers
## three families that would otherwise have been three:
##
##   ON_DEATH   a bug that bursts when it dies              (Popper)
##   ON_KILL    everything you kill explodes                (an item)
##   ON_IMPACT  this projectile goes off where it lands     (a grenade)
##
## Nothing about those differs except where the centre is, and the centre is
## always the same rule stated once: WHERE THE EVENT HAPPENED. The impact point,
## the victim, or the holder itself when the event names no place of its own.
##
## The trigger is exported, which DynamicEffect allows for exactly this case -
## an effect whose hooks are configuration rather than a property of its code.
## The blast cannot be wired to a hook it would not understand, because the enum
## is the only thing that can be authored and every value of it is handled.

enum Trigger {
	ON_DEATH,
	ON_KILL,
	ON_IMPACT,
}

@export var blast: BlastData

@export var trigger: Trigger = Trigger.ON_DEATH

const HOOK_FOR: Dictionary = {
	Trigger.ON_DEATH: Hooks.Hook.ON_DEATH,
	Trigger.ON_KILL: Hooks.Hook.ON_KILL,
	Trigger.ON_IMPACT: Hooks.Hook.ON_IMPACT,
}

func get_hooks() -> Array:
	var hook: Hooks.Hook = HOOK_FOR[trigger]
	return [hook]

func execute(host: Variant, inst: EffectInstance, event: EventPayload) -> void:
	var owner_model := host as EntityModel
	if owner_model == null or blast == null:
		return

	# Branched on the authored TRIGGER rather than on what the payload turns out
	# to be. Reading the type would make the behaviour depend on what some other
	# system happens to pass, which is a coupling that holds right up until two
	# hooks share a payload class - and ON_KILL and ON_DAMAGE_DEALT already do.
	#
	# A kill fires on the KILLER and an impact on the SHOOTER, so the host is the
	# right owner of the explosion in every case: for kill credit, for whose
	# stats decide the damage, and for whose Actor draws it.
	var power := float(inst.stacks)

	match trigger:
		Trigger.ON_IMPACT:
			var impact := event as ImpactEvent
			if impact == null:
				return
			var shot := impact.snapshot
			var fired_by: WeaponModel = null
			if shot != null:
				fired_by = shot.weapon as WeaponModel
			owner_model.detonate(blast, impact.position, fired_by, shot, power)

		Trigger.ON_KILL:
			var kill := event as DamageEvent
			if kill == null or kill.target == null:
				return
			# Deliberately NOT inheriting the killing blow's crit: this explosion
			# is a consequence of the kill rather than part of the shot that
			# caused it, so it rolls its own. The impact case above is the
			# opposite, and the difference is whether one attack happened or two.
			owner_model.detonate(blast, kill.target.world_position, null, null, power)

		_:
			# ON_DEATH carries a bare payload, because a death has nothing to say
			# beyond having happened. The place is the holder's own - written by
			# its Actor, and still correct on a corpse.
			owner_model.detonate(blast, owner_model.world_position, null, null, power)

func describe(inst: EffectInstance) -> String:
	if blast == null:
		return ""

	var occasion := "on death"
	match trigger:
		Trigger.ON_KILL:
			occasion = "on every kill"
		Trigger.ON_IMPACT:
			occasion = "where its shots land"

	return "explodes %s for %s (x%d)" % [occasion, blast.describe(), inst.stacks]
