class_name StatsManager
extends RefCounted

## Stat calculator. Holds TWO representations of the same data:
##  - `_pools`   : aggregated sums, so that get_stat() stays O(1),
##  - `_records` : individual modifiers with their SOURCE remembered.
##
## Tracking the source is required, not cosmetic: without it there is no way to
## remove exactly what an expiring status or a sold item contributed. Two
## overlapping slows of different strength and different duration would drift
## the pools apart irreversibly.

signal stat_changed(stat: StatTypes.Stat)

class ModifierRecord:
	var stat: StatTypes.Stat
	var mod_type: StatTypes.Modifier
	var value: float
	var source: Variant

	func _init(p_stat: StatTypes.Stat, p_mod_type: StatTypes.Modifier, p_value: float, p_source: Variant) -> void:
		stat = p_stat
		mod_type = p_mod_type
		value = p_value
		source = p_source

var _pools: Dictionary = {}
var _mult_handles: Dictionary = {}  # stat -> Array[int], handles of MULT modifiers
var _records: Dictionary = {}       # handle:int -> ModifierRecord
var _by_source: Dictionary = {}     # source:Variant -> Array[int]
var _next_handle: int = 1

func _init() -> void:
	for stat in StatTypes.Stat.values():
		_pools[stat] = {
			StatTypes.Modifier.BASE: 0.0,
			StatTypes.Modifier.FLAT: 0.0,
			StatTypes.Modifier.PERCENT: 0.0,
			# Neutral element of multiplication, not of addition.
			StatTypes.Modifier.MULT: 1.0,
		}
		_mult_handles[stat] = []

## Returns a handle that removes exactly this one modifier.
func add_modifier(stat: StatTypes.Stat, mod_type: StatTypes.Modifier, value: float, source: Variant = null) -> int:
	var handle := _next_handle
	_next_handle += 1

	_records[handle] = ModifierRecord.new(stat, mod_type, value, source)

	if mod_type == StatTypes.Modifier.MULT:
		(_mult_handles[stat] as Array).append(handle)
		_recompute_mult(stat)
	else:
		_pools[stat][mod_type] += value

	if source != null:
		if not _by_source.has(source):
			_by_source[source] = []
		_by_source[source].append(handle)

	stat_changed.emit(stat)
	return handle

func remove_modifier(handle: int) -> void:
	var record: ModifierRecord = _records.get(handle)
	if record == null:
		return

	_records.erase(handle)

	if record.mod_type == StatTypes.Modifier.MULT:
		(_mult_handles[record.stat] as Array).erase(handle)
		_recompute_mult(record.stat)
	else:
		_pools[record.stat][record.mod_type] -= record.value

	if record.source != null and _by_source.has(record.source):
		(_by_source[record.source] as Array).erase(handle)
		if (_by_source[record.source] as Array).is_empty():
			_by_source.erase(record.source)

	stat_changed.emit(record.stat)

## Removes everything a given source contributed. Used when a status expires
## or a whole item is sold.
func remove_all_from_source(source: Variant) -> void:
	if not _by_source.has(source):
		return
	for handle in (_by_source[source] as Array).duplicate():
		remove_modifier(handle)

func get_stat(stat: StatTypes.Stat) -> float:
	var pool: Dictionary = _pools[stat]
	var value: float = (
		(pool[StatTypes.Modifier.BASE] + pool[StatTypes.Modifier.FLAT])
		* (1.0 + pool[StatTypes.Modifier.PERCENT])
		* pool[StatTypes.Modifier.MULT]
	)
	if StatTypes.FLOORS.has(stat):
		value = maxf(value, StatTypes.FLOORS[stat])
	# Capped HERE rather than where the stat is used, so every reader sees the
	# same number - including the stat sheet, which would otherwise keep
	# counting up while the game had stopped listening.
	if StatTypes.CAPS.has(stat):
		value = minf(value, StatTypes.CAPS[stat])
	return value

func has_source(source: Variant) -> bool:
	return _by_source.has(source)

## Raw pools - for UI showing a breakdown, and for tests.
func get_pool_breakdown(stat: StatTypes.Stat) -> Dictionary:
	return (_pools[stat] as Dictionary).duplicate()

## MULT composes multiplicatively, so it cannot be maintained by adding and
## subtracting like the other pools - removal would need division, which drifts
## and blows up on a zero factor. Recomputing the product from the records is
## exact, and the list per stat is tiny.
func _recompute_mult(stat: StatTypes.Stat) -> void:
	var product := 1.0
	for handle in (_mult_handles[stat] as Array):
		product *= (_records[handle] as ModifierRecord).value
	_pools[stat][StatTypes.Modifier.MULT] = product
