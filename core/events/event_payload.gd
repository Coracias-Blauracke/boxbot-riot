class_name EventPayload
extends RefCounted

## An event is an OBJECT, not a list of signal arguments.
##
## There is one important reason: adding a new field six months from now must
## not break two hundred existing effects. With `damage_taken(a, b, c)` every
## signature change breaks every listener. With an object, it breaks nobody.
##
## For PIPELINE hooks the payload is MUTABLE: effects read and overwrite fields
## in turn, and the emitter reads the result after the whole pipeline has run.

## LIFETIME: a payload is transient - it lives for one dispatch and is then
## dropped. An effect must NEVER store one in a field. Payloads reference
## entities, entities own the dispatcher, the dispatcher owns the effect, so
## caching a payload closes a reference cycle that RefCounted cannot collect.
## If an effect needs to remember something from an event, copy out the values
## it needs (or hold a weakref to the entity) into `inst.state`.

## Loose bag for run-wide references (world model, RNG, wave number).
## Deliberately untyped so that core/ stays independent of the gameplay layer.
var context: Dictionary = {}

## Setting this to true stops further processing in a pipeline.
var cancelled: bool = false
