class_name ProjectileData
extends EntityData

## A projectile is an EntityModel too, which is what makes "piercing, explosive,
## leaves a puddle" three entries in a list rather than three subclasses.
##
## Piercing and bouncing are ordinary stats (PIERCING, BOUNCING), so items that
## grant them work on every weapon at once. Everything else - explosions,
## lingering areas, chaining - hangs off ON_IMPACT as a normal DynamicEffect in
## `innate_effects`, inherited from EntityData.

@export var speed: float = 420.0
@export var lifetime: float = 2.0

## Multiplies the wielder's PROJECTILE_SPEED, so a slow heavy shell and a fast
## bullet can share the same stat.
@export var speed_scale: float = 1.0

@export_group("Impact")
## Kept when the projectile passes through an enemy, so piercing shots taper off
## instead of mowing down a whole line at full power. 1.0 disables the taper.
@export var damage_retained_on_pierce: float = 1.0
@export var damage_retained_on_bounce: float = 1.0
