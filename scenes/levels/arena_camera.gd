class_name ArenaCamera
extends Camera2D

## Frames the whole arena, refitting whenever the arena changes size.
##
## A fixed zoom cannot work here: MAP_SIZE is a stat, so a character effect can
## grow the arena mid-run, and in co-op two players carrying that effect stack
## it. At the base resolution a fixed zoom overflowed the screen at only +20%.
##
## Deliberately frames the ARENA rather than following a player: local co-op has
## one shared screen, so everything has to stay in view at once.

## World units kept clear around the arena edge, so the wall is not flush
## against the screen border.
@export var margin: float = 48.0

## Guards against a pathological arena zooming in so far that nothing reads.
@export var max_zoom: float = 3.0

var world: WorldModel

func bind(p_world: WorldModel) -> void:
	world = p_world
	if not world.bounds_changed.is_connected(refit):
		world.bounds_changed.connect(refit)
	refit()

func refit() -> void:
	if world == null:
		return

	var visible_size := (world.get_extents() + Vector2.ONE * margin) * 2.0
	if visible_size.x <= 0.0 or visible_size.y <= 0.0:
		return

	var viewport := get_viewport_rect().size

	# Godot 4 zoom is a magnification: to fit a world span into the viewport,
	# scale by viewport / span. The smaller axis wins so nothing is cut off.
	var fit := minf(viewport.x / visible_size.x, viewport.y / visible_size.y)
	zoom = Vector2.ONE * minf(fit, max_zoom)
