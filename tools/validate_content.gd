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

	_validate_tags_name_real_classes()
	_validate_characters_are_reachable()
	_validate_keys_are_translated()
	_validate_source_is_english()

	for warning in _warnings:
		print("  WARN   %s" % warning)
	for error in _errors:
		printerr("  ERROR  %s" % error)

	print("\nChecked %d files: %d errors, %d warnings" % [_checked, _errors.size(), _warnings.size()])
	quit(1 if not _errors.is_empty() else 0)

## CLAUDE.md's first rule is that everything in the codebase is in English while
## the conversation around it is in Polish, and that rule was broken by eight UI
## strings before anybody noticed.
##
## PARTIAL on purpose, and worth being honest about: it catches non-ASCII, which
## means it finds any Polish word carrying a diacritic and misses one that does
## not. A word blacklist would be the other half and would go stale the day
## somebody writes a new word. Half a guard on an explicit rule still beats
## none, because the accented half is also the half that breaks fonts and
## encodings.
##
## Note it necessarily applies to this file too: an example of a bad string
## written out here would fail the check it describes.
const SOURCE_ROOTS: PackedStringArray = ["res://core", "res://scenes", "res://tools", "res://tests"]

func _validate_source_is_english() -> void:
	for root in SOURCE_ROOTS:
		for path in _collect_scripts(root):
			var text := FileAccess.get_file_as_string(path)
			for index in text.length():
				var code := text.unicode_at(index)
				if code > 127:
					_errors.append(
						"%s : non-ASCII character '%s' - the codebase is English"
						% [path, char(code)]
					)
					break

func _collect_scripts(dir_path: String) -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			found.append_array(_collect_scripts(full))
		elif entry.ends_with(".gd"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return found

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

	# Read GENERICALLY rather than per type. Every player-facing string in
	# content/ is a translation key on some resource, and chasing them type by
	# type means the next content type quietly opts out of being checked.
	for field in ["display_key", "description_key"]:
		var value: Variant = resource.get(field)
		if value is String and not (value as String).is_empty():
			_used_keys[value as String] = path

	if resource is ItemData:
		_validate_item(path, resource)
	elif resource is WaveTable:
		_validate_wave_table(path, resource)
	elif resource is StatSheet:
		_validate_stat_sheet(path, resource)
	elif resource is StatMetadata:
		_validate_stat_metadata(path, resource)
	elif resource is StatusEffect:
		_validate_status(path, resource)
	elif resource is ShopData:
		_validate_shop(path, resource)
	elif resource is WaveModifier:
		_validate_wave_modifier(path, resource)
	elif resource is SpawnPattern:
		_validate_spawn_pattern(path, resource)
	elif resource is WeaponData:
		_validate_weapon(path, resource)
	elif resource is WeaponClassData:
		_validate_weapon_class(path, resource)
	elif resource is WeaponClassSet:
		_validate_weapon_class_set(path, resource)
	elif resource is CharacterSet:
		_validate_character_set(path, resource)
	elif resource is PickupData:
		_validate_pickup(path, resource)
	elif resource is CharacterData:
		_validate_character(path, resource)
	elif resource is EntityData:
		_validate_entity(path, resource)
	else:
		_warnings.append("%s : unrecognised resource type (%s)" % [path, resource.get_class()])

## Catches weapons that load fine and then silently do nothing - the delivery
## kind and its payload have to agree.
func _validate_weapon(path: String, weapon: WeaponData) -> void:
	_validate_entity(path, weapon)

	_validate_upgrade_chain(path, weapon)

	for tag in weapon.tags:
		if tag == &"":
			_errors.append("%s : has an empty tag" % path)
			continue
		if not _used_tags.has(tag):
			_used_tags[tag] = []
		(_used_tags[tag] as Array).append(path)

	# A null entry in either table is silently skipped at runtime, so a deleted
	# resource turns into a weapon that quietly stops caring about a stat.
	var valid_stats := StatTypes.Stat.values()
	for i in weapon.damage_scaling.size():
		var scaling: StatScaling = weapon.damage_scaling[i]
		if scaling == null:
			_errors.append("%s : damage_scaling[%d] is null (deleted resource?)" % [path, i])
		elif not valid_stats.has(scaling.stat):
			_errors.append("%s : damage_scaling[%d] names a stat outside the enum" % [path, i])

	for i in weapon.stat_inheritance.size():
		var scaling: StatScaling = weapon.stat_inheritance[i]
		if scaling == null:
			_errors.append("%s : stat_inheritance[%d] is null (deleted resource?)" % [path, i])
		elif not valid_stats.has(scaling.stat):
			_errors.append("%s : stat_inheritance[%d] names a stat outside the enum" % [path, i])

	# Withholding a MULTIPLICATIVE stat is expressed as a share of the holder's
	# deviation from neutral, so a share is a proportion. Above 1 it amplifies,
	# which is legal; below 0 on a multiplier inverts the holder's bonus into a
	# penalty, which is almost certainly a typo rather than a design.
	for scaling in weapon.stat_inheritance:
		if scaling != null and scaling.coefficient < 0.0 and StatTypes.is_multiplicative(scaling.stat):
			_warnings.append(
				"%s : inherits a NEGATIVE share of %s, so its holder's bonus becomes a penalty"
				% [path, StatTypes.Stat.keys()[scaling.stat]]
			)

	if weapon.firing == null:
		_errors.append("%s : weapon has no firing pattern, it will never attack" % path)
	if weapon.targeting == null:
		_errors.append("%s : weapon has no target selector, it will never find anything" % path)

	match weapon.delivery:
		WeaponData.DeliveryKind.PROJECTILE:
			if weapon.projectile == null:
				_errors.append("%s : PROJECTILE delivery with no projectile data" % path)
			if not weapon.melee_combo.is_empty():
				_warnings.append("%s : melee_combo set on a projectile weapon, it is ignored" % path)
		WeaponData.DeliveryKind.MELEE_SWEEP:
			if weapon.melee_combo.is_empty():
				_errors.append("%s : MELEE_SWEEP delivery with an empty melee_combo" % path)
			for i in weapon.melee_combo.size():
				var swing: SwingPattern = weapon.melee_combo[i]
				if swing == null:
					_errors.append("%s : melee_combo[%d] is null" % [path, i])
				elif swing.duration <= 0.0:
					_errors.append("%s : melee_combo[%d] has non-positive duration" % [path, i])
				elif swing.reach <= 0.0:
					_errors.append("%s : melee_combo[%d] has no reach, it can never connect" % [path, i])
		_:
			# BEAM and SUMMON are enum values with no code behind them. Caught
			# HERE rather than left to the runtime guard, because the runtime
			# symptom is a weapon that loads, prices, sells, sits in the hands
			# and never fires - which reads as a mistake in the author's own
			# file. The enum value existing is what makes it look supported.
			_errors.append(
				"%s : delivery kind %d has no implementation, this weapon can never attack"
				% [path, weapon.delivery]
			)

func _validate_wave_table(path: String, table: WaveTable) -> void:
	if table.entries.is_empty():
		_errors.append("%s : wave table has no entries" % path)
	if table.base_duration <= 0.0:
		_errors.append("%s : base_duration must be positive" % path)
	if table.spawn_events <= 0:
		_errors.append("%s : spawn_events must be positive" % path)
	if table.total_waves <= 0:
		_errors.append("%s : total_waves must be positive, the run would end at once" % path)

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

	# Placement is the failure that says nothing at all: with no pattern
	# anywhere the wave runs its full length and not one enemy appears.
	if table.default_pattern == null:
		var all_entries_placed := true
		for entry in table.entries:
			if entry != null and entry.pattern == null:
				all_entries_placed = false
		if not all_entries_placed:
			_errors.append("%s : no default_pattern and some entries have none either" % path)

	if table.budget_per_extra_player < 0.0 or table.events_per_extra_player < 0.0:
		_errors.append("%s : co-op scaling cannot be negative" % path)

	for i in table.modifiers.size():
		if table.modifiers[i] == null:
			_errors.append("%s : modifier[%d] is null (deleted resource?)" % [path, i])

## A modifier that matches no wave is dead content, and one that multiplies by
## zero produces an empty wave without erroring - both silent at runtime.
func _validate_wave_modifier(path: String, modifier: WaveModifier) -> void:
	if modifier.display_key.is_empty():
		_errors.append("%s : empty display_key (translation key)" % path)
	if modifier.waves.is_empty() and modifier.every_n_waves <= 0:
		_errors.append("%s : matches no wave at all" % path)
	if modifier.budget_multiplier <= 0.0:
		_errors.append("%s : budget_multiplier must be positive" % path)
	if modifier.events_multiplier <= 0.0:
		_errors.append("%s : events_multiplier must be positive" % path)
	if modifier.max_entry_cost < 0.0:
		_errors.append("%s : max_entry_cost cannot be negative" % path)
	for wave in modifier.waves:
		if wave <= 0:
			_errors.append("%s : wave numbers start at 1, got %d" % [path, wave])

func _validate_spawn_pattern(path: String, pattern: SpawnPattern) -> void:
	if pattern is SpawnRing:
		# At or below 1.0 the ring sits inside the view and enemies pop into
		# existence on screen, which reads as a bug rather than as difficulty.
		if (pattern as SpawnRing).view_margin <= 1.0:
			_errors.append("%s : view_margin must exceed 1.0 or enemies appear on screen" % path)
	elif pattern is SpawnNearPlayer:
		var ambush := pattern as SpawnNearPlayer
		if ambush.min_distance <= 0.0:
			_errors.append("%s : min_distance must be positive or the group lands on the player" % path)
		if ambush.max_distance < ambush.min_distance:
			_errors.append("%s : max_distance is below min_distance" % path)
	elif pattern is SpawnInView:
		# Spawning inside the frame gives the player no approach to react to, so
		# a missing clearance is the difference between pressure and a coin flip.
		if (pattern as SpawnInView).clear_radius <= 0.0:
			_errors.append("%s : clear_radius must be positive, it spawns ON the players" % path)

func _validate_stat_metadata(path: String, meta: StatMetadata) -> void:
	if not StatTypes.Stat.values().has(meta.stat):
		_errors.append("%s : stat outside the enum (%d)" % [path, meta.stat])
	if meta.display_key.is_empty():
		_errors.append("%s : empty display_key (translation key)" % path)
	# The sheet shows this when the player rests on the row. Blank is a row that
	# explains nothing, which is worse than no row.
	if meta.visible_in_ui and meta.description_key.is_empty():
		_errors.append("%s : visible stat with no description_key" % path)

## THE rule that makes "a new stat shows up on its own" true rather than merely
## possible: every value in the enum has to be in the sheet exactly once. Add a
## stat and forget its metadata and this fails here, rather than the stat
## silently never appearing in the game.
func _validate_stat_sheet(path: String, sheet: StatSheet) -> void:
	var seen: Dictionary = {}

	for i in sheet.entries.size():
		var entry: StatMetadata = sheet.entries[i]
		if entry == null:
			_errors.append("%s : entry[%d] is null (deleted metadata?)" % [path, i])
			continue
		if seen.has(entry.stat):
			_errors.append("%s : stat %d appears twice" % [path, entry.stat])
		seen[entry.stat] = true

	for stat in StatTypes.Stat.values():
		if not seen.has(stat):
			_errors.append(
				"%s : StatTypes.Stat value %d has no metadata, it can never be displayed"
				% [path, stat]
			)

## A status with no id is refused at runtime with a push_warning nobody reads,
## and one whose duration cannot cover a single tick simply never damages
## anything - both silent.
func _validate_status(path: String, status: StatusEffect) -> void:
	if status.status_id.is_empty():
		_errors.append("%s : status_id is empty, StatusManager will refuse it" % path)
	if status.base_duration <= 0.0:
		_errors.append("%s : base_duration must be positive" % path)
	if status.max_stacks < 1:
		_errors.append("%s : max_stacks below 1 means it can never apply" % path)
	if status.tick_interval < 0.0:
		_errors.append("%s : tick_interval cannot be negative" % path)
	# A ticking status lives by its tick COUNT, so that is what has to be
	# positive; base_duration governs only statuses that never tick.
	if status.tick_interval > 0.0 and status.tick_count < 1:
		_errors.append("%s : ticks but has no ticks to give, so it does nothing" % path)

	var valid_stats := StatTypes.Stat.values()
	for i in status.scaling.size():
		var entry: StatusScaling = status.scaling[i]
		if entry == null:
			_errors.append("%s : scaling[%d] is null (deleted resource?)" % [path, i])
			continue
		if not valid_stats.has(entry.stat):
			_errors.append("%s : scaling[%d] names a stat outside the enum" % [path, i])

	if status is StatusSpreadOnDeath and (status as StatusSpreadOnDeath).spread_radius <= 0.0:
		_errors.append("%s : spread_radius must be positive or it spreads nowhere" % path)

func _validate_shop(path: String, shop: ShopData) -> void:
	if shop.pool.is_empty():
		_errors.append("%s : shop pool is empty, it can never offer anything" % path)
	if shop.offer_count <= 0:
		_errors.append("%s : offer_count must be positive" % path)
	if shop.sell_ratio < 0.0:
		_errors.append("%s : sell_ratio cannot be negative" % path)
	# At or above 1.0 an item sells for what it cost, so buy-and-sell is at worst
	# free and the whole economy stops mattering.
	if shop.sell_ratio >= 1.0:
		_errors.append("%s : sell_ratio at or above 1.0 makes selling a free undo" % path)
	if shop.reroll_cost_growth < 1.0:
		_warnings.append("%s : reroll_cost_growth below 1.0 makes rerolling cheaper each time" % path)

	for i in shop.pool.size():
		if shop.pool[i] == null:
			_errors.append("%s : pool[%d] is null (deleted item?)" % [path, i])

	for i in shop.weapon_pool.size():
		if shop.weapon_pool[i] == null:
			_errors.append("%s : weapon_pool[%d] is null (deleted weapon?)" % [path, i])

	# A weapon offered at a price of zero is free, and a shop that gives weapons
	# away is not a shop. Checked here rather than on the weapon, because a
	# weapon that is never sold is entitled to leave its price alone.
	for weapon in shop.weapon_pool:
		if weapon != null and weapon.base_price <= 0:
			_errors.append(
				"%s : '%s' is in the weapon pool with base_price %d"
				% [path, weapon.display_key, weapon.base_price]
			)

	# The mix is authored, so the two ends of the knob have to mean something. A
	# chance above zero with nothing to draw from silently falls back to items
	# and the setting reads as broken rather than as empty.
	if shop.weapon_offer_chance > 0.0 and shop.weapon_pool.is_empty():
		_warnings.append(
			"%s : weapon_offer_chance is %.2f but the weapon pool is empty"
			% [path, shop.weapon_offer_chance]
		)
	if shop.weapon_offer_chance <= 0.0 and not shop.weapon_pool.is_empty():
		_warnings.append(
			"%s : weapon pool has %d entries but weapon_offer_chance is 0, none can appear"
			% [path, shop.weapon_pool.size()]
		)

	# A tier with content but no weight can never be drawn - it loads fine,
	# validates fine, and is simply never seen. Weapons roll on the same curve,
	# so a tier 3 weapon in a run whose tier 3 weight is always zero is exactly
	# the same silent hole.
	var tiers_present := {}
	for item in shop.pool:
		if item != null:
			tiers_present[item.tier] = true
	for weapon in shop.weapon_pool:
		if weapon != null:
			tiers_present[weapon.tier] = true

	var late := shop.tier_weights_for(30)
	var early := shop.tier_weights_for(1)
	for tier in tiers_present:
		var index: int = tier - 1
		if index < 0 or index >= early.size():
			continue
		if early[index] <= 0.0 and late[index] <= 0.0:
			_warnings.append(
				"%s : tier %d has items but zero weight at every wave, they are unreachable"
				% [path, tier]
			)

func _validate_item(path: String, item: ItemData) -> void:
	if item.display_key.is_empty():
		_errors.append("%s : empty display_key (translation key)" % path)
	if item.tier < 1 or item.tier > 4:
		_errors.append("%s : tier out of range 1-4 (%d)" % [path, item.tier])
	if item.base_price < 0:
		_errors.append("%s : base_price cannot be negative" % path)
	if item.static_stats.is_empty() and item.dynamic_effects.is_empty():
		_warnings.append("%s : item has no effect at all" % path)

	_validate_modifiers(path, item.static_stats)
	_validate_effects(path, item.dynamic_effects)

## Merging walks `upgrades_into` until it runs out, so a chain that loops back
## on itself is an infinite one. Nothing at runtime would catch it: the game
## only ever takes ONE step along the chain, so the loop is invisible until a
## player merges their way around it for ever.
func _validate_upgrade_chain(path: String, weapon: WeaponData) -> void:
	var seen: Dictionary = {weapon: true}
	var link := weapon

	while link.upgrades_into != null:
		var next := link.upgrades_into
		if seen.has(next):
			_errors.append("%s : upgrade chain loops back on itself" % path)
			return
		seen[next] = true

		# A merge is meant to be a step UP. None of these can be checked at
		# runtime, because a weapon has no idea what it was merged from.
		if next.tier < link.tier:
			_warnings.append(
				"%s : '%s' upgrades into a LOWER tier (%d -> %d)"
				% [path, link.display_key, link.tier, next.tier]
			)
		if next.base_price <= link.base_price:
			_warnings.append(
				"%s : '%s' upgrades into something no more expensive (%d -> %d)"
				% [path, link.display_key, link.base_price, next.base_price]
			)
		# A tier that quietly drops a tag breaks set-building in the least
		# visible way possible: the player merges two blades and their blade
		# count goes DOWN by two.
		for tag in link.tags:
			if not next.tags.has(tag):
				_warnings.append(
					"%s : '%s' upgrades into something that is no longer '%s'"
					% [path, link.display_key, tag]
				)

		link = next

# --- weapon classes ---------------------------------------------------------
#
# Tags are strings matched by equality, which is an open invitation to a typo:
# a weapon tagged &"blades" instead of &"blade" loads fine, validates fine as a
# file, and simply never counts toward anything. Collected across the whole
# content tree and checked once at the end, because no single file can see it.

var _declared_tags: Dictionary = {}   # StringName -> true
var _used_tags: Dictionary = {}       # StringName -> Array[String] of paths

func _validate_weapon_class(path: String, weapon_class: WeaponClassData) -> void:
	if weapon_class.tag == &"":
		_errors.append("%s : weapon class has no tag, nothing can name it" % path)
	else:
		_declared_tags[weapon_class.tag] = true

	if weapon_class.display_key.is_empty():
		_errors.append("%s : empty display_key (translation key)" % path)
	if weapon_class.tiers.is_empty():
		_warnings.append("%s : weapon class has no tiers, holding them is worth nothing" % path)

	var seen: Dictionary = {}
	for i in weapon_class.tiers.size():
		var tier: WeaponClassTier = weapon_class.tiers[i]
		if tier == null:
			_errors.append("%s : tiers[%d] is null (deleted resource?)" % [path, i])
			continue
		if tier.required <= 0:
			_errors.append("%s : tiers[%d] requires %d weapons, so it is always on" % [path, i, tier.required])
		# Bonuses are CUMULATIVE, so two tiers at the same count both apply and
		# the file reads as though only one does.
		if seen.has(tier.required):
			_errors.append("%s : two tiers both require %d, and both will apply" % [path, tier.required])
		seen[tier.required] = true
		if tier.modifiers.is_empty():
			_warnings.append("%s : tiers[%d] grants nothing" % [path, i])
		_validate_modifiers(path, tier.modifiers)

func _validate_weapon_class_set(path: String, set_data: WeaponClassSet) -> void:
	if set_data.classes.is_empty():
		_warnings.append("%s : class set is empty, no weapon can belong to anything" % path)

	var seen: Dictionary = {}
	for i in set_data.classes.size():
		var entry: WeaponClassData = set_data.classes[i]
		if entry == null:
			_errors.append("%s : classes[%d] is null (deleted resource?)" % [path, i])
			continue
		# Two classes sharing a tag both match, so every bonus lands twice.
		if seen.has(entry.tag):
			_errors.append("%s : two classes share the tag '%s'" % [path, entry.tag])
		seen[entry.tag] = true

func _validate_tags_name_real_classes() -> void:
	for tag in _used_tags:
		if _declared_tags.has(tag):
			continue
		for path in _used_tags[tag]:
			_warnings.append(
				"%s : tagged '%s', which no authored class declares, so it counts toward nothing"
				% [path, tag]
			)

## Every translation key content asks for, and where it was asked from.
const LOCALE_PATH := "res://content/locale/en.po"

var _used_keys: Dictionary = {}

## A key with no English behind it renders as ITSELF - the shop reads
## WEAPON_BOLT_DRIVER_I and nothing errors. That was the state of the whole game
## until there was a translation at all, and the failure mode of adding the
## forty-ninth weapon is exactly the same: it loads, it sells, and it has no
## name. Cheap to catch here, invisible everywhere else.
##
## Read as TEXT rather than through TranslationServer, because the validator
## must report on the file in the repo rather than on whatever the engine
## happens to have loaded for the current locale.
func _validate_keys_are_translated() -> void:
	var text := FileAccess.get_file_as_string(LOCALE_PATH)
	if text.is_empty():
		_warnings.append("%s : missing or empty, so every name on screen is a key" % LOCALE_PATH)
		return

	var translated: Dictionary = {}
	var pending := ""
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("msgid \""):
			pending = trimmed.substr(7, trimmed.length() - 8)
		elif trimmed.begins_with("msgstr \"") and not pending.is_empty():
			if trimmed.length() > 9:
				translated[pending] = true
			pending = ""

	for key in _used_keys:
		if not translated.has(key):
			_warnings.append(
				"%s : '%s' has no entry in %s, so it draws as the key itself"
				% [_used_keys[key], key, LOCALE_PATH]
			)

## Every authored character, and every character some set lists. Compared at the
## END, because a set may be walked before the characters it names or after.
var _character_paths: PackedStringArray = []
var _listed_characters: Dictionary = {}

func _validate_character_set(path: String, set_data: CharacterSet) -> void:
	if set_data.is_empty():
		_errors.append("%s : character set is empty, the lobby offers no choice at all" % path)

	var seen: Dictionary = {}
	for i in set_data.characters.size():
		var entry: CharacterData = set_data.characters[i]
		if entry == null:
			_errors.append("%s : characters[%d] is null (deleted resource?)" % [path, i])
			continue

		_listed_characters[entry.resource_path] = true
		# Asked of a SET member rather than of every character file, because the
		# paragraph is a select-screen thing: a character nothing offers - a
		# fallback, a test rig - has no screen to be blank on.
		if entry.description_key.is_empty():
			_warnings.append(
				"%s : characters[%d] (%s) has no description_key, so its panel says nothing"
				% [path, i, entry.display_key]
			)
		# Two identical entries are two slots a player cannot tell apart, and the
		# select screen would show the same name twice with no way to say why.
		if seen.has(entry.resource_path):
			_warnings.append(
				"%s : characters[%d] (%s) is listed twice" % [path, i, entry.display_key]
			)
		seen[entry.resource_path] = true

## A character no set lists and no scene names is content that loads, validates
## and can never be played - which is exactly the trap the select screen exists
## to close, so it would be perverse for the validator to miss it.
##
## Scenes are read as TEXT rather than instantiated: a .tscn names its resources
## by path, the answer needed here is only "does anything mention this", and
## instantiating a scene from a headless tool drags in the whole node layer.
func _validate_characters_are_reachable() -> void:
	var scene_text := ""
	for path in _collect_scenes("res://scenes"):
		scene_text += FileAccess.get_file_as_string(path)

	for path in _character_paths:
		if _listed_characters.has(path) or scene_text.contains(path):
			continue
		_warnings.append(
			"%s : no character set lists it and no scene names it, so it cannot be played" % path
		)

func _collect_scenes(dir_path: String) -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			found.append_array(_collect_scenes(full))
		elif entry.ends_with(".tscn"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return found

## A loadout that does not fit is the worst kind of authoring mistake: the run
## starts, the character walks around, and the weapons past the cap are simply
## not there. add_weapon refuses rather than overflowing, so nothing errors.
func _validate_character(path: String, character: CharacterData) -> void:
	_validate_entity(path, character)
	_character_paths.append(path)

	if character.weapon_slots <= 0:
		_errors.append("%s : weapon_slots must be positive, nothing can be carried" % path)

	for i in character.starting_weapons.size():
		if character.starting_weapons[i] == null:
			_errors.append("%s : starting_weapons[%d] is null (deleted weapon?)" % [path, i])

	var carried := character.starting_weapons.size()
	if carried > character.weapon_slots:
		_errors.append(
			"%s : starts with %d weapons but has %d slots, the rest are dropped in silence"
			% [path, carried, character.weapon_slots]
		)

	for i in character.starting_items.size():
		if character.starting_items[i] == null:
			_errors.append("%s : starting_items[%d] is null (deleted item?)" % [path, i])

## A charge that cannot be seen coming, or that never arrives.
##
## Both load, both run, and both are silent. The wind-up is not a flourish on
## this enemy - it is the entire reason it is fair, because a charge is answered
## by stepping ASIDE and you cannot step aside from something you were not shown.
## At 0 it is a cheap shot rather than a hard enemy, and nothing at runtime would
## ever say so.
func _validate_movement(path: String, movement: MovementBehavior) -> void:
	var charge := movement as ChargeBehavior
	if charge == null:
		return

	if charge.windup_time <= 0.0:
		_errors.append(
			"%s : charges with a wind-up of %.2fs, so it cannot be seen coming"
			% [path, charge.windup_time]
		)

	if charge.trigger_distance <= 0.0:
		_errors.append(
			"%s : commits at %.0f units, so it never charges at all"
			% [path, charge.trigger_distance]
		)

	if charge.recover_time <= 0.0:
		_warnings.append(
			"%s : recovers instantly, so a charge can be repeated with no window"
			% path
			+ " to punish it - the player can only ever run"
		)

## Something on the floor that pays nothing, or that cannot reach anybody.
##
## Both load fine and both are invisible at runtime: a pickup worth 0 is a node
## that costs frames and quietly credits nothing, and a magnet that never moves
## looks exactly like a player who did not walk close enough.
func _validate_pickup(path: String, pickup: PickupData) -> void:
	_validate_entity(path, pickup)

	if pickup.value <= 0:
		_errors.append("%s : pays %d, so collecting it does nothing" % [path, pickup.value])

	if pickup.base_magnet < 0.0:
		_warnings.append(
			"%s : has a negative base_magnet (%.1f), which is clamped to nothing"
			% [path, pickup.base_magnet]
		)

	# Reaching for something it cannot travel to. It is still collectable by
	# walking onto it, which is exactly what makes this quiet rather than broken.
	if pickup.base_magnet > 0.0 and pickup.magnet_speed <= 0.0:
		_warnings.append(
			"%s : attracts from %.0f units but moves at %.0f, so it never arrives"
			% [path, pickup.base_magnet, pickup.magnet_speed]
		)

func _validate_entity(path: String, entity: EntityData) -> void:
	if entity.display_key.is_empty():
		_errors.append("%s : empty display_key (translation key)" % path)
	if entity.collider_radius <= 0.0:
		_errors.append("%s : collider_radius must be positive" % path)

	_validate_modifiers(path, entity.base_stats)
	_validate_effects(path, entity.innate_effects)

	if entity is ProjectileData:
		_validate_projectile_effects(path, entity as ProjectileData)

	if entity is EnemyData:
		_validate_movement(path, (entity as EnemyData).movement)


## A projectile runs its innate effects on IMPACT and only on impact.
##
## Projectile._run_projectile_effects calls execute() directly rather than going
## through a dispatcher, so it never looks at get_hooks() - which means an effect
## authored here for any other occasion loads, validates against every other
## check, and then fires at the wrong moment for the rest of the game. There is
## no dispatcher on a projectile to catch it, because a projectile deliberately
## has no EntityModel of its own.
func _validate_projectile_effects(path: String, projectile: ProjectileData) -> void:
	for i in projectile.innate_effects.size():
		var effect: DynamicEffect = projectile.innate_effects[i]
		if effect == null:
			continue
		if not effect.get_hooks().has(Hooks.Hook.ON_IMPACT):
			_errors.append(
				"%s : effect[%d] does not declare ON_IMPACT, but a projectile runs"
				% [path, i]
				+ " its effects on impact regardless - it would fire at the wrong time"
			)

## NO LOOP CHECK HERE, and that is a finding rather than an omission.
##
## A splitter bursting into splitters never ends, so this file grew a walk over
## EffectSpawn.data looking for a cycle - and the walk can never fire. Godot
## refuses to LOAD a .tres that references itself, directly or through an
## intermediate, so authored content cannot express the loop at all; the attempt
## was verified by building splitter -> swarmling -> splitter, which came back as
## four "cannot be loaded" errors before any of this ran.
##
## A check that cannot fire is worse than no check, because it reads like cover.

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

		if effect is EffectBlast:
			_validate_blast(path, "effect[%d]" % i, (effect as EffectBlast).blast)

		var spawn := effect as EffectSpawn
		if spawn != null:
			if spawn.data == null:
				_errors.append("%s : effect[%d] spawns nothing at all" % [path, i])
			if spawn.count <= 0:
				_errors.append(
					"%s : effect[%d] spawns a count of %d" % [path, i, spawn.count]
				)
			if spawn.trigger == EffectSpawn.Trigger.ON_INTERVAL and spawn.interval <= 0.0:
				_errors.append(
					"%s : effect[%d] is on a timer of %.1fs, which never fires"
					% [path, i, spawn.interval]
				)

## An explosion that loads, prices, sells and goes off for nothing.
##
## Every failure here is silent at runtime: a blast with no radius catches
## nobody, and a blast with no damage catches everybody and does nothing to them.
## Neither logs anything, and both read as "the explosion is not working" long
## after whoever authored it has moved on.
func _validate_blast(path: String, label: String, blast: BlastData) -> void:
	if blast == null:
		_errors.append("%s : %s explodes with no BlastData at all" % [path, label])
		return

	if blast.radius <= 0.0:
		_errors.append("%s : %s has a blast radius of %.1f, which reaches nobody"
			% [path, label, blast.radius])

	# An empty scaling table means "all of my own damage type", which is a real
	# number for a player carrying elemental items and exactly zero for every
	# authored enemy. Base damage of nothing on top of it is a blast that only
	# works for half the things that can hold it.
	if blast.base_damage <= 0.0 and blast.damage_scaling.is_empty():
		_warnings.append(
			"%s : %s has no base damage and no scaling, so it deals only whatever"
			% [path, label]
			+ " its source's own damage type happens to be"
		)

	for scaling in blast.damage_scaling:
		if scaling == null:
			_errors.append("%s : %s has a null entry in damage_scaling" % [path, label])
		elif not StatTypes.Stat.values().has(scaling.stat):
			_errors.append("%s : %s scales off a stat outside the enum (%d)"
				% [path, label, scaling.stat])
