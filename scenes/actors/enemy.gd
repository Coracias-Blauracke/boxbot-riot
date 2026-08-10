class_name Enemy
extends Actor

## ONE scene for every enemy and every boss. Variety comes from EnemyData:
## a swappable MovementBehavior on one axis, dynamic effects on the other.

var behavior: MovementBehavior

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

	# Weapons find their targets through this group.
	add_to_group(&"enemies")
	# And a bug that carries one shoots the other way - see Actor.hostile_group.
	hostile_group = &"players"
	attack_layer = LAYER_ENEMY_HITBOX
	attack_mask = LAYER_PLAYER_HURTBOX

	var radius: float = data.collider_radius if data != null else 8.0
	var enemy_data := data as EnemyData
	if enemy_data != null:
		behavior = enemy_data.movement
		_contact_interval = enemy_data.contact_damage_interval
		_separation_radius = radius * enemy_data.separation_radius_scale
		_separation_weight = enemy_data.separation_weight

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

	# The same view-of-the-model the players use. An armed bug gets its weapons
	# from EnemyData.weapons through EntityModel, so nothing here knows whether
	# it is holding one.
	if model != null:
		model.weapons_changed.connect(_on_weapons_changed)
		_on_weapons_changed()

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

	var steer := behavior.get_direction(model, global_position, target.global_position, delta)
	var combined := steer + _separation_direction() * _separation_weight
	return combined.normalized() if combined.length() > 0.001 else Vector2.ZERO

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

func _physics_process(delta: float) -> void:
	super(delta)
	if model == null or not model.is_alive:
		return

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

## Pays out to whoever landed the killing blow. The model records its last
## attacker, so kill credit survives the projectile that did it being freed.
func _on_model_died() -> void:
	var enemy_data := data as EnemyData
	var killer := model.get_last_attacker()
	if enemy_data != null and killer != null:
		killer.add_currency(enemy_data.currency_reward)
	super()
