class_name Character
extends Actor

## ONE scene for every playable character. There is no Medic.tscn - identity
## comes from CharacterData.tres: sprite, collider, base stats and the innate
## effect list.

## Keyboard and the first gamepad both drive player 1. Additional players get
## their own MotionSource.Device with the device_id they joined on.
var motion: MotionSource = MotionSource.Combined.new(
	[MotionSource.Device.new(-1), MotionSource.Device.new(0)] as Array[MotionSource]
)
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

func equip(weapon_data: WeaponData) -> Weapon:
	return ($WeaponMount as WeaponMount).equip(weapon_data, self)

func get_weapons() -> Array[Weapon]:
	return ($WeaponMount as WeaponMount).get_weapons()
