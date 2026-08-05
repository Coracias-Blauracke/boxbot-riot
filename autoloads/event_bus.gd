extends Node

## GLOBAL bus - exclusively for events concerning the whole run, never
## individual entities. Events of the form "what happened to whom" (damage,
## healing, statuses, steps) travel through the local EffectDispatcher of the
## EntityModel in question.
##
## The split is deliberate: if everything went through here, every effect would
## begin by asking "does this event concern me?", and with 200 enemies on screen
## every poison application would wake every listener in the game.
##
## Rule of thumb: if an event has a specific addressee, it does not belong here.

signal run_started
signal run_ended

signal wave_started(wave_number: int)
signal wave_ended(wave_number: int)

signal shop_opened
signal shop_closed

signal map_changed
signal boss_spawned

signal player_joined(player_index: int)
signal player_left(player_index: int)
