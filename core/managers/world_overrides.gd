class_name WorldOverrides
extends RefCounted

## Registry of DISCRETE world-level choices, and the only place in the codebase
## where a conflict can occur.
##
## Everything else is conflict-free by construction:
##   per-player + continuous  -> each entity has its own StatsManager
##   per-player + discrete    -> shop payment, weapon slots: nobody to clash with
##   world     + continuous   -> MAP_SIZE modifiers simply sum
##   world     + discrete     -> HERE. Two players demanding different arena
##                               shapes is the whole problem space.
##
## Note that agreement is not conflict: two players both wanting a circle is a
## single candidate value, resolved without a roll.

signal resolved(key: StringName, winner: Variant, was_contested: bool)

class Claim:
	var value: Variant
	var source: Variant
	var claimant: int  ## player index - gives the sort a stable tiebreaker

	func _init(p_value: Variant, p_source: Variant, p_claimant: int) -> void:
		value = p_value
		source = p_source
		claimant = p_claimant

var _rng: RunRandom
var _claims: Dictionary = {}   # key:StringName -> Array[Claim]
var _winners: Dictionary = {}  # key:StringName -> Variant

func _init(rng: RunRandom) -> void:
	_rng = rng

func claim(key: StringName, value: Variant, source: Variant, claimant: int = 0) -> void:
	if not _claims.has(key):
		_claims[key] = []
	(_claims[key] as Array).append(Claim.new(value, source, claimant))
	_resolve(key)

func release(key: StringName, source: Variant) -> void:
	if not _claims.has(key):
		return
	var kept: Array = []
	for entry in (_claims[key] as Array):
		if (entry as Claim).source != source:
			kept.append(entry)
	_claims[key] = kept
	_resolve(key)

func get_value(key: StringName, fallback: Variant = null) -> Variant:
	return _winners.get(key, fallback)

## True when at least two DIFFERENT values are being claimed. Drives UI copy
## like "Arena: Circle (won the roll against Hexagon)".
func is_contested(key: StringName) -> bool:
	return _distinct_values(key).size() > 1

func get_candidates(key: StringName) -> Array:
	return _distinct_values(key)

# --- internals -------------------------------------------------------------

func _distinct_values(key: StringName) -> Array:
	var seen: Array = []
	for entry in _claims.get(key, []):
		if not seen.has((entry as Claim).value):
			seen.append((entry as Claim).value)
	return seen

## Resolved ONCE per change of the claim set, never per frame - re-rolling
## continuously would make the arena flicker between shapes.
func _resolve(key: StringName) -> void:
	var candidates := _distinct_values(key)

	if candidates.is_empty():
		_winners.erase(key)
		resolved.emit(key, null, false)
		return

	if candidates.size() == 1:
		_winners[key] = candidates[0]
		resolved.emit(key, candidates[0], false)
		return

	# Sort before rolling. Without a stable order the roll would depend on the
	# order claims happened to arrive, which would defeat the seeded RNG.
	var ordered: Array = (_claims[key] as Array).duplicate()
	ordered.sort_custom(
		func(a: Claim, b: Claim) -> bool:
			if a.claimant != b.claimant:
				return a.claimant < b.claimant
			return str(a.value) < str(b.value)
	)

	var ordered_values: Array = []
	for entry in ordered:
		if not ordered_values.has((entry as Claim).value):
			ordered_values.append((entry as Claim).value)

	var winner: Variant = _rng.pick(RunRandom.Stream.WORLD, ordered_values)
	_winners[key] = winner
	resolved.emit(key, winner, true)
