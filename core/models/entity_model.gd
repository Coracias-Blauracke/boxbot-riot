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
signal hp_changed(current: float, maximum: float)

var stats: StatsManager
var counters: CounterManager
var effects: EffectDispatcher
var statuses: StatusManager

var current_hp: float = 0.0
var is_alive: bool = true

var _items: ItemsManager = null
var _rng: RunRandom = null
var _last_max_hp: float = 0.0

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

	if data != null:
		setup_from_data(data)

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
		stats.add_modifier(
			StatTypes.Stat.WEAPON_SLOTS,
			StatTypes.Modifier.BASE,
			float((data as CharacterData).weapon_slots),
			data
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

func apply_status(definition: StatusEffect, applier: EntityModel = null, stacks: int = 1, duration: float = -1.0) -> ActiveStatus:
	return statuses.apply(self, definition, applier, stacks, duration)

func tick_statuses(delta: float) -> void:
	statuses.tick(self, delta)

# --- health and damage -----------------------------------------------------

func get_max_hp() -> float:
	return stats.get_stat(StatTypes.Stat.MAX_HP)

## The single entry point for damage. Runs the target-side pipeline, gives
## BEFORE_DEATH a chance to cancel a lethal blow, applies the result and then
## notifies both sides.
func apply_damage(event: DamageEvent) -> float:
	event.target = self
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

func heal(amount: float) -> void:
	set_hp(current_hp + amount)

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
