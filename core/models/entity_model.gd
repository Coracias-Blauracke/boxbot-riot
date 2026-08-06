class_name EntityModel
extends RefCounted

## The ONE model for everything that exists in the world: the player, enemies,
## bosses, weapons, turrets, destructible obstacles, and the map and run models
## themselves.
##
## There is deliberately no PlayerModel or EnemyModel subclass. Once currency moved
## into the counters, nothing distinguished them but the way they are driven -
## input versus AI - and that is a concern of the scene layer, not of the model.
##
## Pure logic - RefCounted, zero SceneTree dependencies. That is what allows the
## whole game to be run and tested headless, without the editor.

signal died
signal revived
signal hp_changed(current: float, maximum: float)

var stats: StatsManager
var counters: CounterManager
var effects: EffectDispatcher
var statuses: StatusManager

var current_hp: float = 0.0
var is_alive: bool = true

## Where this entity is, written once per frame by its Actor.
##
## A Vector2 rather than a node reference, which is what keeps core/ Node-free
## while still letting it answer "what is within 120 units of here" - the same
## trick SpawnContext uses. core/ never writes this; it is a read-only fact
## handed down from the view.
var world_position: Vector2 = Vector2.ZERO

## Weak, set by WorldCensus.register. Lets an effect reaching outwards - fire
## spreading off a corpse - ask what is nearby at the moment it fires, when
## there is no payload to thread the answer through. Weak in both directions:
## the census holds weakrefs to entities and this holds one back, so neither can
## keep the other alive.
var _census_ref: WeakRef = null

func set_census(census: WorldCensus) -> void:
	_census_ref = weakref(census)

func get_census() -> WorldCensus:
	return _census_ref.get_ref() as WorldCensus if _census_ref != null else null

var _items: ItemsManager = null
var _rng: RunRandom = null
var _last_max_hp: float = 0.0

## Whoever last landed damage, for kill credit. Weak, because the killer may
## well die before its victim's death is processed.
var last_attacker: WeakRef = null

func get_last_attacker() -> EntityModel:
	return last_attacker.get_ref() as EntityModel if last_attacker != null else null

## Injected by RunModel.add_player so the whole run shares one seed. Falls back
## to a private generator when the entity is used standalone (tests, previews);
## assign explicitly when a deterministic roll matters.
var rng: RunRandom:
	get:
		if _rng == null:
			_rng = RunRandom.new()
		return _rng
	set(value):
		_rng = value

## Created on first use - a rock or a projectile never needs an inventory, and
## there may be hundreds of them on screen.
var items: ItemsManager:
	get:
		if _items == null:
			_items = ItemsManager.new()
		return _items

func _init(data: EntityData = null) -> void:
	stats = StatsManager.new()
	counters = CounterManager.new()
	effects = EffectDispatcher.new()
	statuses = StatusManager.new()
	stats.stat_changed.connect(_on_stat_changed)
	_seed_neutrals()

	if data != null:
		setup_from_data(data)

## Every multiplicative stat starts at the value that means "no effect".
##
## Without this a player's ATTACK_SPEED reads its FLOOR of 0.05, because nothing
## ever set a base for it - and the moment a weapon starts inheriting its
## wielder's attack speed, that 0.05 would slow every weapon in the game to a
## twentieth of its rate. A floor is not a default; this is the default.
##
## Seeded for EVERY entity rather than for players, because "everything carries
## the full stat set" is the decision the whole stat system rests on, and an
## enemy whose attack speed reads 0.05 is wrong in exactly the same way.
func _seed_neutrals() -> void:
	for stat in StatTypes.NEUTRALS:
		stats.add_modifier(
			stat, StatTypes.Modifier.BASE, StatTypes.NEUTRALS[stat], &"stat_neutral"
		)

func setup_from_data(data: EntityData) -> void:
	if data == null:
		return

	for modifier in data.base_stats:
		if modifier == null:
			continue
		stats.add_modifier(modifier.stat, modifier.modifier_type, modifier.value, data)

	for effect in data.innate_effects:
		if effect == null:
			continue
		effects.register(EffectInstance.new(effect, data))

	if data is CharacterData:
		var character := data as CharacterData
		stats.add_modifier(
			StatTypes.Stat.WEAPON_SLOTS, StatTypes.Modifier.BASE, float(character.weapon_slots), data
		)
		stats.add_modifier(
			StatTypes.Stat.SHOP_SLOTS, StatTypes.Modifier.BASE, float(character.shop_slots), data
		)

	current_hp = stats.get_stat(StatTypes.Stat.MAX_HP)
	_last_max_hp = current_hp
	hp_changed.emit(current_hp, _last_max_hp)

# --- events ----------------------------------------------------------------

## NOTIFICATION: "this happened". The payload is read-only.
func notify(hook: Hooks.Hook, event: EventPayload) -> void:
	effects.dispatch(self, hook, event)

## PIPELINE: "this is about to happen, change it". Effects mutate the payload
## one after another in `priority` order; the same object is returned carrying
## the result.
func pipeline(hook: Hooks.Hook, event: EventPayload) -> EventPayload:
	return effects.dispatch(self, hook, event)

# --- inventory -------------------------------------------------------------

func add_item(item: ItemData, quantity: int = 1) -> void:
	items.add_item(self, item, quantity)

func remove_item(item: ItemData, quantity: int = 1) -> void:
	items.remove_item(self, item, quantity)

# --- weapons ---------------------------------------------------------------
#
# WHAT IS CARRIED IS MODEL STATE; the nodes in the hands are a view of it. It
# used to be the other way round - WeaponMount owned the list and main.gd was
# the only caller - which is why a weapon could not be bought, sold, saved or
# even authored on a character: nothing outside the scene could see it.
#
# A plain array rather than a WeaponsManager. ItemsManager exists because items
# have real bookkeeping (per-copy modifier handles, effect instances, stacks);
# a weapon pushes nothing into the buyer's stats, because its base_stats belong
# to the WeaponModel the Weapon node builds. There is no state here to manage,
# and a manager holding one array would be a layer that only forwards.
#
# Duplicates are allowed on purpose: two of the same pistol is an ordinary
# loadout in this genre, and it falls out of a list rather than needing a count.

signal weapons_changed

var weapons: Array[WeaponData] = []

## The classes this entity's weapons count toward. Injected, because core/ may
## not load content - the same way rng and the census arrive.
var weapon_classes: WeaponClassSet = null:
	set(value):
		weapon_classes = value
		_refresh_class_bonuses()

## Capacity, read off the WEAPON_SLOTS stat so a character starting with eight,
## an item granting one and a curse taking one away are all ordinary modifiers.
func weapon_slots() -> int:
	return maxi(0, roundi(stats.get_stat(StatTypes.Stat.WEAPON_SLOTS)))

func has_free_weapon_slot() -> bool:
	return weapons.size() < weapon_slots()

func weapon_count(weapon: WeaponData) -> int:
	var total := 0
	for entry in weapons:
		if entry == weapon:
			total += 1
	return total

## Refuses rather than overflowing. The shop asks first through
## WeaponData.can_be_acquired_by, so a refusal here means a caller went around
## it - and silently carrying a ninth weapon in six slots is worse than nothing
## happening.
func add_weapon(weapon: WeaponData) -> bool:
	if weapon == null or not has_free_weapon_slot():
		return false
	weapons.append(weapon)
	_refresh_class_bonuses()
	weapons_changed.emit()
	return true

## Removes ONE copy, not every copy. Selling one of two identical pistols must
## leave the other one in your hands.
func remove_weapon(weapon: WeaponData) -> bool:
	var index := weapons.find(weapon)
	if index < 0:
		return false
	weapons.remove_at(index)
	_refresh_class_bonuses()
	weapons_changed.emit()
	return true

## WeaponClassData -> Array[EffectInstance] currently granted by it. Held only
## so the recompute can strip what an effect of its own added.
var _class_effects: Dictionary = {}

## How many carried weapons name this tag. Two copies of one blade is two.
func weapon_tag_count(tag: StringName) -> int:
	var total := 0
	for weapon in weapons:
		if weapon != null and weapon.tags.has(tag):
			total += 1
	return total

## Strips every class bonus and reapplies from scratch.
##
## IDEMPOTENT ON PURPOSE, and for the reason EffectStatPerWorldCount is: the
## count goes DOWN as well as up. Selling the third blade has to take the third
## blade's bonus away, and an incremental version that adds on acquisition and
## subtracts on loss breaks permanently the first time an event is missed. A
## recompute cannot drift.
##
## The source is the class RESOURCE, so remove_all_from_source strips exactly
## that class's contribution and nothing else - the same trick that lets an
## expiring status remove only what it added when several overlap on one stat.
func _refresh_class_bonuses() -> void:
	if weapon_classes == null:
		return

	for entry in weapon_classes.classes:
		if entry == null:
			continue

		# Modifiers an EFFECT of this class added carry the INSTANCE as their
		# source, not the class, so they have to be stripped through the
		# instances before the instances themselves are dropped. Same order
		# ItemsManager uses when an item leaves.
		for instance in _class_effects.get(entry, []):
			stats.remove_all_from_source(instance)
		effects.unregister_source(entry)
		stats.remove_all_from_source(entry)

		var count := weapon_tag_count(entry.tag)
		for modifier in entry.modifiers_for(count):
			stats.add_modifier(modifier.stat, modifier.modifier_type, modifier.value, entry)

		var created: Array[EffectInstance] = []
		for effect in entry.effects_for(count):
			var instance := EffectInstance.new(effect, entry)
			effects.register(instance)
			created.append(instance)
		_class_effects[entry] = created

# --- currency --------------------------------------------------------------
#
# Currency is a counter, not a stat: accumulated state that must be saved and
# must never be touched by a percent modifier. CURRENCY is the spendable
# balance, CURRENCY_EARNED the lifetime tally that "every 500 earned" effects
# hang on. Nothing here names a theme, so it can be coins, crystals or scrap.

func get_currency() -> int:
	return counters.get_value(CounterTypes.Counter.CURRENCY)

func add_currency(amount: int) -> void:
	counters.add(CounterTypes.Counter.CURRENCY, amount)
	if amount > 0:
		counters.add(CounterTypes.Counter.CURRENCY_EARNED, amount)

func can_afford(amount: int) -> bool:
	return get_currency() >= amount

# --- statuses --------------------------------------------------------------

func apply_status(
	definition: StatusEffect, applier: EntityModel = null, stacks: int = 1,
	duration: float = -1.0, chance: float = -1.0
) -> ActiveStatus:
	return statuses.apply(self, definition, applier, stacks, duration, chance)

func tick_statuses(delta: float) -> void:
	statuses.tick(self, delta)

# --- health and damage -----------------------------------------------------

func get_max_hp() -> float:
	return stats.get_stat(StatTypes.Stat.MAX_HP)

## The single entry point for damage. Runs the target-side pipeline, gives
## BEFORE_DEATH a chance to cancel a lethal blow, applies the result and then
## notifies both sides.
func apply_damage(event: DamageEvent) -> float:
	# A corpse takes no further hits. Every blow landing on something already
	# dead used to award another ENEMIES_KILLED and fire ON_KILL again, because
	# the credit below only checks `not is_alive`. That was unreachable while
	# everything was freed the instant it died; downed players now persist, so a
	# damage-over-time status on one would have farmed kill credit forever.
	if not is_alive:
		return 0.0

	event.target = self

	# Offence first with the target now known, then defence - the same two-phase
	# shape statuses use. The attacker gets to say "more damage to burning
	# things" before the victim gets to say "I resist fire".
	if event.source != null:
		event.source.pipeline(Hooks.Hook.ON_OUTGOING_DAMAGE, event)
	pipeline(Hooks.Hook.TAKE_DAMAGE, event)
	if event.cancelled:
		return 0.0

	var final := event.final_amount()

	if final >= current_hp and is_alive:
		# Room for "survive one lethal hit per wave" style effects.
		var lethal := pipeline(Hooks.Hook.BEFORE_DEATH, event)
		if lethal.cancelled:
			return 0.0

	if final > 0.0:
		counters.add(CounterTypes.Counter.DAMAGE_TAKEN, roundi(final))
		if event.source != null:
			last_attacker = weakref(event.source)
		set_hp(current_hp - final)

	notify(Hooks.Hook.ON_DAMAGE_TAKEN, event)
	if event.source != null:
		event.source.counters.add(CounterTypes.Counter.DAMAGE_DEALT, roundi(final))
		event.source.notify(Hooks.Hook.ON_DAMAGE_DEALT, event)
		if not is_alive:
			event.source.counters.add(CounterTypes.Counter.ENEMIES_KILLED)
			event.source.notify(Hooks.Hook.ON_KILL, event)

	return final

func set_hp(value: float) -> void:
	var maximum := get_max_hp()
	var clamped := clampf(value, 0.0, maximum)
	if is_equal_approx(clamped, current_hp):
		return
	current_hp = clamped
	hp_changed.emit(current_hp, maximum)
	if current_hp <= 0.0 and is_alive:
		is_alive = false
		notify(Hooks.Hook.ON_DEATH, EventPayload.new())
		died.emit()

## Brings a downed entity back on `fraction` of its max HP.
##
## Deliberately NOT heal(): healing a corpse must stay impossible, or lifesteal
## and regeneration would quietly undo death. Who may stand up again, and when,
## is a decision of the run - see RunTypes.DeathRule - and this is the only door
## it has.
func revive(fraction: float = 1.0) -> float:
	if is_alive:
		return 0.0

	is_alive = true
	set_hp(get_max_hp() * clampf(fraction, 0.01, 1.0))
	revived.emit()
	return current_hp

## Goes through CALCULATE_HEAL so effects can scale or block healing, then
## notifies ON_HEAL with what actually landed. Previously this called set_hp()
## directly and both hooks were unreachable.
func heal(amount: float, source: EntityModel = null) -> float:
	# Healing must never raise a corpse. set_hp() would happily push current_hp
	# back above zero while is_alive stayed false, leaving an entity that is
	# neither dead nor playable. Standing up goes through revive() only.
	if amount <= 0.0 or not is_alive:
		return 0.0

	var event := HealEvent.new()
	event.source = source
	event.target = self
	event.amount = amount

	pipeline(Hooks.Hook.CALCULATE_HEAL, event)
	if event.cancelled:
		return 0.0

	var before := current_hp
	set_hp(current_hp + event.amount)
	event.applied = current_hp - before

	if event.applied > 0.0:
		notify(Hooks.Hook.ON_HEAL, event)
		if source != null and source != self:
			source.notify(Hooks.Hook.ON_HEAL, event)

	return event.applied

## current_hp is STATE, so it does not recompute itself from the stats - a
## change of MAX_HP has to be reacted to explicitly. An increase tops up the
## same amount (a +50 max HP item heals for 50); a decrease only clamps.
func _on_stat_changed(stat: StatTypes.Stat) -> void:
	if stat != StatTypes.Stat.MAX_HP:
		return

	var new_max := get_max_hp()
	var delta := new_max - _last_max_hp
	_last_max_hp = new_max

	if delta > 0.0:
		current_hp += delta
	current_hp = clampf(current_hp, 0.0, new_max)
	hp_changed.emit(current_hp, new_max)
