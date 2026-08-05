class_name ActiveStatus
extends EffectInstance

## One status currently sitting on one entity.
##
## Extends EffectInstance on purpose: a status IS an effect with a lifetime, so
## it registers with the EffectDispatcher like any other. That is what lets
## "while bleeding you take +20% damage" hook TAKE_DAMAGE with no extra
## machinery - the status participates in pipelines exactly like an item effect.
##
## It also doubles as the modifier SOURCE, so expiry removes precisely what this
## status contributed and nothing else.

var remaining: float = 0.0
var tick_accumulator: float = 0.0

## RESOLVED FROM THE APPLIER when the status landed, never read live from the
## definition. The .tres is globally cached and shared by every holder, so a
## per-player value cannot live there - and the applier may die long before the
## poison wears off. Same reasoning as rolling crit once per shot.
var max_stacks: int = 99
var tick_interval: float = 0.0
var tick_damage: float = 0.0

## Weak on purpose. Two enemies poisoning each other would otherwise form a
## reference cycle, and RefCounted has no cycle collector. The applier may also
## legitimately die before the status expires.
var _applier_ref: WeakRef = null

func set_applier(applier: EntityModel) -> void:
	_applier_ref = weakref(applier) if applier != null else null

func get_applier() -> EntityModel:
	if _applier_ref == null:
		return null
	return _applier_ref.get_ref() as EntityModel

func definition() -> StatusEffect:
	return effect as StatusEffect
