class_name WorldData
extends EntityData

## An arena definition. The map is an EntityData like everything else, which is
## what makes "+30% map size" an ordinary StatModifier rather than a special
## case wired through its own system.

## Half-extents at MAP_SIZE == 1.0, in world units.
@export var base_extents: Vector2 = Vector2(480.0, 270.0)

@export var default_shape: WorldTypes.MapShape = WorldTypes.MapShape.RECTANGLE
