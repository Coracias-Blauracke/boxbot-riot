class_name Weapon
extends Node2D

## ONE scene for every weapon - guns, melee, beams. The differences live in the
## four resources on WeaponData, not in subclasses.
##
## Fully automatic, like the genre expects: the weapon picks its own target and
## fires on its own. There is no trigger, which also means input latency over
## Remote Play never touches combat.

const PROJECTILE_SCENE := preload("res://scenes/projectiles/projectile.tscn")

var model: WeaponModel
var data: WeaponData
var wielder: Actor

var _target: Actor

# --- melee swing state -----------------------------------------------------
var _swing: SwingPattern
var _swing_snapshot: ShotSnapshot
var _swing_time: float = 0.0
var _swing_duration: float = 0.0
var _swing_mirrored: bool = false
var _swing_hits: Array[EntityModel] = []

func bind(p_data: WeaponData, p_wielder: Actor) -> void:
	data = p_data
	wielder = p_wielder
	model = WeaponModel.new(p_data)
	model.set_wielder(p_wielder.model)
	model.rng = p_wielder.model.rng

func _physics_process(delta: float) -> void:
	if model == null or data == null or wielder == null:
		return

	model.cool(delta)
	_target = _acquire_target()

	# A swing is committed once started: retargeting mid-blow would make the
	# weapon snap around in the middle of its own animation.
	if _swing == null and _target != null:
		rotation = (_target.global_position - global_position).angle()

	if _swing != null:
		_advance_swing(delta)

	var shots := data.firing.advance(model, delta, _target != null)
	for i in shots:
		_fire()

	queue_redraw()

# --- targeting -------------------------------------------------------------

func _acquire_target() -> Actor:
	var enemies := get_tree().get_nodes_in_group(&"enemies")
	if enemies.is_empty() or data.targeting == null:
		return null

	var positions := PackedVector2Array()
	var models: Array = []
	var actors: Array[Actor] = []

	for node in enemies:
		var enemy := node as Actor
		if enemy == null or enemy.model == null or not enemy.model.is_alive:
			continue
		positions.append(enemy.global_position)
		models.append(enemy.model)
		actors.append(enemy)

	# Deliberately the WEAPON's position, not the wielder's centre. Weapons on
	# opposite sides of the mount then cover different directions on their own,
	# which turned out to feel good - do not "fix" this to use the character.
	var index := data.targeting.select(
		global_position, positions, models, model.stats.get_stat(StatTypes.Stat.RANGE)
	)
	return actors[index] if index >= 0 else null

# --- firing ----------------------------------------------------------------

func _fire() -> void:
	# ONE snapshot per shot, shared by every projectile - that is what makes all
	# eight pellets of a shotgun crit or not crit together.
	var shot := model.build_shot(data)

	var aim := Vector2.RIGHT.rotated(rotation)
	var spread := model.stats.get_stat(StatTypes.Stat.SPREAD_ANGLE)
	var pattern := data.spread if data.spread != null else null
	var directions := (
		pattern.directions(aim, spread, model.rng)
		if pattern != null
		else PackedVector2Array([aim])
	)

	match data.delivery:
		WeaponData.DeliveryKind.PROJECTILE:
			_fire_projectiles(shot, directions)
		WeaponData.DeliveryKind.MELEE_SWEEP:
			_start_swing(shot)
		_:
			push_warning("Weapon: delivery kind %d not implemented yet" % data.delivery)

	model.add_heat(data.heat_per_shot)
	model.counters.add(CounterTypes.Counter.BULLETS_FIRED, directions.size())

	var holder := wielder.model
	if holder != null:
		holder.counters.add(CounterTypes.Counter.BULLETS_FIRED, directions.size())
		holder.notify(Hooks.Hook.ON_WEAPON_FIRED, shot)

	var recoil := data.recoil + model.stats.get_stat(StatTypes.Stat.RECOIL)
	if recoil > 0.0:
		wielder.impulse -= aim * recoil

func _fire_projectiles(shot: ShotSnapshot, directions: PackedVector2Array) -> void:
	if data.projectile == null:
		push_warning("Weapon: PROJECTILE delivery with no projectile data")
		return

	var scene: PackedScene = data.projectile_scene if data.projectile_scene != null else PROJECTILE_SCENE
	var pierce := roundi(model.stats.get_stat(StatTypes.Stat.PIERCING))
	var bounce := roundi(model.stats.get_stat(StatTypes.Stat.BOUNCING))
	var speed_multiplier := model.stats.get_stat(StatTypes.Stat.PROJECTILE_SPEED)

	for direction in directions:
		var projectile := scene.instantiate() as Projectile
		projectile.launch(data.projectile, shot, direction, pierce, bounce, speed_multiplier, wielder.world)
		projectile.global_position = global_position
		# Parented to the level, not the weapon: a bullet must not follow the
		# barrel once it has left it.
		wielder.get_parent().add_child(projectile)

# --- melee -----------------------------------------------------------------

## Diagnostic: "-" idle, "w" winding up, "!" live blade.
func debug_swing_state() -> String:
	if _swing == null:
		return "-"
	var t := _swing_time / _swing_duration
	return "!" if _swing.is_active(t) else "w"

func _start_swing(shot: ShotSnapshot) -> void:
	var combo := data.melee_combo
	if combo.is_empty():
		push_warning("Weapon: MELEE_SWEEP delivery with no swing in melee_combo")
		return

	# The combo advances per attack, so "slash, slash, heavy thrust" is authored
	# in the list rather than coded as a state machine.
	var attack_index := model.counters.get_value(CounterTypes.Counter.MELEE_SWINGS)
	_swing = combo[attack_index % combo.size()]
	_swing_mirrored = data.alternate_swing_sides and (attack_index % 2 == 1)
	_swing_snapshot = shot
	_swing_time = 0.0
	_swing_duration = _swing.duration / maxf(0.05, model.stats.get_stat(StatTypes.Stat.ATTACK_SPEED))
	_swing_hits.clear()

	model.counters.add(CounterTypes.Counter.MELEE_SWINGS)
	if wielder.model != null:
		wielder.model.counters.add(CounterTypes.Counter.MELEE_SWINGS)

func _advance_swing(delta: float) -> void:
	var previous := _swing_time / _swing_duration
	_swing_time += delta
	var current := _swing_time / _swing_duration

	# Sub-frame sampling. A fast swing moves the hitbox tens of pixels between
	# frames and a thin enemy would fall straight through the gap.
	var samples := _swing.sweep_samples
	for i in samples:
		var t := lerpf(previous, current, float(i + 1) / float(samples))
		if _swing.is_active(t):
			_check_swing_overlap(t)

	if current >= 1.0:
		_swing = null
		_swing_snapshot = null

func _check_swing_overlap(t: float) -> void:
	if _swing.max_targets > 0 and _swing_hits.size() >= _swing.max_targets:
		return

	var reach_scale := maxf(0.1, model.stats.get_stat(StatTypes.Stat.RANGE) / 100.0)
	var centre := global_position + _swing.offset_at(t, _swing_mirrored).rotated(rotation) * reach_scale
	var radius := _swing.hitbox_radius

	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Actor
		if enemy == null or enemy.model == null or not enemy.model.is_alive:
			continue
		if _swing_hits.has(enemy.model):
			continue

		var hit_range := radius + enemy.data.collider_radius
		if centre.distance_squared_to(enemy.global_position) > hit_range * hit_range:
			continue

		_land_swing_hit(enemy, centre)
		if _swing.max_targets > 0 and _swing_hits.size() >= _swing.max_targets:
			return

func _land_swing_hit(enemy: Actor, from: Vector2) -> void:
	# Cleave taper: each additional enemy in the same swing takes a share of
	# what the previous one did. Above 1.0 it rewards hitting a crowd instead.
	var retained := pow(_swing.cleave_retained, float(_swing_hits.size()))
	_swing_hits.append(enemy.model)

	var damage := _swing_snapshot.to_damage_event(0.0, retained)
	enemy.model.apply_damage(damage)

	if _swing.knockback > 0.0:
		enemy.impulse += (enemy.global_position - from).normalized() * _swing.knockback

func _draw() -> void:
	var heat := model.heat_ratio() if model != null else 0.0
	var color := Color(0.85, 0.85, 0.9).lerp(Color(1.0, 0.35, 0.2), heat)

	if _swing == null:
		draw_line(Vector2.ZERO, Vector2.RIGHT * 14.0, color, 3.0)
		return

	# Placeholder blade: a line out to the hitbox, brightening once it is live.
	var t := clampf(_swing_time / _swing_duration, 0.0, 1.0)
	var reach_scale := maxf(0.1, model.stats.get_stat(StatTypes.Stat.RANGE) / 100.0)
	var tip := _swing.offset_at(t, _swing_mirrored) * reach_scale
	var live := _swing.is_active(t)
	draw_line(Vector2.ZERO, tip, color if not live else Color(1.0, 0.95, 0.7), 3.0)
	if live:
		draw_circle(tip, _swing.hitbox_radius, Color(1.0, 0.95, 0.7, 0.25))
