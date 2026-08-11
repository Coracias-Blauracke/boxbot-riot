class_name Enemy
extends Actor

## ONE scene for every enemy and every boss. Variety comes from EnemyData:
## a swappable MovementBehavior on one axis, dynamic effects on the other.

var behavior: MovementBehavior

## THIS enemy's copy of whatever its behaviour needs to remember - a charger's
## phase and its clock. Owned here rather than by the behaviour, because the
## behaviour is a .tres shared by every enemy carrying it: a phase kept there
## would have the whole wave winding up together. Same split as EffectInstance.
var movement_state := MovementState.new()

## Chosen from the players group rather than assigned once, because in local
## co-op there are up to four of them and they move apart.
var target: Node2D

## Retargeting every frame for a few hundred enemies is wasted work, and
## flip-flopping between two equidistant players looks like indecision.
const RETARGET_INTERVAL := 0.25
var _retarget_timer: float = 0.0

var _contact_interval: float = 0.6
var _contact_timer: float = 0.0
var _touching: Array[Actor] = []

var _separation_radius: float = 0.0
var _separation_weight: float = 0.0

@onready var _hitbox: Area2D = $ContactHitbox
@onready var _separation: Area2D = $SeparationArea

func _ready() -> void:
	placeholder_color = Color(1.0, 0.42, 0.36)
	super()

	# The group weapons find targets through, the group a bug that carries one
	# shoots at, its attack layers and its model's side - see Actor._join_faction.
	_join_faction(WorldTypes.Faction.ENEMIES)

	var radius: float = data.collider_radius if data != null else 8.0
	var enemy_data := data as EnemyData
	if enemy_data != null:
		behavior = enemy_data.movement
		_contact_interval = enemy_data.contact_damage_interval
		_separation_radius = radius * enemy_data.separation_radius_scale
		_separation_weight = enemy_data.separation_weight
		_apply_body_solidity(enemy_data.collides_with_enemies)

	var hit_shape := CircleShape2D.new()
	hit_shape.radius = radius
	($ContactHitbox/CollisionShape2D as CollisionShape2D).shape = hit_shape

	var separation_shape := CircleShape2D.new()
	separation_shape.radius = maxf(_separation_radius, 1.0)
	($SeparationArea/CollisionShape2D as CollisionShape2D).shape = separation_shape

	# What projectiles look for.
	var hurt_shape := CircleShape2D.new()
	hurt_shape.radius = radius
	($Hurtbox/CollisionShape2D as CollisionShape2D).shape = hurt_shape

	_hitbox.area_entered.connect(_on_hitbox_area_entered)
	_hitbox.area_exited.connect(_on_hitbox_area_exited)

	# A bug spits out of itself: no visible weapon, and the mount collapsed onto
	# the body so the shot leaves the creature rather than a barrel beside it.
	# The weapon still fires - hiding a node does not stop it processing, which
	# is the same thing character.gd relies on for a downed player.
	var mount := $WeaponMount as WeaponMount
	if enemy_data != null and not enemy_data.weapons_visible:
		mount.radius = 0.0
		mount.visible = false

	# The same view-of-the-model the players use. An armed bug gets its weapons
	# from EnemyData.weapons through EntityModel, so nothing here knows whether
	# it is holding one.
	if model != null:
		model.weapons_changed.connect(_on_weapons_changed)
		_on_weapons_changed()

## Solid to the rest of the horde, or not part of that argument at all.
##
## BOTH SIDES of it, which is why the LAYER moves and not only the mask: clearing
## the mask alone would let this one walk through the swarm while the swarm still
## piled against it, and something that blocks what it cannot see is how bodies
## end up wedged inside each other.
##
## The layer is used for nothing else - the player masks Environment only, and
## projectiles find their targets through hurtboxes - so dropping it is safe and
## costs one less body in every other enemy's broadphase.
func _apply_body_solidity(solid: bool) -> void:
	if solid:
		collision_layer |= LAYER_ENEMY_BODY
		collision_mask |= LAYER_ENEMY_BODY
	else:
		collision_layer &= ~LAYER_ENEMY_BODY
		collision_mask &= ~LAYER_ENEMY_BODY

func _on_weapons_changed() -> void:
	($WeaponMount as WeaponMount).sync(self)

func get_weapons() -> Array[Weapon]:
	return ($WeaponMount as WeaponMount).get_weapons()

func _get_move_direction(delta: float) -> Vector2:
	_retarget_timer -= delta
	if _retarget_timer <= 0.0 or target == null or not is_instance_valid(target):
		_retarget_timer = RETARGET_INTERVAL
		target = _nearest_player()

	if behavior == null or target == null:
		return Vector2.ZERO

	var steer := behavior.get_direction(
		model, global_position, target.global_position, delta, movement_state
	)
	var combined := steer + _separation_direction() * _separation_weight
	if combined.length() <= 0.001:
		return Vector2.ZERO

	# The behaviour's LENGTH is how much of its speed it is asking for - see
	# MovementBehavior. Normalising it away, which is what this line used to do,
	# meant every enemy moved flat out in whatever direction it was pointed: a
	# skirmisher backed off exactly as fast as it closed in, and no amount of
	# authoring could say otherwise.
	#
	# A behaviour asking for nothing at all still gets moved by crowd separation,
	# at full speed, exactly as before - otherwise an enemy that decides to stand
	# still could never be pushed out of a pile.
	var steer_length := steer.length()
	var share := 1.0 if steer_length <= 0.001 else minf(1.0, steer_length)
	return combined.normalized() * share

## Nearest LIVING player. A dead one must stop attracting the horde, or in co-op
## the swarm would pile onto a corpse while the survivors are ignored.
func _nearest_player() -> Node2D:
	var best: Node2D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Actor
		if player == null or player.model == null or not player.model.is_alive:
			continue
		var distance := global_position.distance_squared_to(player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = player
	return best

## Pushes away from nearby enemies, with the push fading to nothing at the edge
## of the separation radius. Without this a swarm converges on one point and
## literally merges into a single dot.
func _separation_direction() -> Vector2:
	if _separation_radius <= 0.0:
		return Vector2.ZERO

	var push := Vector2.ZERO
	for area in _separation.get_overlapping_areas():
		var other := area.get_parent() as Node2D
		if other == self or other == null:
			continue

		var offset := global_position - other.global_position
		var distance := offset.length()

		if distance <= 0.001:
			# Exactly coincident: normalized() would return zero and the pair
			# would stay welded together forever. Push apart along a stable
			# per-instance angle so the two pick opposite directions.
			push += Vector2.RIGHT.rotated(float(get_instance_id() % 360) * (TAU / 360.0))
			continue

		push += offset.normalized() * (1.0 - clampf(distance / _separation_radius, 0.0, 1.0))

	return push

## Enemies get ON_TICK too, and only when something is actually listening.
##
## RunModel.advance_wave raises it on every PLAYER once a frame, which is where
## regeneration and "for each burning enemy" live. Nothing ever did the same for
## the horde, so an enemy effect on a SCHEDULE - a hive's clock - had no
## heartbeat to hang on at all and could not have been authored.
##
## It lives on Enemy rather than on Actor deliberately: players already get
## theirs from the run, and doing it here as well would tick every player's
## regeneration twice - the same trap Actor.tick_statuses documents.
##
## The guard is not an optimisation of the dispatch, it is an optimisation of the
## PAYLOAD: seventy enemies would otherwise allocate a TickEvent every frame to
## hand it to nothing.
func _tick_effects(delta: float) -> void:
	if model == null or not model.listens_for(Hooks.Hook.ON_TICK):
		return

	var tick := TickEvent.new()
	tick.delta = delta
	tick.census = model.get_census()
	model.notify(Hooks.Hook.ON_TICK, tick)

func _physics_process(delta: float) -> void:
	super(delta)
	if model == null or not model.is_alive:
		return

	_tick_effects(delta)

	# ONE LINE, and it is the whole telegraph's picture: the behaviour says how
	# far through committing it is, ActorTint says what that looks like. Any other
	# enemy can drive the same tint from anything it knows - a boss phase, a
	# status - without either side learning about the other.
	#
	# The MECHANIC is the enemy standing still, which ChargeBehavior does by
	# returning nothing. That is what makes the attack readable with no art at
	# all; this only makes it louder.
	tint.sustain = movement_state.windup

	_contact_timer -= delta
	if _contact_timer <= 0.0 and not _touching.is_empty():
		_contact_timer = _contact_interval
		for victim in _touching:
			_deal_contact_damage(victim)

## Goes through the full damage path, so armor, resistances and on-hit effects
## all apply without this knowing anything about them.
func _deal_contact_damage(victim: Actor) -> void:
	if victim == null or victim.model == null or not victim.model.is_alive:
		return

	var event := DamageEvent.new()
	event.source = model
	event.amount = model.stats.get_stat(StatTypes.Stat.MELEE_DAMAGE)
	event.damage_type = StatTypes.DamageType.MELEE
	victim.model.apply_damage(event)

func _on_hitbox_area_entered(area: Area2D) -> void:
	var actor := area.get_parent() as Actor
	if actor != null and not _touching.has(actor):
		_touching.append(actor)
		# Hit immediately on contact; the timer governs repeats only.
		_deal_contact_damage(actor)
		_contact_timer = _contact_interval

func _on_hitbox_area_exited(area: Area2D) -> void:
	var actor := area.get_parent() as Actor
	if actor != null:
		_touching.erase(actor)

# NO _on_model_died OVERRIDE. It existed only to pay the killer on the spot, and
# an enemy no longer pays anybody: it drops, through an EffectSpawn on ON_DEATH
# like any other death effect, and the scrap on the floor is what carries the
# currency. Actor.queue_free() is the whole of what happens now.
