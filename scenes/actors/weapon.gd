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

	if _target != null:
		rotation = (_target.global_position - global_position).angle()

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
		projectile.launch(data.projectile, shot, direction, pierce, bounce, speed_multiplier)
		projectile.global_position = global_position
		# Parented to the level, not the weapon: a bullet must not follow the
		# barrel once it has left it.
		wielder.get_parent().add_child(projectile)

func _draw() -> void:
	# Placeholder: a stub pointing where the weapon aims, tinted by heat.
	var heat := model.heat_ratio() if model != null else 0.0
	var color := Color(0.85, 0.85, 0.9).lerp(Color(1.0, 0.35, 0.2), heat)
	draw_line(Vector2.ZERO, Vector2.RIGHT * 14.0, color, 3.0)
