class_name StatusEvent
extends EventPayload

## Applying a status is a two-sided affair, mirroring the damage model:
## the applier's offence pipeline runs first, the target's defence pipeline
## second, and only then does the status land.
##
## Both sides also receive a notification afterwards - ON_STATUS_APPLIED on the
## applier and ON_STATUS_RECEIVED on the target - so that "whoever poisons an
## enemy gains a buff" is an ordinary effect rather than a special case.

var applier: EntityModel = null
var target: EntityModel = null

var definition: StatusEffect = null
var status_id: StringName = &""

var stacks: int = 1
var duration: float = 0.0

## Effects in the CALCULATE_STATUS pipeline may raise or lower this.
var chance: float = 1.0

## Set by StatusManager once the status has actually landed.
var applied: bool = false
