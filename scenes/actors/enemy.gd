class_name Enemy
extends Actor

## ONE scene for every enemy and every boss. Variety comes from EnemyData:
## a swappable MovementBehavior on one axis, dynamic effects on the other.

var behavior: MovementBehavior
var target: Node2D

var _contact_interval: float = 0.6
var _contact_timer: float = 0.0
var _touching: Array[Actor] = []

@onready var _hitbox: Area2D = $ContactHitbox

func _ready() -> void:
	placeholder_color = Color(1.0, 0.42, 0.36)
	super()

	var enemy_data := data as EnemyData
	if enemy_data != null:
		behavior = enemy_data.movement
		_contact_interval = enemy_data.contact_damage_interval

	var circle := CircleShape2D.new()
	circle.radius = data.collider_radius if data != null else 8.0
	($ContactHitbox/CollisionShape2D as CollisionShape2D).shape = circle

	_hitbox.area_entered.connect(_on_hitbox_area_entered)
	_hitbox.area_exited.connect(_on_hitbox_area_exited)

func _get_move_direction(delta: float) -> Vector2:
	if behavior == null or target == null:
		return Vector2.ZERO
	return behavior.get_direction(model, global_position, target.global_position, delta)

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
