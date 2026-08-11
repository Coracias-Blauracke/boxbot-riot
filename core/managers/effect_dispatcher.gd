class_name EffectDispatcher
extends RefCounted

## LOCAL dispatcher - every entity owns one and only fans out to its own effects.
##
## The alternative (one global bus for everything) loses on two counts: every
## effect would have to open with boilerplate asking "does this event concern
## me?", and with 200 enemies on screen every poison application would wake up
## every listener in the game. The global EventBus stays, but only for events
## that genuinely belong to the whole run.
##
## NOTE on reference cycles: the dispatcher deliberately does NOT keep a
## reference to its owner - `host` arrives as a call argument instead. Godot's
## RefCounted has no cycle collector, so mutual references would never be freed.

var _by_hook: Dictionary = {}                      # Hook -> Array[EffectInstance]
var _instances: Array[EffectInstance] = []

func register(instance: EffectInstance) -> void:
	if instance == null or instance.effect == null:
		push_warning("EffectDispatcher.register: empty instance or effect")
		return

	_instances.append(instance)
	for hook in instance.effect.get_hooks():
		if not _by_hook.has(hook):
			_by_hook[hook] = []
		(_by_hook[hook] as Array).append(instance)
		_sort_hook(hook)

func unregister(instance: EffectInstance) -> void:
	_instances.erase(instance)
	for hook in _by_hook:
		(_by_hook[hook] as Array).erase(instance)

## Drops every effect that came from a given source (sold item, swapped
## character, expired status).
func unregister_source(source: Variant) -> void:
	for instance in _instances.duplicate():
		if instance.source == source:
			unregister(instance)

func find_by_source(source: Variant) -> Array[EffectInstance]:
	var found: Array[EffectInstance] = []
	for instance in _instances:
		if instance.source == source:
			found.append(instance)
	return found

## Called by EntityModel. Returns the same payload so callers can write
## `var event := host.pipeline(HOOK, DamageEvent.new())`.
func dispatch(host: EntityModel, hook: Hooks.Hook, event: EventPayload) -> EventPayload:
	if not _by_hook.has(hook):
		return event

	for instance in (_by_hook[hook] as Array):
		if event.cancelled:
			break
		instance.effect.execute(host, instance, event)

	return event

## Whether anything at all would run for this hook.
##
## Exists so a CALLER can decide not to build a payload. Everything else in the
## game raises events on occasions - a hit, a death, a purchase - and allocating
## one payload for one occasion is free. ON_TICK is the exception: it fires on a
## schedule, so every enemy on screen would allocate one every frame to hand it
## to nothing at all. Seventy enemies at sixty frames is a lot of garbage to
## produce for the handful that are actually on a timer.
func has_listeners(hook: Hooks.Hook) -> bool:
	return _by_hook.has(hook) and not (_by_hook[hook] as Array).is_empty()

func get_instances() -> Array[EffectInstance]:
	return _instances.duplicate()

## Pipeline order must be deterministic and INDEPENDENT of the order in which
## items were acquired - otherwise two players with the same build get different
## results. Hence an explicit `priority` rather than array order.
func _sort_hook(hook: Hooks.Hook) -> void:
	(_by_hook[hook] as Array).sort_custom(
		func(a: EffectInstance, b: EffectInstance) -> bool:
			return a.effect.priority < b.effect.priority
	)
