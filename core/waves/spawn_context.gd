class_name SpawnContext
extends RefCounted

## Everything a SpawnPattern needs to know about the world right now, as PLAIN
## DATA.
##
## This exists so placement can live in core/ at all. A pattern wants the
## camera's view rectangle and where the players are standing, and both of those
## are scene facts - but handed over as Vector2 they stop being scene facts and
## become numbers, which is the whole trick that keeps core/ Node-free and
## testable without a game window.
##
## Filled by the spawner once per spawn event and thrown away. Deliberately not
## cached anywhere: a stale view rectangle would place enemies against a frame
## that has already moved.

## LIVING players only. A downed player must not attract an ambush - the group
## would arrive beside a corpse while the survivors are left alone.
var player_positions: PackedVector2Array = PackedVector2Array()

## Centre and size of what is currently on screen, in world units.
var view_centre: Vector2 = Vector2.ZERO
var view_size: Vector2 = Vector2.ZERO

## For bounds clamping. WorldModel is core, so this costs nothing.
var world: WorldModel = null
