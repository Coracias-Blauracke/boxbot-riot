class_name EnemyData
extends EntityData

## An enemy definition. Bosses use this too - they are the same scene with a
## bigger collider, higher stats and a richer effect list, not a separate type.

@export var movement: MovementBehavior

@export_group("Separation")
## Keeps a swarm from collapsing into a single point. Deliberately a property of
## the enemy rather than of its MovementBehavior - otherwise every new behaviour
## would have to reimplement crowd handling.
##
## Radius is a multiple of collider_radius; weight is relative to the pull of
## the behaviour itself, so values below 1.0 still let the enemy close in.
@export var separation_radius_scale: float = 2.6
@export var separation_weight: float = 0.9

@export_group("Contact")
## Damage dealt by simply touching the target, and how often it repeats while
## the two stay in contact.
@export var contact_damage_interval: float = 0.6

@export_group("Rewards")
@export var gold_reward: int = 1
