class_name RunRandom
extends RefCounted

## All randomness in the run, owned in one place and derived from one seed.
##
## SEPARATE STREAMS are the point, not a refinement. Sharing one generator
## between combat and the shop means firing one extra bullet changes what the
## shop offers - which destroys reproducibility and makes balance comparisons
## between two runs impossible. Each concern advances its own stream.
##
## `sub` derives an independent sub-stream, used for per-player shops: the order
## in which four players hit reroll must not change what the others are offered.

enum Stream {
	COMBAT,
	SHOP,
	SPAWNS,
	DROPS,
	## Reserved for resolving world-level conflicts, so that rolling the arena
	## shape never perturbs combat or shop rolls.
	WORLD,
}

var run_seed: int = 0

var _generators: Dictionary = {}  # key:int -> RandomNumberGenerator

func _init(p_seed: int = 0) -> void:
	run_seed = p_seed if p_seed != 0 else randi()

func chance(stream: Stream, probability: float, sub: int = 0) -> bool:
	if probability <= 0.0:
		return false
	if probability >= 1.0:
		return true
	return _generator_for(stream, sub).randf() < probability

func randf_in(stream: Stream, from: float, to: float, sub: int = 0) -> float:
	return _generator_for(stream, sub).randf_range(from, to)

func randi_in(stream: Stream, from: int, to: int, sub: int = 0) -> int:
	return _generator_for(stream, sub).randi_range(from, to)

func pick(stream: Stream, options: Array, sub: int = 0) -> Variant:
	if options.is_empty():
		return null
	return options[_generator_for(stream, sub).randi_range(0, options.size() - 1)]

func weighted_pick(stream: Stream, options: Array, weights: PackedFloat32Array, sub: int = 0) -> Variant:
	if options.is_empty() or options.size() != weights.size():
		return null

	var total := 0.0
	for weight in weights:
		total += weight
	if total <= 0.0:
		return pick(stream, options, sub)

	var roll := _generator_for(stream, sub).randf() * total
	var running := 0.0
	for i in options.size():
		running += weights[i]
		if roll < running:
			return options[i]
	return options[options.size() - 1]

# --- persistence -----------------------------------------------------------

## The stream positions must go into the save file, otherwise a player can save
## before the shop, dislike the offer, reload and reroll for free.
func to_dict() -> Dictionary:
	var states := {}
	for key in _generators:
		states[key] = (_generators[key] as RandomNumberGenerator).state
	return {"seed": run_seed, "states": states}

func from_dict(data: Dictionary) -> void:
	run_seed = int(data.get("seed", 0))
	_generators.clear()
	var states: Dictionary = data.get("states", {})
	for key in states:
		var generator := RandomNumberGenerator.new()
		generator.seed = _seed_for(int(key))
		generator.state = int(states[key])
		_generators[int(key)] = generator

# --- internals -------------------------------------------------------------

## Not named _get() - that is a reserved Object virtual and shadowing it makes
## the whole script fail to compile.
func _generator_for(stream: Stream, sub: int) -> RandomNumberGenerator:
	var key := _key(stream, sub)
	if not _generators.has(key):
		var generator := RandomNumberGenerator.new()
		generator.seed = _seed_for(key)
		_generators[key] = generator
	return _generators[key]

func _key(stream: Stream, sub: int) -> int:
	return int(stream) * 1000 + sub

## Derived deterministically from the run seed, so every stream is reproducible
## from that one number alone.
func _seed_for(key: int) -> int:
	return hash(str(run_seed) + ":" + str(key))
