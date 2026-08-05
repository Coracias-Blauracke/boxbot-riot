class_name ArenaCamera
extends Camera2D

## Follows the players across an arena LARGER than the screen.
##
## The arena deliberately does not fit in the viewport - you see a slice of it
## and the rest is out there. That is the genre convention, and it also removes
## the tension the previous fit-the-whole-arena camera had: growing MAP_SIZE
## used to zoom everything out until enemies were unreadable, whereas now
## growth simply means more room.
##
## Local co-op shares one screen, so the frame has to hold every living player.
## It widens as they separate and stops at `min_zoom`, which is what effectively
## limits how far apart they can get - going further would either shrink
## everyone to nothing or drop somebody off the edge.

## Framing when the players are together. Higher means closer in.
@export var default_zoom: float = 1.35

## Furthest the view will pull back when players scatter.
##
## Low enough that players in opposite corners pull the whole arena into frame,
## which is the intended co-op moment: spreading out trades a close view for
## seeing everything at once. It is a floor rather than a target - the camera
## only goes this far if the players actually make it.
@export var min_zoom: float = 0.5

## World units kept clear around the players when the frame widens.
@export var group_margin: float = 260.0

@export var position_smoothing: float = 6.0
@export var zoom_smoothing: float = 3.0

var world: WorldModel

func bind(p_world: WorldModel) -> void:
	world = p_world
	if not world.bounds_changed.is_connected(_apply_limits):
		world.bounds_changed.connect(_apply_limits)
	_apply_limits()
	zoom = Vector2.ONE * default_zoom

func _process(delta: float) -> void:
	var alive := _living_players()
	if alive.is_empty():
		return

	var bounds := _bounds_of(alive)

	# Zoom out only as far as needed to hold everyone, never past min_zoom.
	var needed := bounds.size + Vector2.ONE * group_margin * 2.0
	var viewport := get_viewport_rect().size
	var fit := minf(viewport.x / maxf(1.0, needed.x), viewport.y / maxf(1.0, needed.y))
	var target_zoom := clampf(fit, min_zoom, default_zoom)

	zoom = zoom.lerp(Vector2.ONE * target_zoom, clampf(zoom_smoothing * delta, 0.0, 1.0))
	global_position = global_position.lerp(
		bounds.get_center(), clampf(position_smoothing * delta, 0.0, 1.0)
	)

## World-space rectangle currently on screen. Used by the spawner so enemies
## appear just out of sight rather than at the far wall.
func visible_world_size() -> Vector2:
	return get_viewport_rect().size / maxf(0.01, zoom.x)

func _living_players() -> Array[Node2D]:
	var alive: Array[Node2D] = []
	for node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Actor
		if player != null and player.model != null and player.model.is_alive:
			alive.append(player)
	return alive

func _bounds_of(nodes: Array[Node2D]) -> Rect2:
	var bounds := Rect2(nodes[0].global_position, Vector2.ZERO)
	for i in range(1, nodes.size()):
		bounds = bounds.expand(nodes[i].global_position)
	return bounds

## Camera2D limits stop the view sliding past the arena walls, so a player
## standing in a corner does not get half a screen of emptiness.
func _apply_limits() -> void:
	if world == null:
		return
	var extents := world.get_extents()
	limit_left = int(-extents.x)
	limit_right = int(extents.x)
	limit_top = int(-extents.y)
	limit_bottom = int(extents.y)
