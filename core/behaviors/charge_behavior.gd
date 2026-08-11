class_name ChargeBehavior
extends MovementBehavior

## Closes, STOPS DEAD, then throws itself in a straight line.
##
## The first enemy in the game that has to be DODGED rather than out-walked.
## Everything else either walks at you, keeps its distance or stands still, so
## every one of them is answered by moving away; a charge is answered by moving
## ASIDE, and only if you saw it coming.
##
## THE WIND-UP IS THE WHOLE DESIGN. Without it this is a cheap shot: something
## crosses 300 units in half a second with no warning and there was never a
## decision to make. The stop is what turns it into one, and the stop is a
## MECHANIC rather than a decoration - it works with no art at all, because a
## thing that was moving and is suddenly not is the loudest signal in a top-down
## game. What the view adds on top (a flash, a shiver) only makes it louder.
##
## THE FIRST BEHAVIOUR WITH STATE, which is why MovementState exists: a .tres is
## shared by every enemy carrying it, so a phase kept on the resource would have
## every charger in the wave winding up on the same clock.

enum Phase {
	APPROACH,
	WINDUP,
	DASH,
	RECOVER,
}

const PHASE := &"charge_phase"
const TIMER := &"charge_timer"
const AIM := &"charge_aim"

@export_group("Approach")

## How near it has to be before it will commit. Its dash reach should comfortably
## exceed this, or it stops just short and charges at nothing.
@export var trigger_distance: float = 260.0

## Share of its speed while walking in. Below 1.0 because MOVEMENT_SPEED is the
## DASH speed - see the note on `dash_speed_share` - so this is the fraction it
## ambles at.
@export_range(0.0, 1.0, 0.05) var approach_speed_share: float = 0.4

@export_group("Charge")

## Seconds of standing still before it commits. THE TELEGRAPH.
##
## Long enough to read and react to, which is the entire point; at 0 this is an
## unfair enemy rather than a hard one.
@export var windup_time: float = 0.7

@export var dash_time: float = 0.55

## Seconds of standing still afterwards. The PUNISH WINDOW - a charge that can be
## repeated instantly is one the player can only ever run from, and this is what
## makes stepping aside and hitting it back the better answer.
@export var recover_time: float = 0.8

## MOVEMENT_SPEED is the enemy's TOP speed and the dash is what runs at it,
## because a speed share is capped at 1 - a behaviour may never ask for more than
## the stat. Authoring it the other way round would need a cap that lets a
## behaviour exceed its own holder's speed, and then a slow status would stop
## meaning what it says.
@export_range(0.1, 1.0, 0.05) var dash_speed_share: float = 1.0

func get_direction(
	host: Variant, self_position: Vector2, target_position: Vector2, delta: float,
	state: MovementState
) -> Vector2:
	if state == null:
		# No state means no phases; walking in is the honest fallback rather than
		# standing still, which would read as a broken enemy.
		return _towards(self_position, target_position) * approach_speed_share

	var phase: int = int(state.get_state(PHASE, Phase.APPROACH))
	var timer: float = float(state.get_state(TIMER, 0.0)) + delta

	match phase:
		Phase.WINDUP:
			if timer >= windup_time:
				_enter(state, Phase.DASH)
				# Committed HERE, at the end of the wind-up: the direction is what
				# the player had the whole telegraph to read. Aiming at the last
				# instant instead would make the wind-up a lie.
				state.set_state(AIM, _towards(self_position, target_position))
				return _aim_of(state) * dash_speed_share

			state.set_state(TIMER, timer)
			# The one place windup is written. Standing still AND saying how far
			# through it is: the stop is the mechanic, the number is what lets the
			# view draw it.
			state.windup = clampf(timer / maxf(0.01, windup_time), 0.0, 1.0)
			return Vector2.ZERO

		Phase.DASH:
			if timer >= dash_time:
				_enter(state, Phase.RECOVER)
				return Vector2.ZERO
			state.set_state(TIMER, timer)
			# Deliberately NOT re-aimed. A dash that tracks is not a dash, it is a
			# fast chase, and stepping aside would do nothing.
			return _aim_of(state) * dash_speed_share

		Phase.RECOVER:
			if timer >= recover_time:
				_enter(state, Phase.APPROACH)
				return _towards(self_position, target_position) * approach_speed_share
			state.set_state(TIMER, timer)
			return Vector2.ZERO

		_:
			if self_position.distance_to(target_position) <= trigger_distance:
				_enter(state, Phase.WINDUP)
				return Vector2.ZERO
			state.set_state(TIMER, timer)
			return _towards(self_position, target_position) * approach_speed_share

## Moving to a phase resets its clock and clears the telegraph, so the view never
## has to guess whether a windup value belongs to the phase it is looking at.
func _enter(state: MovementState, phase: Phase) -> void:
	state.set_state(PHASE, phase)
	state.set_state(TIMER, 0.0)
	state.windup = 0.0

func _towards(from: Vector2, to: Vector2) -> Vector2:
	var offset := to - from
	return offset.normalized() if offset.length() > 0.001 else Vector2.ZERO

func _aim_of(state: MovementState) -> Vector2:
	var aim: Vector2 = state.get_state(AIM, Vector2.ZERO)
	return aim
