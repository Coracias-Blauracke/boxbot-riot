class_name StatusManager
extends RefCounted

## Statuses currently sitting on one entity, keyed by status_id.
##
## Like every other manager it holds no reference back to its owner - `host`
## arrives as a call argument.

signal status_applied(status_id: StringName, stacks: int)
signal status_removed(status_id: StringName)

var _active: Dictionary = {}  # StringName -> ActiveStatus

## Returns the ActiveStatus if the status landed, null if it was resisted,
## cancelled by a pipeline effect, or lost the chance roll.
func apply(
	host: EntityModel,
	definition: StatusEffect,
	applier: EntityModel = null,
	stacks: int = 1,
	duration: float = -1.0,
	chance: float = -1.0
) -> ActiveStatus:
	if definition == null or definition.status_id.is_empty():
		push_warning("StatusManager.apply: status has no status_id")
		return null

	var event := StatusEvent.new()
	event.applier = applier
	event.target = host
	event.definition = definition
	event.status_id = definition.status_id
	event.stacks = stacks
	event.duration = definition.base_duration if duration < 0.0 else duration

	# The BASE chance belongs to the application site, not to the status. A
	# weapon hit that may cause bleeding rolls for it; fire spreading off a
	# corpse is deliberate and always lands. Defaulting to 1.0 here and letting
	# items only subtract made "+10% chance to bleed" mean "always, minus 10".
	if chance >= 0.0:
		event.chance = chance

	# The applier's stats decide how likely this is to land and how long it
	# lasts, BEFORE any pipeline effect gets to argue about it.
	event.chance += definition.bonus_for(StatusScaling.Axis.CHANCE, applier)
	event.duration += definition.bonus_for(StatusScaling.Axis.DURATION, applier)

	# Offence first, then defence - the same two-phase shape as damage.
	if applier != null:
		applier.pipeline(Hooks.Hook.CALCULATE_STATUS, event)
	if not event.cancelled:
		host.pipeline(Hooks.Hook.CALCULATE_STATUS, event)

	if event.cancelled or event.stacks <= 0:
		return null
	# Rolled on the run-wide seeded generator, not randf(), so a run replays
	# identically from its seed and the roll is testable.
	if not host.rng.chance(RunRandom.Stream.COMBAT, event.chance):
		return null

	# Typed explicitly: a Dictionary lookup is Variant and `:=` off one is a
	# parse error that takes the whole file with it.
	var existing_before: ActiveStatus = _active.get(event.status_id)
	var status := _land(host, event)

	event.applied = true
	host.notify(Hooks.Hook.ON_STATUS_RECEIVED, event)
	if applier != null:
		applier.notify(Hooks.Hook.ON_STATUS_APPLIED, event)
	host.counters.add(CounterTypes.Counter.STATUS_APPLIED)
	# Tallied on the APPLIER and only for a FRESH target: refreshing a status
	# already running must not count as poisoning somebody new.
	if applier != null and existing_before == null:
		applier.counters.add(definition.apply_counter)

	status_applied.emit(event.status_id, status.stacks)
	return status

func has(status_id: StringName) -> bool:
	return _active.has(status_id)

func get_stacks(status_id: StringName) -> int:
	var status: ActiveStatus = _active.get(status_id)
	return status.stacks if status != null else 0

func get_active(status_id: StringName) -> ActiveStatus:
	return _active.get(status_id)

func get_all() -> Array[ActiveStatus]:
	var result: Array[ActiveStatus] = []
	for status_id in _active:
		result.append(_active[status_id])
	return result

func remove(host: EntityModel, status_id: StringName) -> void:
	var status: ActiveStatus = _active.get(status_id)
	if status == null:
		return
	_expire(host, status)

func clear_all(host: EntityModel) -> void:
	for status_id in _active.keys():
		_expire(host, _active[status_id])

## Advances every active status. Called once per frame by the entity's view,
## or directly by tests.
func tick(host: EntityModel, delta: float) -> void:
	for status in get_all():
		var definition := status.definition()

		# The RESOLVED interval, not the authored one - that is what makes
		# "bleed ticks 10% faster" a per-player property rather than a global
		# edit to a shared resource.
		if status.tick_interval > 0.0:
			status.tick_accumulator += delta
			while status.tick_accumulator >= status.tick_interval:
				status.tick_accumulator -= status.tick_interval
				definition.on_tick(host, status)
				host.notify(Hooks.Hook.ON_STATUS_TICK, _describe(host, status))

		status.remaining -= delta
		if status.remaining <= 0.0:
			_expire(host, status)

# --- internals -------------------------------------------------------------

func _land(host: EntityModel, event: StatusEvent) -> ActiveStatus:
	var existing: ActiveStatus = _active.get(event.status_id)

	if existing != null:
		# Re-resolved on every application, not only the first. The applier's
		# stats may have moved since, and the newest application is the one that
		# should decide how the status behaves from here.
		event.definition.resolve_onto(existing, event.applier)
		existing.stacks = mini(existing.stacks + event.stacks, existing.max_stacks)
		match event.definition.refresh_mode:
			StatusEffect.RefreshMode.REFRESH:
				existing.remaining = event.duration
			StatusEffect.RefreshMode.EXTEND:
				existing.remaining += event.duration
			StatusEffect.RefreshMode.KEEP:
				pass
		existing.set_applier(event.applier)
		# on_applied must be idempotent - it reruns so stack-scaled modifiers
		# can recompute themselves.
		event.definition.on_applied(host, existing)
		return existing

	var status := ActiveStatus.new(event.definition, event.definition, 1)
	# Resolve first: the cap the stacks are clamped to is the RESOLVED one, so
	# "+1 additional bleed stack" works on the very application that grants it.
	event.definition.resolve_onto(status, event.applier)
	status.stacks = mini(event.stacks, status.max_stacks)
	status.remaining = event.duration
	status.set_applier(event.applier)

	_active[event.status_id] = status
	host.effects.register(status)
	event.definition.on_applied(host, status)
	return status

func _expire(host: EntityModel, status: ActiveStatus) -> void:
	var definition := status.definition()
	definition.on_expired(host, status)

	# The payoff of source tracking: this removes exactly what the status
	# contributed, leaving any other slow or buff on the same stat untouched.
	host.stats.remove_all_from_source(status)
	host.effects.unregister(status)
	_active.erase(definition.status_id)

	host.notify(Hooks.Hook.ON_STATUS_EXPIRED, _describe(host, status))
	status_removed.emit(definition.status_id)

func _describe(host: EntityModel, status: ActiveStatus) -> StatusEvent:
	var event := StatusEvent.new()
	event.target = host
	event.applier = status.get_applier()
	event.definition = status.definition()
	event.status_id = event.definition.status_id
	event.stacks = status.stacks
	event.duration = status.remaining
	event.applied = true
	return event
