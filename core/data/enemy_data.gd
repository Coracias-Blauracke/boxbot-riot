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

@export_group("Armament")
## What this bug attacks WITH, beyond simply touching you.
##
## The same WeaponData a player carries, on the same WeaponModel, aimed by the
## same TargetSelector - the whole weapon stack was already side-agnostic, and
## the one thing that was not is now Actor.hostile_group. A spitter is therefore
## an ordinary enemy with a weapon in the list, not a second attack system.
##
## Named `weapons` rather than `starting_weapons`: a bug never buys, sells or
## merges one, so there is no "starting" to distinguish from "later".
@export var weapons: Array[WeaponData] = []

## Whether the armament is DRAWN, and where the shot leaves from.
##
## False by default, because the default enemy is a BUG: a biter spits a glob
## out of itself, and a beetle holding a pistol is a different game. Off, the
## mount is invisible and sits at the body's centre, so the projectile leaves
## the creature rather than a rifle floating beside it.
##
## Kept as a flag rather than as two kinds of enemy, because a turret, a mech
## and a boss with a visible cannon are all things this roster will want, and
## they differ from a spitter in exactly this one respect. Whether an armament
## SHOWS is a property of the creature, not of the weapon.
@export var weapons_visible: bool = false

@export_group("Rewards")
@export var currency_reward: int = 1
