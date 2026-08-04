class_name Actor
extends CharacterBody2D

## Shared view logic for anything that walks around: players, enemies, later
## turrets and destructibles.
##
## NOTE the distinction from what was rejected earlier. Scene inheritance per
## VARIANT (Medic.tscn extending Character.tscn) is out - 40 characters do not
## get 40 scenes. SCRIPT inheritance by RESPONSIBILITY is fine and is what this
## is: it has none of the fragility of inherited scenes, because there is no
## node tree to get out of sync.
##
## The node never creates its own model. A spawner builds the model and injects
## it here, so the model stays the authority and the view merely reads it.

var model: EntityModel
var data: EntityData
var world: WorldModel

var placeholder_color: Color = Color.WHITE

@onready var _shape: CollisionShape2D = $CollisionShape2D

func bind(p_model: EntityModel, p_data: EntityData, p_world: WorldModel) -> void:
	model = p_model
	data = p_data
	world = p_world

	if not model.died.is_connected(_on_model_died):
		model.died.connect(_on_model_died)

func _ready() -> void:
	if data != null:
		var circle := CircleShape2D.new()
		circle.radius = data.collider_radius
		_shape.shape = circle
	queue_redraw()

func _physics_process(delta: float) -> void:
	if model == null or not model.is_alive:
		return

	# Speed is read from the model every frame rather than cached, so a slow
	# status or a speed item takes effect immediately with no wiring.
	var direction := _get_move_direction(delta)
	velocity = direction * model.stats.get_stat(StatTypes.Stat.MOVEMENT_SPEED)
	move_and_slide()

	if world != null:
		global_position = world.clamp_to_bounds(global_position)

	# Each actor advances its own statuses. RunModel.tick() exists for headless
	# tests; calling both would tick players twice.
	model.tick_statuses(delta)

	queue_redraw()

## Overridden by subclasses: input for players, a MovementBehavior for enemies.
func _get_move_direction(_delta: float) -> Vector2:
	return Vector2.ZERO

func _on_model_died() -> void:
	queue_free()

# --- placeholder rendering -------------------------------------------------
#
# Drawn rather than sprited so the slice needs no art at all. Size comes from
# EntityData, so swapping in real sprites later is a data change.

func _draw() -> void:
	if data == null:
		return

	var radius := data.collider_radius
	draw_circle(Vector2.ZERO, radius, placeholder_color)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, placeholder_color.darkened(0.5), 2.0)

	if model == null:
		return

	var maximum := model.get_max_hp()
	if maximum <= 0.0:
		return

	var bar_width := radius * 2.0
	var bar_top := -radius - 8.0
	var ratio := clampf(model.current_hp / maximum, 0.0, 1.0)
	draw_rect(Rect2(Vector2(-radius, bar_top), Vector2(bar_width, 3.0)), Color(0, 0, 0, 0.6))
	draw_rect(
		Rect2(Vector2(-radius, bar_top), Vector2(bar_width * ratio, 3.0)),
		Color(0.3, 0.9, 0.4) if ratio > 0.3 else Color(0.9, 0.4, 0.3)
	)
