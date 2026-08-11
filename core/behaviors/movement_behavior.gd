@abstract
class_name MovementBehavior
extends Resource

## How an entity decides where to move. Swappable per enemy, exactly like
## effects are swappable per item.
##
## This is the axis that makes enemy variety combinatorial rather than
## class-based: "a chaser that explodes on death" is ChaseBehavior plus
## EffectExplodeOnDeath, with no new class anywhere.
##
## Returns a direction; speed comes from the entity's MOVEMENT_SPEED stat, so
## items and statuses affect enemies for free.
##
## THE LENGTH IS A SPEED SHARE, capped at 1. A behaviour that returns a
## unit-length vector asks for full speed, and a shorter one asks for that
## fraction of it - which is how "backs off more slowly than it advances" and a
## charger's wind-up get said at all. Zero means "I have no opinion", and leaves
## whatever else steers the entity (crowd separation) to move it.
##
## This used to be documented as NORMALISED, and the view enforced that by
## normalising whatever came back. A behaviour could therefore only ever steer,
## never modulate - so a skirmisher that retreats at full speed was not a tuning
## choice, it was the only thing expressible.

## `state` is this holder's own MovementState - never the resource's, because the
## resource is shared by every enemy carrying it. A behaviour with no state to
## keep simply ignores the argument.
@abstract func get_direction(host: Variant, self_position: Vector2, target_position: Vector2, delta: float, state: MovementState) -> Vector2
