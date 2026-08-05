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
## Returns a NORMALISED direction; speed comes from the entity's
## MOVEMENT_SPEED stat, so items and statuses affect enemies for free.

@abstract func get_direction(host: Variant, self_position: Vector2, target_position: Vector2, delta: float) -> Vector2
