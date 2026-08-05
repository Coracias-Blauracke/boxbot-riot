class_name SpawnGroup
extends RefCounted

## One spawn decision: this enemy, this many, arriving this way.
##
## The director used to return a FLAT Array[EnemyData], appending the same enemy
## `group_size` times. The spawner then placed each element with its own
## independent roll, so an authored "group of three" arrived at three unrelated
## points on the ring - up to opposite sides of the player. WaveEntry.group_size
## promised a cluster and the pipeline shredded it.
##
## Keeping the group intact all the way to placement is the entire reason this
## type exists. One group, one anchor, one arrival.

var enemy: EnemyData = null
var count: int = 1
var pattern: SpawnPattern = null
