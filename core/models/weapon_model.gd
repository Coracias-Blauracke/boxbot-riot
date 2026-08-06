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
	# ATTACK_SPEED and PROJECTILE_SPEED need no line here any more: EntityModel
	# seeds every multiplicative stat with its neutral, and for those two the
	# neutral IS the default. This is +1.0 ON TOP of that neutral, so a weapon
	# that says nothing about crits still does double damage on one.
	stats.add_modifier(StatTypes.Stat.CRIT_MULTIPLIER, StatTypes.Modifier.BASE, 1.0, &"weapon_base")

	if data != null:
		setup_from_data(data)
		_weapon_data = data as WeaponData

## Kept because the scaling tables live on it, and build_shot is not the only
## thing that needs them.
var _weapon_data: WeaponData = null

# --- inheriting the wielder's stats -----------------------------------------

## A stat as this weapon actually experiences it: its own, plus whatever share
## of its wielder's it inherits.
##
## EVERY read site goes through here - the firing interval, crit, range, spread,
## piercing, projectile speed, recoil and heat. That is the whole point. Before
## this existed each site read `stats.get_stat()` directly and the wielder's
## copy was never consulted at all, so a player's ATTACK_SPEED or CRIT_CHANCE
## moved a number in the stat sheet and changed nothing about a shot. Eleven
## sites each combining in their own way is how that happens twice.
func combined_stat(stat: StatTypes.Stat) -> float:
	var own := stats.get_stat(stat)
	var holder := get_wielder()
	if holder == null:
		return own

	var share := inheritance_share(stat)
	if is_zero_approx(share):
		return own

	var neutral := StatTypes.neutral_of(stat)

	# A multiplier multiplies, and only its DEVIATION from neutral is shared -
	# half of a 1.4 attack speed is 1.2, not 0.7.
	if not is_zero_approx(neutral):
		var theirs := holder.stats.get_stat(stat)
		return own * (neutral + (theirs - neutral) * share) / neutral

	return _combine_additive(stat, own, holder, share)

## A quantity, where the holder's POOLS have to be read apart rather than as one
## total.
##
## Their flat bonuses ADD to the weapon and their percentages SCALE it, and the
## difference is not academic: "-20% spread" is a percentage of the HOLDER's own
## spread, which is zero, so reading their total would make the item worth
## exactly nothing. `machined_sights` was authored that way and was decorative
## for this reason on top of the transfer being missing at all. What the player
## means by -20% spread is a fifth off the gun they are holding.
func _combine_additive(
	stat: StatTypes.Stat, own: float, holder: EntityModel, share: float
) -> float:
	var pool := holder.stats.get_pool_breakdown(stat)
	var flat: float = pool[StatTypes.Modifier.BASE] + pool[StatTypes.Modifier.FLAT]
	var percent: float = pool[StatTypes.Modifier.PERCENT]
	var mult: float = pool[StatTypes.Modifier.MULT]

	# Shares apply to every pool alike, so a weapon inheriting half of a stat
	# takes half the flat AND half the percentage rather than all of one.
	return (
		(own + flat * share)
		* (1.0 + percent * share)
		* (1.0 + (mult - 1.0) * share)
	)

## Unlisted stats transfer in full, so a weapon says only what it withholds.
func inheritance_share(stat: StatTypes.Stat) -> float:
	if _weapon_data == null:
		return 1.0
	for scaling in _weapon_data.stat_inheritance:
		if scaling != null and scaling.stat == stat:
			return scaling.coefficient
	return 1.0

func set_wielder(entity: EntityModel) -> void:
	wielder = weakref(entity) if entity != null else null

func get_wielder() -> EntityModel:
	return wielder.get_ref() as EntityModel if wielder != null else null

# --- heat ------------------------------------------------------------------

func heat_capacity() -> float:
	return combined_stat(StatTypes.Stat.HEAT_CAPACITY)

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
	heat = maxf(0.0, heat - combined_stat(StatTypes.Stat.HEAT_DISSIPATION) * delta)
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
	shot.amount = _base_damage(holder, shot.damage_type, data) * damage_scale
	shot.crit_chance = combined_stat(StatTypes.Stat.CRIT_CHANCE)
	shot.crit_multiplier = combined_stat(StatTypes.Stat.CRIT_MULTIPLIER)

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

## The weapon supplies its own damage; the WIELDER's stats are then added
## through the weapon's scaling table.
##
## The table is what lets a weapon care about something other than its own
## damage type - max HP, movement speed, anything - and what lets a very fast
## weapon take only half of a damage bonus. Empty means "all of my own damage
## type", which is exactly what this function did before the table existed.
## `data` is the resource build_shot was handed; `_weapon_data` is the one this
## model was built from. They are the same file in the game and only differ in
## tests, so preferring the argument keeps one truth rather than two.
func _base_damage(
	holder: EntityModel, damage_type: StatTypes.DamageType, data: WeaponData = null
) -> float:
	var own_stat := (
		StatTypes.Stat.MELEE_DAMAGE
		if damage_type == StatTypes.DamageType.MELEE
		else StatTypes.Stat.RANGED_DAMAGE
	)
	if holder == null:
		return stats.get_stat(own_stat)

	# Not a ternary with `[]` in it: the untyped empty array cannot be assigned
	# to an Array[StatScaling], and the parse error takes the whole suite with
	# it rather than failing one assertion.
	var source := data if data != null else _weapon_data
	var table: Array[StatScaling] = []
	if source != null:
		table = source.damage_scaling

	# Nothing authored: all of the holder's matching damage, through the same
	# pool-aware path every other stat takes - so "+20% ranged damage" scales
	# the gun rather than scaling the holder's own zero.
	if table.is_empty():
		return combined_stat(own_stat)

	var total := stats.get_stat(own_stat)
	for scaling in table:
		if scaling == null:
			continue
		if scaling.stat == own_stat:
			# The weapon's OWN kind of damage: a share of the holder's bonuses,
			# applied to the weapon's own number.
			total = _combine_additive(own_stat, total, holder, scaling.coefficient)
		else:
			# A FOREIGN stat contributes its VALUE instead. "10% of max HP"
			# means a tenth of the number on the sheet, which is get_stat.
			total += holder.stats.get_stat(scaling.stat) * scaling.coefficient
	return total
