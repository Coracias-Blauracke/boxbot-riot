class_name Arena
extends Node2D

## Draws the arena boundary straight from WorldModel and redraws whenever the
## model says the bounds changed - which is what happens when a character effect
## grows the map mid-run.
##
## The view derives from the model; it never stores its own copy of the size.

var world: WorldModel

func bind(p_world: WorldModel) -> void:
	world = p_world
	if not world.bounds_changed.is_connected(queue_redraw):
		world.bounds_changed.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	if world == null:
		return

	var extents := world.get_extents()
	var floor_color := Color(0.11, 0.12, 0.16)
	var wall_color := Color(0.45, 0.5, 0.62)

	match world.shape:
		WorldTypes.MapShape.CIRCLE:
			var radius := minf(extents.x, extents.y)
			draw_circle(Vector2.ZERO, radius, floor_color)
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 96, wall_color, 3.0)
		_:
			var rect := Rect2(-extents, extents * 2.0)
			draw_rect(rect, floor_color)
			draw_rect(rect, wall_color, false, 3.0)
