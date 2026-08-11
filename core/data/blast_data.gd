class_name BlastData
extends Resource

## An area attack: one centre, one radius, everything inside it takes a hit.
##
## THE ONE DESCRIPTION OF AN EXPLOSION IN THE GAME. A bug that bursts when it
## dies, an item that detonates whatever you kill and a grenade that goes off on
## impact are the same four numbers with different values, so they are one
## resource and one resolver rather than three implementations that drift.
##
## Deliberately NOT a DynamicEffect. An effect answers WHEN something happens;
## this answers WHAT happens, and the two are separate axes for the same reason
## FiringPattern is separate from delivery: one EffectBlast with a trigger covers
## every occasion, and one BlastData covers every shape, so the pair of them
## multiply instead of adding.
##
## Godot caches .tres globally, so nothing here may hold runtime state. resolve()
## therefore writes everything it learns onto the BlastEvent it returns and
## touches no field of its own - the same rule EffectInstance exists to enforce.

## Whose side of the fight a blast reaches, relative to whoever set it off.
##
## Authored rather than assumed, which is how "does a Popper hurt other bugs"
## became a field instead of an argument. It ships on HOSTILE - a horde that
## partly kills itself is a real design lever and an unmeasurable one, and
## turning it on later is this one line.
enum Reach {
	HOSTILE,     ## the other side only. What an explosion normally means.
	ALLIED,      ## own side only - a healing pulse, a bug that feeds its swarm.
	EVERYTHING,  ## friendly fire, the source itself always excluded.
}

@export_group("Shape")

## World units at AREA_SIZE 1.0. The character is 12 units across, so 90 is a
## little over seven bodies wide.
@export var radius: float = 90.0

## Share of the damage still dealt at the very edge, interpolated linearly from
## the full amount at the centre. 1.0 is a flat blast that ignores distance.
##
## The taper is what makes an explosion a POSITION question rather than a radius
## question: standing at the rim has to be worth something, or the only decision
## a blast poses is whether you are inside it.
@export_range(0.0, 1.0, 0.05) var edge_damage_share: float = 0.5

## How many it may catch. 0 is everything inside, which is the normal case; a cap
## takes the NEAREST, because "the three closest" is the only reading a player
## can predict from where they are standing.
@export var max_targets: int = 0

@export_group("Damage")

## Damage at the centre before any stat is added.
@export var base_damage: float = 0.0

## Which stats feed it, and how much of each - the same table WeaponData uses,
## and the same one class for the same reason.
##
## Every entry contributes that stat's VALUE times its coefficient. There is
## deliberately no "own damage type" special case here: a blast has no weapon of
## its own to take a share of the holder's bonuses INTO, so the question that
## rule answers does not arise.
##
## Empty means all of the source's own damage type, which for the default
## ELEMENTAL is what finally makes ELEMENTAL_DAMAGE mean something.
@export var damage_scaling: Array[StatScaling] = []

@export var damage_type: StatTypes.DamageType = StatTypes.DamageType.ELEMENTAL

@export var reach: Reach = Reach.HOSTILE

@export_group("Presentation")

## Read by the view off this resource rather than copied onto the event: a blast
## is authored content and this is one of its authored properties, exactly like
## EntityData.sprite.
@export var flash_color: Color = Color(1.0, 0.72, 0.3)

## Which stat carries a blast's damage when nothing is authored, by damage type.
## TRUE_DAMAGE is absent on purpose - it means "a flat number nothing scales",
## so a scaling stat for it would contradict its own name.
const OWN_DAMAGE_STAT: Dictionary = {
	StatTypes.DamageType.MELEE: StatTypes.Stat.MELEE_DAMAGE,
	StatTypes.DamageType.RANGED: StatTypes.Stat.RANGED_DAMAGE,
	StatTypes.DamageType.ELEMENTAL: StatTypes.Stat.ELEMENTAL_DAMAGE,
	StatTypes.DamageType.BLEED: StatTypes.Stat.BLEED_DAMAGE,
	StatTypes.DamageType.POISON: StatTypes.Stat.POISON_DAMAGE,
	StatTypes.DamageType.BURN: StatTypes.Stat.BURN_DAMAGE,
}

## Works out who is inside, hurts them, and reports what happened.
##
## Called through EntityModel.detonate() rather than directly, so that every
## explosion announces itself the same way; this half is kept here because it is
## the DATA's business how far it reaches and how hard it hits.
##
## `weapon` is the WeaponModel that set it off, when one did: its combined_stat
## is then what the blast reads, so a weapon that withholds crit or area through
## stat_inheritance withholds it here too. `inherited` is the shot that triggered
## it, whose crit outcome this one takes rather than rolling again.
##
## `power` multiplies the authored damage, and is where an effect's stack count
## arrives - a second copy of an exploding item has to be worth something.
func resolve(
	source: EntityModel,
	at: Vector2,
	weapon: WeaponModel = null,
	inherited: ShotSnapshot = null,
	power: float = 1.0
) -> BlastEvent:
	var event := BlastEvent.new()
	event.blast = self
	event.source = source
	event.weapon = weapon
	event.centre = at
	event.damage_type = damage_type

	if source == null:
		return event

	event.radius = maxf(0.0, radius * _stat(source, weapon, StatTypes.Stat.AREA_SIZE))

	var shot := _build_shot(source, weapon, inherited, power)
	event.amount = shot.amount
	event.is_crit = shot.is_crit

	# The census is how core/ does geometry at all. An entity that has none - a
	# model built for a test, or one whose run has gone away - simply hurts
	# nobody, rather than the caller having to check first.
	var census := source.get_census()
	if census == null or event.radius <= 0.0:
		return event

	for target in _targets(source, census, at, event.radius):
		var share := _share_at(at.distance_to(target.world_position), event.radius)
		event.damage_dealt += target.apply_damage(shot.to_damage_event(0.0, share))
		event.victims.append(target)

	return event

## Everything the blast may legitimately hurt, nearest first when it has to
## choose. Sorted only when a cap makes the order matter - a full-radius blast
## hits the same set whatever order it walks it in, and sorting a hundred
## entities per explosion for nothing is the sort of cost that only shows up
## once there are a hundred.
func _targets(
	source: EntityModel, census: WorldCensus, at: Vector2, reach_radius: float
) -> Array[EntityModel]:
	var found: Array[EntityModel] = []
	for candidate in census.entities_within(at, reach_radius, source):
		# The census answers from a cache held for the whole frame, which is what
		# makes twenty questions cost one walk - but a CHAIN of explosions all
		# happens inside one frame, so by the second one that answer already lists
		# the dead. apply_damage refuses a corpse anyway, so the damage was never
		# wrong; what was wrong is that a capped blast spent its three targets on
		# things that were already gone.
		if not candidate.is_alive:
			continue
		if _reaches(source, candidate):
			found.append(candidate)

	if max_targets <= 0 or found.size() <= max_targets:
		return found

	found.sort_custom(
		func(a: EntityModel, b: EntityModel) -> bool:
			return (
				a.world_position.distance_squared_to(at)
				< b.world_position.distance_squared_to(at)
			)
	)
	return found.slice(0, max_targets)

func _reaches(source: EntityModel, target: EntityModel) -> bool:
	match reach:
		Reach.EVERYTHING:
			return true
		Reach.ALLIED:
			return WorldTypes.are_allied(source.faction, target.faction)
		_:
			return WorldTypes.are_hostile(source.faction, target.faction)

## Linear from full at the centre to edge_damage_share at the rim.
func _share_at(distance: float, reach_radius: float) -> float:
	if reach_radius <= 0.0:
		return 1.0
	return lerpf(1.0, edge_damage_share, clampf(distance / reach_radius, 0.0, 1.0))

## Phase 1 of damage for a blast: everything the SOURCE contributes, frozen once
## for the whole explosion.
##
## A ShotSnapshot rather than a shape of its own, because that is exactly what it
## is - one attack that lands on many targets, which is the same thing a shotgun
## blast is. Reusing it means the crit rolls once for the whole explosion, the
## falloff arithmetic is the one already written, and CALCULATE_DAMAGE effects
## reach a blast without knowing blasts exist.
func _build_shot(
	source: EntityModel, weapon: WeaponModel, inherited: ShotSnapshot, power: float
) -> ShotSnapshot:
	var shot := ShotSnapshot.new()
	shot.source = source
	shot.weapon = weapon
	shot.damage_type = damage_type
	shot.amount = _damage_from(source, weapon) * power
	shot.crit_chance = _stat(source, weapon, StatTypes.Stat.CRIT_CHANCE)
	shot.crit_multiplier = _crit_multiplier(source, weapon)

	# The weapon's own effects first, then the wielder's - the order build_shot
	# uses, so a blast and a bullet are modified in the same sequence.
	if weapon != null:
		weapon.pipeline(Hooks.Hook.CALCULATE_DAMAGE, shot)
	source.pipeline(Hooks.Hook.CALCULATE_DAMAGE, shot)

	if inherited != null:
		shot.inherit_crit(inherited)
	else:
		shot.roll_crit(source.rng, weapon, source)
	return shot

## A weapon carries the game's default doubling as a base of its own, so with one
## in the picture there is nothing to add. WITHOUT one, the blast is the weapon,
## and reading the source's bare CRIT_MULTIPLIER would find the neutral 1.0 - a
## crit worth nothing, quietly making CRIT_CHANCE inert on every exploding item.
##
## Multiplied rather than added, which is how WeaponModel.combined_stat shares a
## multiplicative stat: a holder at 1.5 gets x3, on a gun and on a grenade alike.
func _crit_multiplier(source: EntityModel, weapon: WeaponModel) -> float:
	if weapon != null:
		return weapon.combined_stat(StatTypes.Stat.CRIT_MULTIPLIER)
	return (
		StatTypes.DEFAULT_CRIT_MULTIPLIER
		* source.stats.get_stat(StatTypes.Stat.CRIT_MULTIPLIER)
	)

func _damage_from(source: EntityModel, weapon: WeaponModel) -> float:
	if damage_scaling.is_empty():
		if not OWN_DAMAGE_STAT.has(damage_type):
			return base_damage
		var own: StatTypes.Stat = OWN_DAMAGE_STAT[damage_type]
		return base_damage + _stat(source, weapon, own)

	var total := base_damage
	for scaling in damage_scaling:
		if scaling != null:
			total += _stat(source, weapon, scaling.stat) * scaling.coefficient
	return total

## A stat as the blast experiences it. Through the WEAPON when one set it off, so
## its inheritance table applies, and off the source directly otherwise.
func _stat(source: EntityModel, weapon: WeaponModel, stat: StatTypes.Stat) -> float:
	if weapon != null:
		return weapon.combined_stat(stat)
	return source.stats.get_stat(stat)

## For the shop's derived detail block. Deliberately says the RADIUS rather than
## the damage: the damage is already on the entry's own stat lines, and repeating
## it there would be one number in two places.
func describe() -> String:
	return "%d damage in a %d radius" % [roundi(base_damage), roundi(radius)]
