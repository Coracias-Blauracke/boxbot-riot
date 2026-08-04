class_name SwingPattern
extends Resource

## The shape of ONE melee attack, described as motion over normalised time.
##
## Procedural rather than keyframed for two reasons: at a hundred-odd weapons,
## hand-authoring AnimationPlayer tracks is hundreds of hours, and a keyframed
## swing cannot scale with ATTACK_SPEED or with a reach item. This does both for
## free.
##
## A slash and a thrust are the SAME system with different motion: in an arc the
## angle sweeps and the reach holds; in a thrust the angle holds and the reach
## shoots out and back. Optional Curve resources override either, and Curve is
## editable by hand in the Inspector - so tuning the feel needs no code.

enum Motion {
	ARC,     ## sweeps through an angle - swords, axes
	THRUST,  ## stabs straight out and back - spears, rapiers
}

@export var motion: Motion = Motion.ARC

@export_group("Shape")
@export var arc_degrees: float = 150.0
## Distance from the mount at full extension. Multiplied by the RANGE stat.
@export var reach: float = 46.0
@export var hitbox_radius: float = 14.0

@export_group("Timing")
## Seconds at ATTACK_SPEED 1.0. Scaled by the stat like everything else.
@export var duration: float = 0.28
## Telegraph before the blow lands. Deals no damage - it is what makes a heavy
## weapon read as heavy rather than just slow.
@export_range(0.0, 0.9) var windup_ratio: float = 0.35

## ANTICIPATION. During the windup the weapon travels BEYOND the start of the
## arc, then sweeps through the whole thing. Without it a swing is a bare
## rotation and reads as sterile no matter how the timing is tuned; with it the
## eye sees the wind-up and the release as one motion.
@export var windup_overshoot_degrees: float = 40.0

## Rotation of the blade itself, on top of where it is positioned. 90 makes the
## edge lead the sweep; 0 keeps it pointing away from the wielder, which is what
## a thrust wants.
@export var blade_tilt_degrees: float = 90.0
@export var tilt_curve: Curve

@export_group("Curves (optional)")
## Override the built-in easing. Null keeps the defaults, which already work.
@export var angle_curve: Curve
@export var reach_curve: Curve

@export_group("Hit rules")
## 0 means a swing may hit everything it touches.
@export var max_targets: int = 0
## Damage retained per additional enemy in one swing. Below 1.0 the swing
## tapers through a crowd; above 1.0 it rewards hitting many at once.
@export_range(0.0, 2.0) var cleave_retained: float = 1.0
@export var knockback: float = 0.0

## Sub-steps checked per frame. A 0.15s swing moves the hitbox tens of pixels
## between frames, and a thin enemy falls straight through the gap - this is a
## correctness setting, not a quality one.
@export_range(1, 16) var sweep_samples: int = 4

## True once the windup is over and the blow is live.
func is_active(t: float) -> bool:
	return t >= windup_ratio and t <= 1.0

## Position of the hitbox centre relative to the mount, at normalised time `t`.
func offset_at(t: float, mirrored: bool) -> Vector2:
	return Vector2.RIGHT.rotated(angle_at(t, mirrored)) * reach_at(t)

func angle_at(t: float, mirrored: bool) -> float:
	if motion == Motion.THRUST:
		return 0.0

	var half := deg_to_rad(arc_degrees) * 0.5
	var overshoot := deg_to_rad(windup_overshoot_degrees)
	var angle: float

	if t < windup_ratio:
		# Winding back past the start of the arc.
		var wind := t / maxf(0.001, windup_ratio)
		angle = lerpf(-half, -half - overshoot, _smoothstep(wind))
	else:
		# Releasing: from the wound-back position through the entire arc.
		var progress := _active_progress(t)
		var eased := (
			angle_curve.sample_baked(progress)
			if angle_curve != null
			else _smoothstep(progress)
		)
		angle = lerpf(-half - overshoot, half, eased)

	return -angle if mirrored else angle

## Rotation of the blade itself. Separate from where the blade IS, so the edge
## can lead the sweep rather than the whole thing sliding around rigidly.
func tilt_at(t: float, mirrored: bool) -> float:
	var progress := _active_progress(t)
	var lead := deg_to_rad(blade_tilt_degrees)

	if tilt_curve != null:
		lead *= tilt_curve.sample_baked(progress)
	elif motion == Motion.ARC:
		# Tilts hardest through the middle of the sweep, easing off at both
		# ends - the blade rolls over rather than staying rigid.
		lead *= 0.6 + 0.4 * sin(PI * progress)

	return angle_at(t, mirrored) + (-lead if mirrored else lead)

func reach_at(t: float) -> float:
	var progress := _active_progress(t)

	if reach_curve != null:
		return reach * reach_curve.sample_baked(progress)

	if t < windup_ratio:
		# Pulling back: the weapon draws in before it goes out.
		var wind := t / maxf(0.001, windup_ratio)
		return reach * lerpf(0.55, 0.35, wind)

	match motion:
		Motion.THRUST:
			# Out and back within the active window.
			return reach * sin(PI * progress)
		_:
			# An arc keeps its extension, bulging slightly at the midpoint.
			return reach * (0.8 + 0.2 * sin(PI * progress))

## 0 during the windup, then 0..1 across the live part of the swing.
func _active_progress(t: float) -> float:
	if t <= windup_ratio:
		return 0.0
	return clampf((t - windup_ratio) / maxf(0.001, 1.0 - windup_ratio), 0.0, 1.0)

## Slow at the ends, fast through the middle - reads as a swing rather than a
## constant sweep.
func _smoothstep(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)
