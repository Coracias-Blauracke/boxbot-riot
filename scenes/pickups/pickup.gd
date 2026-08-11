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

## Spelled once, here, rather than as a bare string in whoever sweeps the floor
## at the end of a wave.
const GROUP := &"pickups"

signal collected(value: int)

var data: PickupData

var _taken: bool = false

func setup(p_data: PickupData) -> void:
	data = p_data

## Grouped by ITSELF rather than by whoever built it, exactly as an Enemy joins
## its own group in _ready. A node that has to be put into a group by its caller
## is a node that gets missed the second time somebody builds one.
func _ready() -> void:
	add_to_group(GROUP)

func _physics_process(delta: float) -> void:
	if data == null or _taken:
		return

	var target := _closest_interested_player()
	if target == null:
		queue_redraw()
		return

	var offset := target.global_position - global_position
	if offset.length() <= _collect_reach(target):
		_take()
		return

	global_position += offset.normalized() * data.magnet_speed * delta
	queue_redraw()

## Touching distance: the two radii, and nothing else.
##
## Named, because it is asked TWICE - once to decide whether anybody is
## interested and once to decide whether they have arrived - and two spellings of
## one distance is how they end up disagreeing. That is the shape of half the
## bugs written down in CLAUDE.md.
func _collect_reach(player: Actor) -> float:
	var body := player.data.collider_radius if player.data != null else 0.0
	return data.collider_radius + body

## How far this piece will fly to a player: touching distance plus the magnet.
##
## The stat is read off the player every frame rather than cached, so an item
## bought in the shop widens it with nothing else wired - the same reason Actor
## reads MOVEMENT_SPEED live. It ADDS to the pickup's own reach, so the stat is
## an upgrade on a loop that already works rather than the thing that makes it
## work at all.
func _magnet_reach(player: Actor) -> float:
	var pull := data.base_magnet + player.model.stats.get_stat(StatTypes.Stat.PICKUP_RANGE)
	return _collect_reach(player) + maxf(0.0, pull)

## The nearest player who can reach it: standing on it, or with a wide enough
## magnet to pull it in.
func _closest_interested_player() -> Actor:
	var best: Actor = null
	var best_distance := INF

	for node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Actor
		if player == null or player.model == null or not player.model.is_alive:
			continue

		var distance := global_position.distance_to(player.global_position)
		if distance > _magnet_reach(player) or distance >= best_distance:
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
