class_name TickEvent
extends EventPayload

## Payload for ON_TICK, the one hook that fires on a schedule.
##
## Carries the census rather than making effects reach for a global, so an
## effect asking "how many enemies are burning" gets the answer through its
## argument like everything else here does.

var delta: float = 0.0
var census: WorldCensus = null
