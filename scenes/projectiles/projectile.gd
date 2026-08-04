class_name Projectile
extends Area2D

## A fired projectile. Deliberately lightweight: it carries the shot snapshot
## rather than owning a model, so a shotgun blast spawns eight of these without
## allocating eight sets of managers.
##
## The snapshot is SHARED with every other projectile from the same shot, which
## is what makes all eight pellets crit together.

var data: ProjectileData
var snapshot: ShotSnapshot
var shooter: EntityModel

var direction: Vector2 = Vector2.RIGHT
var speed: float = 420.0

var pierce_left: int = 0
var bounce_left: int = 0

var _distance: float = 0.0
var _lifetime: float = 2.0
## One projectile must not hit the same enemy twice on the way through.
var _already_hit: Array[EntityModel] = []

@onready var _shape: CollisionShape2D = $CollisionShape2D

func launch(
	p_data: ProjectileData,
	p_snapshot: ShotSnapshot,
	p_direction: Vector2,
	p_pierce: int,
	p_bounce: int,
	speed_multiplier: float
) -> void:
	data = p_data
	snapshot = p_snapshot
	shooter = p_snapshot.source
	direction = p_direction.normalized()
	pierce_left = p_pierce
	bounce_left = p_bounce
	speed = p_data.speed * p_data.speed_scale * speed_multiplier
	_lifetime = p_data.lifetime

func _ready() -> void:
	var circle := CircleShape2D.new()
	circle.radius = data.collider_radius if data != null else 4.0
	_shape.shape = circle
	area_entered.connect(_on_area_entered)
	rotation = direction.angle()

func _physics_process(delta: float) -> void:
	var step := direction * speed * delta
	position += step
	_distance += step.length()

	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	var actor := area.get_parent() as Actor
	if actor == null or actor.model == null or not actor.model.is_alive:
		return
	if _already_hit.has(actor.model):
		return
	_already_hit.append(actor.model)

	_hit(actor.model)

func _hit(target: EntityModel) -> void:
	# Damage tapers as the projectile passes through, so a piercing shot does
	# not mow down a whole line at full power.
	var retained := pow(data.damage_retained_on_pierce, float(_already_hit.size() - 1)) if data != null else 1.0
	var damage := snapshot.to_damage_event(_distance, retained)
	var dealt := target.apply_damage(damage)

	var impact := ImpactEvent.new()
	impact.shooter = shooter
	impact.target = target
	impact.snapshot = snapshot
	impact.position = global_position
	impact.direction = direction
	impact.distance_travelled = _distance
	impact.pierce_left = pierce_left
	impact.bounce_left = bounce_left
	impact.damage_dealt = dealt

	# Dispatched on the shooter: explosions and chains belong to whoever fired.
	if shooter != null:
		shooter.notify(Hooks.Hook.ON_IMPACT, impact)
	_run_projectile_effects(impact)

	# Effects may have granted extra passes.
	pierce_left = impact.pierce_left
	bounce_left = impact.bounce_left

	if impact.consume_projectile:
		queue_free()
		return

	if pierce_left > 0:
		pierce_left -= 1
		return

	if bounce_left > 0:
		bounce_left -= 1
		_bounce()
		return

	queue_free()

## Turns towards another target rather than reflecting off geometry - a ricochet
## that seeks is far more useful in a horde game than a physically accurate one.
func _bounce() -> void:
	var best: Node2D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Actor
		if enemy == null or enemy.model == null or _already_hit.has(enemy.model):
			continue
		var distance := global_position.distance_squared_to(enemy.global_position)
		if distance < best_distance:
			best_distance = distance
			best = enemy

	if best == null:
		queue_free()
		return

	direction = (best.global_position - global_position).normalized()
	rotation = direction.angle()

func _run_projectile_effects(impact: ImpactEvent) -> void:
	if data == null or shooter == null:
		return
	for effect in data.innate_effects:
		if effect == null:
			continue
		# Shared instance per definition; per-projectile state travels on the
		# event rather than in the instance.
		effect.execute(shooter, EffectInstance.new(effect, data), impact)

func _draw() -> void:
	var radius := data.collider_radius if data != null else 4.0
	draw_circle(Vector2.ZERO, radius, Color(1.0, 0.9, 0.5))
