class_name Character
extends Actor

## ONE scene for every playable character. There is no Medic.tscn - identity
## comes from CharacterData.tres: sprite, collider, base stats and the innate
## effect list.

var motion: MotionSource = MotionSource.Device.new(-1)
var player_index: int = 0

func _ready() -> void:
	placeholder_color = Color(0.35, 0.78, 1.0)
	super()

	# The hurtbox is what enemy hitboxes look for; it mirrors the body radius.
	var circle := CircleShape2D.new()
	circle.radius = data.collider_radius if data != null else 8.0
	($Hurtbox/CollisionShape2D as CollisionShape2D).shape = circle

func _get_move_direction(_delta: float) -> Vector2:
	var direction := motion.get_direction()
	return direction.normalized() if direction.length() > 1.0 else direction
