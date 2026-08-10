class_name OrbitBehavior
extends MovementBehavior

## Closes to a PREFERRED DISTANCE and then circles, instead of walking into you.
##
## The movement a ranged enemy needs, and the first one that gives the player's
## MOVEMENT_SPEED and RANGE anything to do: everything in the game so far walks
## straight at you, so outrunning it and outranging it were the same act.
##
## Three bands rather than two. Closing and backing off are obvious; the RING
## between them is what stops the enemy juddering in place at exactly the
## preferred distance, flipping between "too near" and "too far" every frame.

## Where it wants to stand. Its weapon's range should comfortably exceed this,
## or it spends the fight walking in to shoot and out again.
@export var preferred_distance: float = 220.0

## Half-width of the band it is content in. Inside it the enemy only circles.
@export var tolerance: float = 40.0

## How hard it circles while in the band, relative to closing. 0 makes it stand
## still at range, which reads as a turret rather than a skirmisher.
@export_range(0.0, 1.0) var strafe_weight: float = 1.0

## Which way round it circles. Authored rather than random so two of them do not
## smear into a cloud - and flipping it on a second .tres is a different enemy
## for no code at all.
@export var clockwise: bool = false

func get_direction(_host: Variant, self_position: Vector2, target_position: Vector2, _delta: float) -> Vector2:
	var offset := target_position - self_position
	var distance := offset.length()
	if distance <= 0.001:
		return Vector2.ZERO

	var towards := offset / distance
	var strafe := Vector2(-towards.y, towards.x) * (-1.0 if clockwise else 1.0)

	if distance > preferred_distance + tolerance:
		return towards
	if distance < preferred_distance - tolerance:
		# Backing off still carries some of the circle, so a swarm of them does
		# not collapse into a line retreating along one axis.
		return (-towards + strafe * strafe_weight * 0.5).normalized()

	return strafe * strafe_weight if strafe_weight > 0.0 else Vector2.ZERO
