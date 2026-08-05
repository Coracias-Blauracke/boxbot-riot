class_name HealEvent
extends EventPayload

## Healing mirrors damage: a pipeline that can scale or block it before it
## lands, then a notification carrying what actually happened.
##
## `applied` is not the same as `amount` - healing at full HP applies nothing,
## which is exactly what a "gain shield for overhealing" effect needs to know.

var source: EntityModel = null
var target: EntityModel = null

var amount: float = 0.0
var applied: float = 0.0
