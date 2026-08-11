class_name WorldModel
extends EntityModel

## The arena, as pure logic. No nodes, no SceneTree - the scene layer reads this
## and builds colliders to match, never the other way round.
##
## MAP_SIZE is an ordinary stat, so "+30% map size" is an ordinary modifier and
## two players carrying it simply sum. Shape is discrete and lives in
## WorldOverrides, because that is the one thing that can actually conflict.

signal bounds_changed

## Points landing exactly on the rim must count as inside. Enemies spawn on the
## edge, and floating-point error in cos/sin alone is enough to push them a
## fraction outside, which would make the spawner fight the bounds check.
const BOUNDS_EPSILON := 0.001

var base_extents: Vector2 = Vector2(480.0, 270.0)
var shape: WorldTypes.MapShape = WorldTypes.MapShape.RECTANGLE

func _init(data: WorldData = null) -> void:
	super()
	# MAP_SIZE is a multiplier, so its neutral value is 1.0, not 0.0.
	# The source is a plain name, never `self` - the source index holds a strong
	# reference, and a model pointing back at itself would never be freed.
	stats.add_modifier(StatTypes.Stat.MAP_SIZE, StatTypes.Modifier.BASE, 1.0, &"world_base")

	if data != null:
		base_extents = data.base_extents
		shape = data.default_shape

	stats.stat_changed.connect(_on_map_stat_changed)

## LINEAR scaling: +30% grows each edge by 30%, so the playable AREA grows by
## 69%. Deliberate - it matches how the genre reads that number.
func get_scale() -> float:
	return stats.get_stat(StatTypes.Stat.MAP_SIZE)

func get_extents() -> Vector2:
	return base_extents * get_scale()

func get_size() -> Vector2:
	return get_extents() * 2.0

func set_shape(new_shape: WorldTypes.MapShape) -> void:
	if shape == new_shape:
		return
	shape = new_shape
	bounds_changed.emit()

# --- geometry --------------------------------------------------------------
#
# Vector2 is a built-in engine type, not a node, so this stays fully headless.

func is_inside(point: Vector2) -> bool:
	var extents := get_extents()
	match shape:
		WorldTypes.MapShape.CIRCLE:
			var radius := minf(extents.x, extents.y) + BOUNDS_EPSILON
			return point.length_squared() <= radius * radius
		_:
			return (
				absf(point.x) <= extents.x + BOUNDS_EPSILON
				and absf(point.y) <= extents.y + BOUNDS_EPSILON
			)

func clamp_to_bounds(point: Vector2) -> Vector2:
	var extents := get_extents()
	match shape:
		WorldTypes.MapShape.CIRCLE:
			var radius := minf(extents.x, extents.y)
			return point if point.length() <= radius else point.normalized() * radius
		_:
			return Vector2(
				clampf(point.x, -extents.x, extents.x),
				clampf(point.y, -extents.y, extents.y)
			)

func random_point_inside(point_rng: RunRandom) -> Vector2:
	var extents := get_extents()
	match shape:
		WorldTypes.MapShape.CIRCLE:
			var radius := minf(extents.x, extents.y)
			# sqrt keeps the distribution uniform over the disc rather than
			# clustering spawns near the centre.
			var distance := sqrt(point_rng.randf_in(RunRandom.Stream.SPAWNS, 0.0, 1.0)) * radius
			var angle := point_rng.randf_in(RunRandom.Stream.SPAWNS, 0.0, TAU)
			return Vector2(cos(angle), sin(angle)) * distance
		_:
			return Vector2(
				point_rng.randf_in(RunRandom.Stream.SPAWNS, -extents.x, extents.x),
				point_rng.randf_in(RunRandom.Stream.SPAWNS, -extents.y, extents.y)
			)

## Enemies spawn at the rim, so this is the one the wave system actually calls.
func random_point_on_edge(point_rng: RunRandom) -> Vector2:
	var extents := get_extents()
	match shape:
		WorldTypes.MapShape.CIRCLE:
			var angle := point_rng.randf_in(RunRandom.Stream.SPAWNS, 0.0, TAU)
			return Vector2(cos(angle), sin(angle)) * minf(extents.x, extents.y)
		_:
			var horizontal := rng.chance(RunRandom.Stream.SPAWNS, 0.5)
			if horizontal:
				return Vector2(
					point_rng.randf_in(RunRandom.Stream.SPAWNS, -extents.x, extents.x),
					extents.y if rng.chance(RunRandom.Stream.SPAWNS, 0.5) else -extents.y
				)
			return Vector2(
				extents.x if rng.chance(RunRandom.Stream.SPAWNS, 0.5) else -extents.x,
				point_rng.randf_in(RunRandom.Stream.SPAWNS, -extents.y, extents.y)
			)

func _on_map_stat_changed(stat: StatTypes.Stat) -> void:
	if stat == StatTypes.Stat.MAP_SIZE:
		bounds_changed.emit()
