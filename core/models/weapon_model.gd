class_name WeaponModel
extends EntityModel

## A weapon is an EntityModel like everything else - it has its own stats, its
## own counters and its own effects - plus the temporal state of firing.
##
## This subclass is justified where PlayerModel was not: PlayerModel held
## nothing of its own once currency moved into the counters, whereas a weapon has
## real state that effects need to read and modify - heat, spin-up, burst
## progress, which side it swung from last.

signal overheated
signal cooled_down

var wielder: WeakRef = null

## HEAT is available to every weapon, not just miniguns. Setting heat_per_shot
## to 0 in the data disables it entirely, which is how most weapons will run.
## Capacity and dissipation are stats, so items can widen or vent them.
var heat: float = 0.0
var is_overheated: bool = false

## Spin-up progress, 0..1. Windup weapons ramp this; everything else ignores it.
var spin: float = 0.0

var cooldown: float = 0.0
var burst_remaining: int = 0
var channel_remaining: float = 0.0

## Scales the next shot; charge weapons raise it, everything else leaves it at 1.
var damage_scale: float = 1.0

## Neutral bases, added before the data so a weapon that says nothing about
## these behaves sanely rather than falling to the stat floor.
##
## Note the division of labour for fire rate: the weapon's OWN speed is
## `FiringPattern.base_interval` (seconds between shots). ATTACK_SPEED is the
## multiplier characters and items apply on top, and is neutral at 1.0. A weapon
## that should be inherently fast lowers its interval; it does not set this stat.
func _init(data: EntityData = null) -> void:
	super()
	stats.add_modifier(StatTypes.Stat.ATTACK_SPEED, StatTypes.Modifier.BASE, 1.0, &"weapon_base")
	stats.add_modifier(StatTypes.Stat.PROJECTILE_SPEED, StatTypes.Modifier.BASE, 1.0, &"weapon_base")
	stats.add_modifier(StatTypes.Stat.CRIT_MULTIPLIER, StatTypes.Modifier.BASE, 2.0, &"weapon_base")

	if data != null:
		setup_from_data(data)

func set_wielder(entity: EntityModel) -> void:
	wielder = weakref(entity) if entity != null else null

func get_wielder() -> EntityModel:
	return wielder.get_ref() as EntityModel if wielder != null else null

# --- heat ------------------------------------------------------------------

func heat_capacity() -> float:
	return stats.get_stat(StatTypes.Stat.HEAT_CAPACITY)

func heat_ratio() -> float:
	var capacity := heat_capacity()
	return clampf(heat / capacity, 0.0, 1.0) if capacity > 0.0 else 0.0

func add_heat(amount: float) -> void:
	if amount <= 0.0:
		return
	heat += amount
	if not is_overheated and heat >= heat_capacity():
		heat = heat_capacity()
		is_overheated = true
		notify(Hooks.Hook.ON_OVERHEAT, EventPayload.new())
		overheated.emit()

## Overheating locks the weapon until it has vented most of its heat, rather
## than freeing it the instant heat dips below the cap - otherwise a weapon at
## capacity stutters one shot at a time instead of properly cooling.
const VENT_RATIO := 0.35

func cool(delta: float) -> void:
	if heat <= 0.0:
		return
	heat = maxf(0.0, heat - stats.get_stat(StatTypes.Stat.HEAT_DISSIPATION) * delta)
	if is_overheated and heat <= heat_capacity() * VENT_RATIO:
		is_overheated = false
		cooled_down.emit()

func can_fire() -> bool:
	return is_alive and not is_overheated

# --- firing ----------------------------------------------------------------

## Phase 1 of damage: everything the SOURCE contributes, frozen once per shot.
##
## Order matters. The pipeline runs first so effects can adjust the amount and
## the crit chance ("your next shot always crits"); only then is the single roll
## made and the multiplier applied. Every projectile from this shot then shares
## the outcome.
func build_shot(data: WeaponData) -> ShotSnapshot:
	var holder := get_wielder()

	var shot := ShotSnapshot.new()
	shot.source = holder
	shot.weapon = self
	shot.damage_type = (
		StatTypes.DamageType.MELEE
		if data != null and data.delivery == WeaponData.DeliveryKind.MELEE_SWEEP
		else StatTypes.DamageType.RANGED
	)
	shot.amount = _base_damage(holder, shot.damage_type) * damage_scale
	shot.crit_chance = stats.get_stat(StatTypes.Stat.CRIT_CHANCE)
	shot.crit_multiplier = stats.get_stat(StatTypes.Stat.CRIT_MULTIPLIER)

	if data != null:
		shot.falloff_start = data.falloff_start
		shot.falloff_end = data.falloff_end
		shot.falloff_multiplier = data.falloff_multiplier

	# The weapon's own effects first, then the wielder's.
	pipeline(Hooks.Hook.CALCULATE_DAMAGE, shot)
	if holder != null:
		holder.pipeline(Hooks.Hook.CALCULATE_DAMAGE, shot)

	shot.is_crit = rng.chance(RunRandom.Stream.COMBAT, shot.crit_chance)
	if shot.is_crit:
		shot.amount *= shot.crit_multiplier
		counters.add(CounterTypes.Counter.CRITS_LANDED)
		if holder != null:
			holder.counters.add(CounterTypes.Counter.CRITS_LANDED)
			holder.notify(Hooks.Hook.ON_CRIT, shot)

	damage_scale = 1.0
	return shot

## The weapon supplies its own damage; the wielder's matching stat adds on top,
## which is why a melee character makes every melee weapon better.
func _base_damage(holder: EntityModel, damage_type: StatTypes.DamageType) -> float:
	var stat := (
		StatTypes.Stat.MELEE_DAMAGE
		if damage_type == StatTypes.DamageType.MELEE
		else StatTypes.Stat.RANGED_DAMAGE
	)
	var total := stats.get_stat(stat)
	if holder != null:
		total += holder.stats.get_stat(stat)
	return total
