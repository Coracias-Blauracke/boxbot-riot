class_name Pickup
extends Node2D

## Scrap on the floor. Sits where it fell, flies at a player who gets close
## enough, and reports its value when it arrives.
##
## NO Area2D and no physics layer, deliberately. It has to measure the distance
## to every player anyway - that is what PICKUP_RANGE is - so collection is the
## same measurement with a smaller number rather than a second mechanism that can
## disagree with the first.
##
## It knows nothing about whose currency it becomes. That is a run rule and lives
## in RunModel.credit_pickup; this only says "somebody reached me, I was worth
## this much" and lets the composition root route it.

signal collected(value: int)

var data: PickupData

var _taken: bool = false

func setup(p_data: PickupData) -> void:
	data = p_data

func _physics_process(delta: float) -> void:
	if data == null or _taken:
		return

	var target := _closest_interested_player()
	if target == null:
		queue_redraw()
		return

	var offset := target.global_position - global_position
	var reach := data.collider_radius + (target.data.collider_radius if target.data != null else 0.0)
	if offset.length() <= reach:
		_take()
		return

	global_position += offset.normalized() * data.magnet_speed * delta
	queue_redraw()

## The nearest player who can actually reach it: either standing on it, or with a
## PICKUP_RANGE wide enough to pull it in.
##
## Read off the player's stat every frame rather than cached, so an item bought
## in the shop widens the magnet with nothing else wired - the same reason Actor
## reads MOVEMENT_SPEED live.
func _closest_interested_player() -> Actor:
	var best: Actor = null
	var best_distance := INF

	for node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Actor
		if player == null or player.model == null or not player.model.is_alive:
			continue

		var distance := global_position.distance_to(player.global_position)
		# The floor is the two radii touching, so a player with no PICKUP_RANGE
		# at all still collects by walking over it. The stat only ever widens.
		# The pickup's own reach plus whatever the player adds. Additive, so the
		# stat is an upgrade on a loop that already works rather than the thing
		# that makes it work at all.
		var pull := data.base_magnet + player.model.stats.get_stat(StatTypes.Stat.PICKUP_RANGE)
		var reach := data.collider_radius + player.data.collider_radius + maxf(0.0, pull)
		if distance > reach or distance >= best_distance:
			continue

		best_distance = distance
		best = player

	return best

## Guarded, because the magnet can close the gap on the same frame something else
## frees this - and paying twice for one piece of scrap is the kind of bug that
## only shows up as an economy that drifts.
func _take() -> void:
	if _taken:
		return
	_taken = true
	collected.emit(data.value)
	queue_free()

func _draw() -> void:
	if data == null:
		return

	var radius := data.collider_radius
	draw_circle(Vector2.ZERO, radius, data.color)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 16, data.color.darkened(0.45), 1.5)
