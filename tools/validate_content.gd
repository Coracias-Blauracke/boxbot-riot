extends SceneTree

## Content file validator:
##   godot --headless --path . --script res://tools/validate_content.gd
##
## At the target scale (hundreds of .tres files) Godot will NOT complain when a
## file points at a deleted effect or carries a stat outside the enum - it just
## loads null and something quietly fails to work halfway through a wave.
## This catches that in a second, before it ever reaches the game.

const CONTENT_ROOT := "res://content"

var _errors: Array[String] = []
var _warnings: Array[String] = []
var _checked: int = 0

func _initialize() -> void:
	print("=== CONTENT VALIDATION ===\n")

	for path in _collect_resources(CONTENT_ROOT):
		_validate(path)

	for warning in _warnings:
		print("  WARN   %s" % warning)
	for error in _errors:
		printerr("  ERROR  %s" % error)

	print("\nChecked %d files: %d errors, %d warnings" % [_checked, _errors.size(), _warnings.size()])
	quit(1 if not _errors.is_empty() else 0)

func _collect_resources(dir_path: String) -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			found.append_array(_collect_resources(full))
		elif entry.ends_with(".tres"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return found

func _validate(path: String) -> void:
	_checked += 1
	var resource := load(path)
	if resource == null:
		_errors.append("%s : cannot be loaded" % path)
		return

	if resource is ItemData:
		_validate_item(path, resource)
	elif resource is WaveTable:
		_validate_wave_table(path, resource)
	elif resource is EntityData:
		_validate_entity(path, resource)
	else:
		_warnings.append("%s : unrecognised resource type (%s)" % [path, resource.get_class()])

func _validate_wave_table(path: String, table: WaveTable) -> void:
	if table.entries.is_empty():
		_errors.append("%s : wave table has no entries" % path)
	if table.base_duration <= 0.0:
		_errors.append("%s : base_duration must be positive" % path)
	if table.spawn_events <= 0:
		_errors.append("%s : spawn_events must be positive" % path)

	var reachable_at_one := false
	for i in table.entries.size():
		var entry: WaveEntry = table.entries[i]
		if entry == null:
			_errors.append("%s : entry[%d] is null" % [path, i])
			continue
		if entry.enemy == null:
			_errors.append("%s : entry[%d] has no enemy (deleted resource?)" % [path, i])
			continue
		if entry.weight <= 0.0:
			_errors.append("%s : entry[%d] has non-positive weight, it can never be drawn" % [path, i])
		if entry.cost <= 0.0:
			_errors.append("%s : entry[%d] has non-positive cost, it would spawn forever" % [path, i])
		if entry.max_wave > 0 and entry.max_wave < entry.min_wave:
			_errors.append("%s : entry[%d] has max_wave below min_wave, it never appears" % [path, i])
		if entry.is_available(1):
			reachable_at_one = true

	# A table with nothing available on wave one produces an empty first wave.
	if not reachable_at_one and not table.entries.is_empty():
		_errors.append("%s : no entry is available on wave 1" % path)

func _validate_item(path: String, item: ItemData) -> void:
	if item.display_key.is_empty():
		_errors.append("%s : empty display_key (translation key)" % path)
	if item.tier < 1 or item.tier > 4:
		_errors.append("%s : tier out of range 1-4 (%d)" % [path, item.tier])
	if item.static_stats.is_empty() and item.dynamic_effects.is_empty():
		_warnings.append("%s : item has no effect at all" % path)

	_validate_modifiers(path, item.static_stats)
	_validate_effects(path, item.dynamic_effects)

func _validate_entity(path: String, entity: EntityData) -> void:
	if entity.display_key.is_empty():
		_errors.append("%s : empty display_key (translation key)" % path)
	if entity.collider_radius <= 0.0:
		_errors.append("%s : collider_radius must be positive" % path)

	_validate_modifiers(path, entity.base_stats)
	_validate_effects(path, entity.innate_effects)

func _validate_modifiers(path: String, modifiers: Array) -> void:
	var valid_stats := StatTypes.Stat.values()
	var valid_types := StatTypes.Modifier.values()

	for i in modifiers.size():
		var modifier: StatModifier = modifiers[i]
		if modifier == null:
			_errors.append("%s : modifier[%d] is null (deleted resource?)" % [path, i])
			continue
		if not valid_stats.has(modifier.stat):
			_errors.append("%s : modifier[%d] has a stat outside the enum (%d)" % [path, i, modifier.stat])
		if not valid_types.has(modifier.modifier_type):
			_errors.append("%s : modifier[%d] has an unknown modifier type (%d)" % [path, i, modifier.modifier_type])
		if is_zero_approx(modifier.value):
			_warnings.append("%s : modifier[%d] has value 0 (mistake?)" % [path, i])

func _validate_effects(path: String, effects: Array) -> void:
	for i in effects.size():
		var effect: DynamicEffect = effects[i]
		if effect == null:
			_errors.append("%s : effect[%d] is null (deleted effect script?)" % [path, i])
			continue

		var hooks: Array = effect.get_hooks()
		if hooks.is_empty():
			_errors.append("%s : effect[%d] declares no hooks" % [path, i])
		for hook in hooks:
			if not Hooks.KINDS.has(hook):
				_errors.append("%s : effect[%d] declares an unknown hook (%d)" % [path, i, hook])
