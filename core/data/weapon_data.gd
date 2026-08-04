class_name WeaponData
extends EntityData

## ONE weapon definition covering guns, melee, beams and summons. The four
## resources below are independent axes; a weapon is a point in that space
## rather than a class:
##
##   pistol   = Instant + Projectile + Single
##   shotgun  = Instant + Projectile + Cone(8)
##   minigun  = Windup  + Projectile + Cone(1)
##   laser    = Channel + Beam       + Single
##   sword    = Instant + MeleeSweep + -
##
## Combinations nobody planned for - a channelled shotgun, a spinning-up melee
## flurry - fall out for free, because the axes do not know about each other.

enum DeliveryKind {
	PROJECTILE,
	MELEE_SWEEP,
	BEAM,
	SUMMON,
}

@export_group("Axes")
@export var firing: FiringPattern
@export var spread: SpreadPattern
@export var targeting: TargetSelector
@export var delivery: DeliveryKind = DeliveryKind.PROJECTILE

@export_group("Delivery payload")
## Used when delivery is PROJECTILE.
@export var projectile: ProjectileData
@export var projectile_scene: PackedScene

@export_group("Heat")
## 0 disables heat entirely, which is how most weapons will be configured.
## Capacity and dissipation are stats, so items can widen or vent them.
@export var heat_per_shot: float = 0.0

@export_group("Damage falloff")
## Distance in world units at which damage starts dropping, and where it bottoms
## out. A strong balance lever: it stops shotguns being good at every range.
@export var falloff_start: float = 0.0
@export var falloff_end: float = 0.0
@export_range(0.0, 1.0) var falloff_multiplier: float = 1.0

@export_group("Feel")
## Push applied to the wielder on firing. Almost always 0; a shotgun that shoves
## you backwards turns recoil into a movement option.
@export var recoil: float = 0.0
