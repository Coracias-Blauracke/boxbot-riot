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

## WHICH GROUP THIS ACTOR'S WEAPONS SHOOT AT.
##
## A property of the WIELDER rather than a constant in the weapon, because the
## weapon system is the same one on both sides: EntityModel and WeaponModel are
## already shared between a player and a bug, and the only thing that ever
## differed was a hardcoded &"enemies" in three places - targeting, the melee
## sweep and a projectile's collision. That single constant is what stopped an
## enemy from ever holding a weapon, since it would have shot the other bugs.
##
## Derived from the faction the subclass joins: a Character shoots enemies, an
## Enemy shoots players. Anything that carries a weapon and forgets to join a
## faction hits nothing, which is a great deal louder than hitting its own side.
var hostile_group: StringName = &""

## Which side this actor is on, in the vocabulary core/ understands. The other
## three - the group it joins, the group it hunts, the layers its attacks use -
## are all derived from this one line by _join_faction.
var faction: WorldTypes.Faction = WorldTypes.Faction.NEUTRAL

## The physics layers named in project.godot, spelled once.
##
## A projectile finds what it hits through LAYERS rather than through a group -
## it is an Area2D and that is what Area2D does - so "whose side is this shot
## on" has to be answered twice, in two different vocabularies. Both answers
## live here so they cannot drift apart, and so no scene file has to carry a
## bare 32 that nobody can read.
const LAYER_PLAYER_HURTBOX := 8
const LAYER_ENEMY_HURTBOX := 16
const LAYER_PLAYER_HITBOX := 32
const LAYER_ENEMY_HITBOX := 64

## Which layer this actor's attacks live on, and which they look for. The same
## split as hostile_group, for the half of the engine that speaks in layers.
var attack_layer: int = LAYER_PLAYER_HITBOX
var attack_mask: int = LAYER_ENEMY_HURTBOX

## The three vocabularies of "whose side", keyed by the one that decides them.
## Tables rather than a match, so adding a third faction is three entries and no
## new branches anywhere.
const GROUP_FOR: Dictionary = {
	WorldTypes.Faction.PLAYERS: &"players",
	WorldTypes.Faction.ENEMIES: &"enemies",
}
const HITBOX_LAYER_FOR: Dictionary = {
	WorldTypes.Faction.PLAYERS: LAYER_PLAYER_HITBOX,
	WorldTypes.Faction.ENEMIES: LAYER_ENEMY_HITBOX,
}
const HURTBOX_LAYER_FOR: Dictionary = {
	WorldTypes.Faction.PLAYERS: LAYER_PLAYER_HURTBOX,
	WorldTypes.Faction.ENEMIES: LAYER_ENEMY_HURTBOX,
}

## ONE declaration of whose side this is, from which everything else follows:
## the group enemies search, the group this side's weapons hunt, the layers its
## attacks live on and look for, and the faction its MODEL carries so that core/
## can reason about sides with no nodes in sight.
##
## They used to be set one at a time in each subclass. Four facts saying the same
## thing in four places is four chances for them to disagree, and the way they
## disagree is a bug that hits its own side.
func _join_faction(p_faction: WorldTypes.Faction) -> void:
	faction = p_faction
	if model != null:
		model.faction = p_faction
	if not GROUP_FOR.has(p_faction):
		return

	var opponent := (
		WorldTypes.Faction.ENEMIES
		if p_faction == WorldTypes.Faction.PLAYERS
		else WorldTypes.Faction.PLAYERS
	)

	# Typed locals rather than assigning a Dictionary read straight into a typed
	# field: that read is a Variant, and the warning it raises is treated as an
	# error, which skips the whole file rather than failing one line.
	var own_group: StringName = GROUP_FOR[p_faction]
	var enemy_group: StringName = GROUP_FOR[opponent]
	var layer: int = HITBOX_LAYER_FOR[p_faction]
	var mask: int = HURTBOX_LAYER_FOR[opponent]

	add_to_group(own_group)
	hostile_group = enemy_group
	attack_layer = layer
	attack_mask = mask

var placeholder_color: Color = Color.WHITE

## Knockback and recoil arrive here rather than in `velocity`, which is
## overwritten from the stats every frame. Decays on its own.
var impulse: Vector2 = Vector2.ZERO
@export var impulse_decay: float = 6.0

@onready var _shape: CollisionShape2D = $CollisionShape2D

func bind(p_model: EntityModel, p_data: EntityData, p_world: WorldModel) -> void:
	model = p_model
	data = p_data
	world = p_world

	if not model.died.is_connected(_on_model_died):
		model.died.connect(_on_model_died)
	if not model.revived.is_connected(_on_model_revived):
		model.revived.connect(_on_model_revived)

func _ready() -> void:
	if data != null:
		var circle := CircleShape2D.new()
		circle.radius = data.collider_radius
		_shape.shape = circle
	# Before the first frame, because a spawner sets `position` before add_child
	# and something can already ask where this is on the frame it appears.
	_publish_position()
	queue_redraw()

## THE ONE WRITE of the model's position, and the whole reason core/ can answer
## "what is within 90 units of here" without ever seeing a node.
##
## It is written from OUTSIDE the alive check on purpose: a corpse still has a
## place in the world, and an explosion centred on whatever was just killed reads
## the position off the model rather than off a node that may already be freed.
func _publish_position() -> void:
	if model != null:
		model.world_position = global_position

func _physics_process(delta: float) -> void:
	_publish_position()

	if model == null or not model.is_alive:
		return

	# Speed is read from the model every frame rather than cached, so a slow
	# status or a speed item takes effect immediately with no wiring.
	var direction := _get_move_direction(delta)
	velocity = direction * model.stats.get_stat(StatTypes.Stat.MOVEMENT_SPEED) + impulse
	impulse = impulse.lerp(Vector2.ZERO, clampf(impulse_decay * delta, 0.0, 1.0))
	move_and_slide()

	if world != null:
		global_position = world.clamp_to_bounds(global_position)

	# Again, AFTER the move. The call at the top is what keeps a corpse honest;
	# this one is what keeps a runner honest, and statuses tick below it - a
	# status reaching outwards must not measure from where its carrier was.
	_publish_position()

	# Each actor advances its own statuses. RunModel.tick() exists for headless
	# tests; calling both would tick players twice.
	model.tick_statuses(delta)

	queue_redraw()

## Overridden by subclasses: input for players, a MovementBehavior for enemies.
func _get_move_direction(_delta: float) -> Vector2:
	return Vector2.ZERO

## Enemies simply vanish. Players go down instead and override this - see
## Character, and RunTypes.DeathRule for who stands up again.
func _on_model_died() -> void:
	queue_free()

func _on_model_revived() -> void:
	queue_redraw()

# --- placeholder rendering -------------------------------------------------
#
# Drawn rather than sprited so the slice needs no art at all. Size comes from
# EntityData, so swapping in real sprites later is a data change.

func _draw() -> void:
	if data == null:
		return

	var radius := data.collider_radius

	# Downed: flattened, drained of colour, no health bar. It has to read as
	# "still there, but out" from across a 1920-wide screen, because in co-op
	# somebody else has to notice before the wave ends.
	if model != null and not model.is_alive:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, radius, placeholder_color.darkened(0.7))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, placeholder_color.darkened(0.4), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return

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
