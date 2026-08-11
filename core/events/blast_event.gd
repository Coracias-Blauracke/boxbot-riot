class_name BlastEvent
extends EventPayload

## What one area attack did: where it went off, how big it turned out and who it
## caught.
##
## Emitted on the source's `blast_resolved` signal once the damage has landed, so
## the view has ONE thing to listen to for every explosion in the game - a bug
## dying, an item, a grenade - and core/ needs no idea that anything is drawing.
## That is the mirror of EntityModel.world_position: the view writes where things
## are, the model says what happened there.
##
## Carries the BlastData that produced it rather than copying its presentation
## fields out. The authored resource is already the answer to "what should this
## look like", exactly as EntityData.collider_radius is, and duplicating half of
## it here would be two places to keep in step.
##
## NOTHING MAY KEEP ONE. Like every payload it references entities, and an entity
## owns the dispatcher and the signal connection that delivered this - so a
## listener that stores the event closes a cycle RefCounted cannot collect.
## Measured at 48 leaked objects, by a test that did exactly that. Copy out what
## you need, which is what BlastFlash.setup does.

var blast: BlastData = null

var source: EntityModel = null

## The weapon that set it off, when one did. Null for an explosion that belongs
## to the entity itself - a Popper, an item triggering on a kill.
var weapon: EntityModel = null

var centre: Vector2 = Vector2.ZERO

## AFTER AREA_SIZE, so this is what actually happened rather than what was
## authored. The view draws this one.
var radius: float = 0.0

## Damage at the centre, before each target's own defences. What a victim really
## took is in damage_dealt.
var amount: float = 0.0
var damage_type: StatTypes.DamageType = StatTypes.DamageType.ELEMENTAL
var is_crit: bool = false

## Everything the blast reached, in the order it was resolved - nearest first
## when a target cap made the order matter.
var victims: Array[EntityModel] = []

## Total that actually landed, summed across victims after armor, dodge and
## every TAKE_DAMAGE effect had their say.
var damage_dealt: float = 0.0
