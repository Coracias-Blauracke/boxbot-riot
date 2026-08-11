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

## Which side of the fight something is on - the ONE vocabulary core/ has for it.
##
## The view speaks two others and needs both: a SceneTree group, because that is
## how a weapon finds what to aim at, and a physics layer, because that is how an
## Area2D finds what to collide with. Neither is available to core/, and core/ has
## to answer "who does this explosion hurt" without either.
##
## All three are DERIVED from one declaration in Actor._join_faction, so they
## cannot drift apart. Before that they were four separate lines in two
## subclasses, which is four chances to write "players" and mean "enemies".
##
## NEUTRAL keeps "everything has a side" true for what belongs to neither - the
## arena model, a destructible crate, a weapon model - without making it
## everybody's enemy. Nothing is ever hostile OR allied to it.
enum Faction {
	NEUTRAL,
	PLAYERS,
	ENEMIES,
}

static func are_hostile(a: Faction, b: Faction) -> bool:
	if a == Faction.NEUTRAL or b == Faction.NEUTRAL:
		return false
	return a != b

## Deliberately NOT `not are_hostile()`. Two neutrals are not comrades, they are
## simply not in the fight, and an area effect that heals allies must not sweep
## up every crate in the arena.
static func are_allied(a: Faction, b: Faction) -> bool:
	if a == Faction.NEUTRAL or b == Faction.NEUTRAL:
		return false
	return a == b

## Keys for discrete world-level overrides handled by WorldOverrides.
## Only WORLD-scoped discrete choices belong here - anything per-player
## (shop payment, weapon slots) cannot conflict and must not be registered.
const OVERRIDE_MAP_SHAPE := &"map_shape"
