class_name BlastFlash
extends Node2D

## The placeholder an explosion is drawn as: a disc that swells to the radius
## that actually went off, fading as it goes, and frees itself.
##
## Script-only, with no scene file, because it has no node tree at all - no
## collider, no area, no children. A .tscn wrapping one Node2D would be a file to
## keep in step with nothing.
##
## It knows about BlastEvent and about nothing else. It never touches the model,
## the run or the actor that set it off, so an explosion looks the same whether
## a bug burst, an item detonated a corpse or a grenade landed - which is the
## point of there being one event.

## Short on purpose. An explosion is an instant, and a placeholder that lingers
## reads as a puddle - which is a different mechanic that does not exist yet.
const DURATION := 0.3

## Where the swell starts, as a share of the final radius. Not zero: a blast that
## grows from a point looks like a projectile arriving rather than something
## going off.
const START_SHARE := 0.45

var radius: float = 90.0
var color: Color = Color(1.0, 0.72, 0.3)

var _elapsed: float = 0.0

## Everything it needs, taken from the event and then forgotten. The event holds
## references to models, and a node that lives across frames must not keep those
## alive - the same rule that stops an effect caching a payload.
func setup(event: BlastEvent) -> void:
	radius = event.radius
	if event.blast != null:
		color = event.blast.flash_color
	global_position = event.centre

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	if radius <= 0.0:
		return

	var t := clampf(_elapsed / DURATION, 0.0, 1.0)
	var drawn := radius * lerpf(START_SHARE, 1.0, t)

	# Fades out over its whole life, so the frame it is freed on is already
	# invisible rather than popping.
	var fill := color
	fill.a = 0.35 * (1.0 - t)
	draw_circle(Vector2.ZERO, drawn, fill)

	var rim := color
	rim.a = 0.9 * (1.0 - t)
	draw_arc(Vector2.ZERO, drawn, 0.0, TAU, 32, rim, 2.0)
