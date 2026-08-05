class_name ImpactEvent
extends EventPayload

## Fired when a projectile hits something.
##
## Carries the projectile's own state, because the projectile deliberately has
## no EntityModel of its own. Hundreds can exist at once and allocating four
## managers for each - stats, counters, effects, statuses - to serve a bullet
## that lives half a second would be waste, not uniformity.
##
## ON_IMPACT is therefore dispatched on the SHOOTER, which is also the right
## owner semantically: an explosion belongs to whoever fired it, for kill credit
## and for damage scaling. Anything the effect needs to know about the
## projectile itself is on this event.

var shooter: EntityModel = null
var target: EntityModel = null
var snapshot: ShotSnapshot = null

var position: Vector2 = Vector2.ZERO
var direction: Vector2 = Vector2.RIGHT
var distance_travelled: float = 0.0

## Remaining passes and ricochets. Effects may extend them - "every crit grants
## one extra pierce" needs nothing more than writing here.
var pierce_left: int = 0
var bounce_left: int = 0

## Damage actually dealt to this target, filled in after the target's pipeline.
var damage_dealt: float = 0.0

## Set to true to destroy the projectile regardless of pierces left.
var consume_projectile: bool = false
