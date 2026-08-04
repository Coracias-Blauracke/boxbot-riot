class_name EnemyData
extends EntityData

## An enemy definition. Bosses use this too - they are the same scene with a
## bigger collider, higher stats and a richer effect list, not a separate type.

@export var movement: MovementBehavior

@export_group("Contact")
## Damage dealt by simply touching the target, and how often it repeats while
## the two stay in contact.
@export var contact_damage_interval: float = 0.6

@export_group("Rewards")
@export var gold_reward: int = 1
