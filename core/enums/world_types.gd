class_name WorldTypes

## Arena shape. Size and shape are deliberately independent axes: size is a
## continuous stat that sums across players, shape is a discrete choice that
## can genuinely conflict. Same append-only rule as the other enums.
enum MapShape {
	RECTANGLE,
	CIRCLE,
}

enum Phase {
	PREPARING,
	COMBAT,
	SHOP,
	FINISHED,
}

## Keys for discrete world-level overrides handled by WorldOverrides.
## Only WORLD-scoped discrete choices belong here - anything per-player
## (shop payment, weapon slots) cannot conflict and must not be registered.
const OVERRIDE_MAP_SHAPE := &"map_shape"
