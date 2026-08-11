class_name SpawnRequest
extends RefCounted

## "Put this many of these, here." Something in core/ asking the world for
## entities it cannot create itself.
##
## THE MIRROR OF EntityModel.world_position. The view writes where things are so
## core/ can do geometry; this is core/ writing what should exist so the view can
## build it. Neither side gains a reference to the other, and core/ behaves
## identically when nothing is listening - which is what keeps the headless suite
## and the running game the same code.
##
## It carries EntityData rather than an enemy specifically, and no scene path at
## all. What NODE a piece of data becomes is the view's business and nothing
## core/ should be able to name; the same channel therefore serves a splitter's
## children, a hive's brood, and later a summoned turret or a pickup dropped by a
## corpse, without learning about any of them.
##
## Deliberately NOT a queue on RunModel. An effect firing on a dying enemy cannot
## reach the run - it has no reference to it and must not be given one, because
## RefCounted has no cycle collector - and it does not need to: the entity it
## fires on is already the thing the view is listening to.

## What to build. EnemyData today; the type is the view's dispatch key.
var data: EntityData = null

var count: int = 1

## Where the asking entity was, read from its world_position. Anchored patterns
## place around it; the others ignore it entirely.
var origin: Vector2 = Vector2.ZERO

## HOW they arrive. Null means the view's default, exactly as WaveEntry.pattern
## being null falls back to the wave spawner's own - so a request is placed by
## the same axis a wave is, and "these children walk in from off screen instead"
## is one authored resource rather than a branch.
var pattern: SpawnPattern = null

## Who asked, weakly. For kill credit and for whose side the children are on.
##
## WEAK because the usual requester is a corpse: an enemy that splits on death is
## already dead when this is drained, and a strong reference here would keep its
## whole model - stats, effects, statuses - alive for as long as the request
## lives. Everything the view needs is copied out above.
var requester: WeakRef = null

func get_requester() -> EntityModel:
	return requester.get_ref() as EntityModel if requester != null else null
