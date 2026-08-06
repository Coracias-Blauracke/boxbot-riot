class_name Character
extends Actor

## ONE scene for every playable character. There is no Medic.tscn - identity
## comes from CharacterData.tres: sprite, collider, base stats and the innate
## effect list.

## Which physical device owns this player, for BOTH walking and menus. Assigned
## by the spawner; see PlayerInput for why it cannot be derived from the index.
var input: PlayerInput = PlayerInput.new(PlayerInput.KEYBOARD, true)

## How this character decides where to walk. Normally reads `input`; the capture
## runs swap in MotionSource.Scripted, which is why the two are separate - a
## scripted walk must not cost the player their shop controls.
var motion: MotionSource = MotionSource.FromInput.new(input)

var player_index: int = 0

func _ready() -> void:
	# Same table the HUD panel uses, so the blob on the floor and the corner
	# describing it are the same colour. player_index is assigned by the spawner
	# before add_child(), so it is already correct here.
	placeholder_color = PlayerPalette.color_for(player_index)
	super()

	# What enemies search when picking whom to chase.
	add_to_group(&"players")

	# The hurtbox is what enemy hitboxes look for; it mirrors the body radius.
	var circle := CircleShape2D.new()
	circle.radius = data.collider_radius if data != null else 8.0
	($Hurtbox/CollisionShape2D as CollisionShape2D).shape = circle

	# The rack follows the model from here on, so a weapon bought in the shop
	# appears in the hands with nothing else told about it.
	if model != null:
		model.weapons_changed.connect(_on_weapons_changed)
		_on_weapons_changed()

func _get_move_direction(_delta: float) -> Vector2:
	var direction := motion.get_direction()
	return direction.normalized() if direction.length() > 1.0 else direction

func _on_weapons_changed() -> void:
	($WeaponMount as WeaponMount).sync(self)

func get_weapons() -> Array[Weapon]:
	return ($WeaponMount as WeaponMount).get_weapons()

# --- being downed ----------------------------------------------------------
#
# A downed player is NOT freed, which is where this parts company with Actor.
# The model stays in the run holding its currency, its items and its panel, and
# RunTypes.DeathRule decides whether it ever stands up again. queue_free() here
# would take all of that with it and make a revive impossible.

func _on_model_died() -> void:
	_set_downed(true)

func _on_model_revived() -> void:
	_set_downed(false)

func _set_downed(downed: bool) -> void:
	velocity = Vector2.ZERO
	impulse = Vector2.ZERO

	# Dropping the hurtbox is what actually ends contact damage. The enemy
	# ContactHitbox monitors this layer, so switching it off fires area_exited
	# and the enemy forgets the corpse, instead of keeping it in `_touching`
	# and re-checking is_alive every 0.6s for the rest of the wave.
	($Hurtbox as Area2D).set_deferred(&"monitorable", not downed)

	# The weapons stop themselves (see Weapon._physics_process); hiding the mount
	# is only so a corpse is not left ringed by floating blades.
	($WeaponMount as Node2D).visible = not downed
	queue_redraw()
