class_name WorldCensus
extends RefCounted

## Live counts of what is in the world right now, for effects of the shape
## "+1% attack speed for each burning enemy".
##
## DERIVED FROM TRUTH, NOT MAINTAINED BY SIGNALS. An incremental counter that
## goes up on apply and down on expiry breaks permanently and silently the first
## time an event is missed - a target cleared by clear_all(), an enemy freed with
## a status still on it - and afterwards reports three burning enemies when the
## screen is empty. Nothing detects that. Recomputing cannot drift.
##
## The cost is a walk over the entities, which is why every answer is cached for
## the current generation: twenty items asking the same question in one frame
## pay for one walk, not twenty.
##
## Deliberately does NOT answer questions somebody else already answers.
## RunModel knows the players and living_player_count(); duplicating that here
## would create two counts that eventually disagree, which is the same class of
## silent bug this design exists to avoid.

## WeakRef, so an enemy freed with its node simply vanishes from the census at
## the next recount. There is no unregister() and there cannot be one forgotten.
var _entities: Array[WeakRef] = []

var _generation: int = 0
var _cached_generation: int = -1
var _live: Array[EntityModel] = []

## Called by the spawner, where the model is created anyway.
func register(entity: EntityModel) -> void:
	if entity == null:
		return
	_entities.append(weakref(entity))
	# Handed back weakly so an effect firing on ON_DEATH can still ask what is
	# nearby. Weak in both directions, so nothing here can keep anything alive.
	entity.set_census(self)

## Invalidates the per-frame cache. Called once per tick by the run.
func invalidate() -> void:
	_generation += 1

func count_alive() -> int:
	return _living().size()

func count_with_status(status_id: StringName) -> int:
	var total := 0
	for entity in _living():
		if entity.statuses.has(status_id):
			total += 1
	return total

## For "deals more damage to anything carrying two or more statuses".
func count_with_at_least(status_count: int) -> int:
	var total := 0
	for entity in _living():
		if entity.statuses.get_all().size() >= status_count:
			total += 1
	return total

## Everything alive within `radius` of a point, for effects that reach outwards -
## fire jumping off a corpse, an explosion, a chain.
##
## Works only because EntityModel carries its world_position as plain data. That
## is the same trick SpawnContext uses: a Vector2 handed down from the view stops
## being a scene fact and becomes a number core/ may reason about.
func entities_within(centre: Vector2, radius: float, exclude: EntityModel = null) -> Array[EntityModel]:
	var found: Array[EntityModel] = []
	var limit := radius * radius
	for entity in _living():
		if entity == exclude:
			continue
		if entity.world_position.distance_squared_to(centre) <= limit:
			found.append(entity)
	return found

## Rebuilt at most once per generation, dropping anything that has been freed.
## The pruning is the point: it makes a stale entry impossible rather than
## unlikely.
func _living() -> Array[EntityModel]:
	if _cached_generation == _generation:
		return _live

	_live = []
	var surviving: Array[WeakRef] = []

	for held in _entities:
		var entity := held.get_ref() as EntityModel
		if entity == null:
			continue
		surviving.append(held)
		if entity.is_alive:
			_live.append(entity)

	_entities = surviving
	_cached_generation = _generation
	return _live
