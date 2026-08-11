class_name ItemsManager
extends RefCounted

## Inventory of passive items.
##
## DELIBERATELY keeps no reference to its owner - `host` arrives as an argument.
## The previous version had PlayerModel -> ItemsManager -> PlayerModel, a
## reference cycle; Godot's RefCounted has no cycle collector, so neither object
## was ever freed (confirmed by leaked instances reported at shutdown).
##
## It also subscribes to nothing global. Wave events are fanned out by the run
## controller via host.notify(), so two player models (for example a shop
## preview) can never trigger each other's effects.

var _quantities: Dictionary = {}   # ItemData -> int
var _handles: Dictionary = {}      # ItemData -> Array[Array[int]] (handles per copy)
var _instances: Dictionary = {}    # ItemData -> Array[EffectInstance]

func add_item(host: EntityModel, item: ItemData, quantity: int = 1) -> void:
	if item == null or quantity <= 0:
		return

	_quantities[item] = _quantities.get(item, 0) + quantity

	# Each copy gets its own set of handles so that selling ONE unit removes
	# exactly that unit's modifiers rather than the whole stack.
	if not _handles.has(item):
		_handles[item] = []
	for _i in quantity:
		var copy_handles: Array[int] = []
		for modifier in item.static_stats:
			if modifier == null:
				continue
			copy_handles.append(
				host.stats.add_modifier(modifier.stat, modifier.modifier_type, modifier.value, item)
			)
		(_handles[item] as Array).append(copy_handles)

	_sync_effects(host, item)

func remove_item(host: EntityModel, item: ItemData, quantity: int = 1) -> void:
	if not _quantities.has(item) or quantity <= 0:
		return

	var actual: int = mini(_quantities[item], quantity)
	_quantities[item] -= actual

	for _i in actual:
		var copy_handles: Array = (_handles[item] as Array).pop_back()
		for handle in copy_handles:
			host.stats.remove_modifier(handle)

	if _quantities[item] <= 0:
		_quantities.erase(item)
		_handles.erase(item)
		_clear_effects(host, item)
	else:
		_sync_effects(host, item)

func get_quantity(item: ItemData) -> int:
	return _quantities.get(item, 0)

func get_all() -> Dictionary:
	return _quantities.duplicate()

## For effects such as "gain +X for every tier 4 item you own".
func count_by_tier(tier: int) -> int:
	var total := 0
	for item in _quantities:
		if (item as ItemData).tier == tier:
			total += _quantities[item]
	return total

# --- dynamic effects -------------------------------------------------------

## One EffectInstance per (item, effect), with the owned count living in
## `stacks`. Each effect decides for itself how it scales with the stack.
func _sync_effects(host: EntityModel, item: ItemData) -> void:
	var quantity: int = _quantities[item]

	if not _instances.has(item):
		var created: Array[EffectInstance] = []
		for effect in item.dynamic_effects:
			if effect == null:
				continue
			var instance := EffectInstance.new(effect, item, quantity)
			host.effects.register(instance)
			created.append(instance)
		_instances[item] = created
		return

	for instance in (_instances[item] as Array):
		(instance as EffectInstance).stacks = quantity

func _clear_effects(host: EntityModel, item: ItemData) -> void:
	if not _instances.has(item):
		return
	# Effects may have added modifiers of their own with the instance as source
	# (e.g. "+1% per 1000 bullets fired"). Clean those up along with the effect.
	for instance in (_instances[item] as Array):
		host.stats.remove_all_from_source(instance)
	host.effects.unregister_source(item)
	_instances.erase(item)
